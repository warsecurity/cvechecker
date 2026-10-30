package com.cvewatch.app;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.PowerManager;
import android.util.Log;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.File;
import java.io.FileWriter;
import java.io.FileReader;
import java.util.ArrayList;
import java.util.List;

/**
 * Runs inside system_server (loaded by Hook), so Android and ColorOS cannot kill it.
 * An alarm wakes it every cycle. It reads the settings from the app, asks NVD for CVEs
 * published since the last cycle, and notifies for the ones that match the watchlist.
 * It never touches the app's files: everything goes through ConfigProvider.
 */
final class SysScanner {
    private static final String TAG = "CVEChecker";
    private static final String TICK = "com.cvewatch.app.TICK";
    private static final Uri PROVIDER = Uri.parse("content://com.cvewatch.app.cfg");
    private static final File STATE = new File("/data/system/cvewatch_state.json");
    private static boolean started;

    private final Context ctx;
    private JSONObject state = new JSONObject();

    private SysScanner(Context ctx) { this.ctx = ctx; }

    static synchronized void start(Context ctx) {
        if (started) return;
        started = true;
        new Thread(() -> new SysScanner(ctx).boot(), "cve-boot").start();
    }

    static final class TickReceiver extends BroadcastReceiver {
        private final SysScanner owner;
        TickReceiver(SysScanner owner) { this.owner = owner; }
        @Override public void onReceive(Context c, Intent i) {
            new Thread(new ScanTask(owner), "cve-scan").start();
        }
    }

    static final class ScanTask implements Runnable {
        private final SysScanner owner;
        ScanTask(SysScanner owner) { this.owner = owner; }
        @Override public void run() { owner.cycle(); }
    }

    private void boot() {
        try {
            Thread.sleep(45_000);
            loadState();
            BroadcastReceiver receiver = new TickReceiver(this);
            IntentFilter filter = new IntentFilter(TICK);
            if (Build.VERSION.SDK_INT >= 33) ctx.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED);
            else ctx.registerReceiver(receiver, filter);
            Log.i(TAG, "system scanner started");
            scheduleIn(15_000);
        } catch (Throwable t) {
            Log.e(TAG, "boot failed", t);
        }
    }

    void cycle() {
        PowerManager.WakeLock lock = ((PowerManager) ctx.getSystemService(Context.POWER_SERVICE))
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "cvechecker:scan");
        lock.acquire(3 * 60_000L);
        long next = 10 * 60_000L;
        String error = null;
        int found = 0;
        try {
            JSONObject cfg = config();
            next = cfg.optLong("interval", 60) * 60_000L;
            found = scan(cfg);
        } catch (Throwable t) {
            error = String.valueOf(t.getMessage());
            Log.w(TAG, "cycle failed: " + error);
        } finally {
            beat(found, error);
            scheduleIn(error == null ? next : 10 * 60_000L);
            if (lock.isHeld()) lock.release();
        }
    }

    /** Asks NVD for CVEs published since the last successful cycle and notifies matches. */
    private int scan(JSONObject cfg) throws Exception {
        List<String> watch = new ArrayList<>();
        JSONArray w = cfg.optJSONArray("watch");
        for (int i = 0; w != null && i < w.length(); i++) watch.add(w.getString(i));
        String key = cfg.optString("key").trim();
        double threshold = cfg.optDouble("threshold", 7.0);

        long now = System.currentTimeMillis();
        deliverPending();
        if (key.isEmpty()) { remember(now); return 0; }
        long last = state.optLong("last", 0);
        if (last <= 0) {
            long appLast = cfg.optLong("lastChange", 0);
            if (appLast <= 0) { remember(now); return 0; }
            last = appLast;
        }
        long since = Math.max(last, now - 119L * 86_400_000L);

        JSONArray notified = state.optJSONArray("notified");
        if (notified == null) notified = new JSONArray();
        int sent = 0, newCount = 0, critical = 0, high = 0, start = 0, total;
        String range = "pubStartDate=" + Nvd.stamp(since - 120_000L) + "&pubEndDate=" + Nvd.stamp(now);
        do {
            JSONObject page = Nvd.page(range, start, key);
            total = page.getInt("totalResults");
            JSONArray items = page.getJSONArray("vulnerabilities");
            if (items.length() == 0) break;
            for (Nvd.Cve cve : Nvd.parseAll(items)) {
                if (contains(notified, cve.id)) continue;
                notified.put(cve.id);
                newCount++;
                if (cve.score >= 9) critical++;
                else if (cve.score >= 7) high++;
                String hit = Nvd.match(cve, watch, threshold);
                if (hit == null) continue;
                JSONObject alert = new JSONObject().put("id", cve.id)
                        .put("title", "Your watchlist \"" + hit + "\" has been exploited")
                        .put("text", cve.id + " (" + cve.severity() + "): " + cve.description);
                queue(alert);
                sent++;
            }
            start += items.length();
            if (start < total) Thread.sleep(Nvd.pause(key));
        } while (start < total);

        long summaryAt = state.optLong("summaryAt", 0);
        if (sent == 0 && newCount > 0 && now - summaryAt >= 6L * 3600_000L) {
            String text = newCount + " new CVE" + (newCount == 1 ? "" : "s") + " detected. "
                    + critical + " critical and " + high + " high severity. Open CVE Checker to review them.";
            queue(new JSONObject().put("id", "new-cves").put("title", "New CVEs detected").put("text", text));
            state.put("summaryAt", now);
        }

        state.put("notified", trim(notified, 300));
        remember(now);
        deliverPending();
        return sent;
    }

    // ---- delivery -------------------------------------------------------------------------

    private void queue(JSONObject alert) throws Exception {
        JSONArray p = state.optJSONArray("pending");
        if (p == null) p = new JSONArray();
        if (p.length() >= 50) return;
        p.put(alert);
        state.put("pending", p);
    }

    /** Sends queued alerts through the app. If the app cannot be reached, posts them as the system instead. */
    private void deliverPending() throws Exception {
        JSONArray p = state.optJSONArray("pending");
        if (p == null || p.length() == 0) return;
        int processed = 0;
        for (int i = 0; i < p.length() && processed < 10; i++, processed++) {
            JSONObject a = p.getJSONObject(i);
            Bundle extras = new Bundle();
            extras.putString("title", a.getString("title"));
            extras.putString("text", a.getString("text"));
            Bundle reply = null;
            try { reply = ctx.getContentResolver().call(PROVIDER, "alert", a.getString("id"), extras); } catch (Throwable ignored) { }
            if (reply == null) postAsSystem(a.getString("id"), a.getString("title"), a.getString("text"));
        }
        JSONArray left = new JSONArray();
        for (int i = processed; i < p.length(); i++) left.put(p.get(i));
        state.put("pending", left);
        saveState();
    }

    private void postAsSystem(String id, String title, String text) {
        NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
        nm.createNotificationChannel(new NotificationChannel("cvewatch", "CVE alerts", NotificationManager.IMPORTANCE_HIGH));
        Intent openApp = new Intent().setComponent(new ComponentName("com.cvewatch.app", "com.cvewatch.app.MainActivity"))
                .putExtra("showLatest", true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent open = PendingIntent.getActivity(ctx, Math.abs(id.hashCode()) % 100000, openApp,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        nm.notify(Math.abs(id.hashCode()) % 100000 + 100, new Notification.Builder(ctx, "cvewatch").setSmallIcon(android.R.drawable.stat_sys_warning)
                .setContentTitle(title).setContentText(text).setStyle(new Notification.BigTextStyle().bigText(text))
                .setContentIntent(open).setAutoCancel(true).build());
    }

    // ---- app link ---------------------------------------------------------------------------

    private JSONObject config() {
        try {
            Bundle b = ctx.getContentResolver().call(PROVIDER, "config", null, null);
            if (b != null && b.getString("json") != null) {
                JSONObject cfg = new JSONObject(b.getString("json"));
                state.put("cfg", cfg);
                saveState();
                return cfg;
            }
        } catch (Throwable t) {
            Log.w(TAG, "app not reachable, using saved settings");
        }
        JSONObject saved = state.optJSONObject("cfg");
        return saved != null ? saved : new JSONObject();
    }

    private void beat(int found, String error) {
        try {
            Bundle b = new Bundle();
            b.putLong("time", System.currentTimeMillis());
            b.putInt("found", found);
            b.putString("error", error);
            ctx.getContentResolver().call(PROVIDER, "beat", null, b);
        } catch (Throwable ignored) { }
    }

    // ---- alarm and state --------------------------------------------------------------------

    private void scheduleIn(long delay) {
        AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
        PendingIntent pi = PendingIntent.getBroadcast(ctx, 0, new Intent(TICK).setPackage(ctx.getPackageName()),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        long at = System.currentTimeMillis() + delay;
        try { am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi); }
        catch (Throwable t) { am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi); }
    }

    private void remember(long time) throws Exception { state.put("last", time); saveState(); }

    private void loadState() {
        try (FileReader r = new FileReader(STATE)) {
            StringBuilder sb = new StringBuilder();
            char[] buf = new char[4096];
            int n;
            while ((n = r.read(buf)) != -1) sb.append(buf, 0, n);
            state = new JSONObject(sb.toString());
        } catch (Throwable ignored) { state = new JSONObject(); }
    }

    private void saveState() {
        try (FileWriter w = new FileWriter(STATE)) { w.write(state.toString()); } catch (Throwable ignored) { }
    }

    private static boolean contains(JSONArray a, String s) {
        for (int i = 0; i < a.length(); i++) if (s.equals(a.optString(i))) return true;
        return false;
    }

    private static JSONArray trim(JSONArray a, int max) throws Exception {
        if (a.length() <= max) return a;
        JSONArray out = new JSONArray();
        for (int i = a.length() - max; i < a.length(); i++) out.put(a.get(i));
        return out;
    }
}
