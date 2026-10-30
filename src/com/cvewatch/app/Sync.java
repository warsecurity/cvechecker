package com.cvewatch.app;

import android.content.Context;
import android.content.SharedPreferences;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.List;
import java.util.Locale;
import java.util.TimeZone;
import java.util.concurrent.locks.ReentrantLock;

/** Downloads and maintains the local NVD CVE database. A verified NVD key is required for every request. */
final class Sync {
    static final ReentrantLock LOCK = new ReentrantLock();
    static volatile boolean stopRequested;

    /** Raised when the user stops a download from the UI. */
    static final class Stopped extends Exception { Stopped() { super("Stopped by user"); } }
    static volatile String state = "idle"; // idle, running, ready, error
    static volatile String note = "";
    static volatile int percent;
    static volatile int revision;
    static volatile int done;
    static volatile int total;

    private static final String KEV_URL = "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json";
    private static final long DAY = 86_400_000L;

    /** Latest mode samples the newest records of this many years. */
    static final int YEARS = 10;
    static final int PER_YEAR = 1500;
    /** Full mode uses small batches plus a pause so a 500k+ download stays gentle. */
    private static final int GENTLE_PAGE = 400;

    private static int cachedCount;
    private static int cachedRevision = -1;

    private Sync() {}

    static boolean running() { return LOCK.isLocked(); }

    static void stop() { stopRequested = true; }

    static boolean due(Context c) {
        SharedPreferences p = Prefs.get(c);
        if (Prefs.paused(c)) return false;
        long wait = Prefs.intervalMinutes(c) * 60_000L - 60_000L;
        return Prefs.hasKey(c) && p.getBoolean("complete", false)
                && System.currentTimeMillis() - p.getLong("lastRun", 0) >= wait;
    }

    static void run(Context context) { run(context, false, false); }

    /** forceFull clears the local cache and reloads it with the mode chosen in Settings. */
    static void run(Context context, boolean forceFull) { run(context, forceFull, false); }

    /** resync never clears the cache: it only checks for new or modified CVEs. */
    static void run(Context context, boolean forceFull, boolean resync) {
        if (!LOCK.tryLock()) return;
        Context app = context.getApplicationContext();
        SharedPreferences prefs = Prefs.get(app);
        try {
            stopRequested = false;
            Prefs.setPaused(app, false);
            state = "running"; note = ""; percent = 0; done = 0; total = 0;
            String key = Prefs.apiKey(app);
            String validation = testKey(key);
            if (!validation.startsWith("Key accepted")) throw new Exception(validation);
            prefs.edit().putBoolean("verified", true).putLong("verifiedAt", System.currentTimeMillis()).apply();

            String requestedMode = Prefs.mode(app);
            String previousMode = prefs.getString("loadedMode", "");
            if (forceFull || (!resync && prefs.getBoolean("complete", false) && !requestedMode.equals(previousMode))) {
                Db.get(app).clear();
                prefs.edit().putBoolean("complete", false).putInt("offset", 0).putInt("total", 0)
                        .putInt("done", 0).putLong("lastChange", 0).putLong("lastRun", 0).apply();
            }
            if (prefs.getBoolean("complete", false)) loadChanges(app);
            else if ("all".equals(requestedMode)) loadAll(app);
            else loadLatest(app);

            markExploited(app);
            prefs.edit().putLong("lastRun", System.currentTimeMillis()).apply();
            percent = 100; state = "ready"; note = "Database up to date";
        } catch (Stopped stopped) {
            state = "paused"; note = "Paused. Tap Resume fetching to continue.";
            Prefs.setPaused(app, true);
            Prefs.log(app, "Download paused by user at " + done + " records");
        } catch (Throwable e) {
            state = "error"; note = String.valueOf(e.getMessage());
            if (note.contains("401") || note.contains("403")) prefs.edit().putBoolean("verified", false).apply();
            Prefs.log(app, "Sync stopped: " + note);
        } finally {
            revision++;
            LOCK.unlock();
        }
    }

    /**
     * Default mode: fetch the newest records in each of the last YEARS calendar years.
     * NVD limits published-date windows to 120 days, so each year is walked backwards in
     * non-overlapping 119-day chunks. The API orders results by published date, so the newest
     * records in each chunk are taken from the tail of the result set.
     */
    private static void loadLatest(Context app) throws Exception {
        SharedPreferences prefs = Prefs.get(app);
        String key = Prefs.apiKey(app);
        Db db = Db.get(app);
        int currentYear = yearNow();
        int completed = 0;
        int estimate = YEARS * PER_YEAR;
        List<String> watch = Prefs.watchlist(app);
        double threshold = Prefs.threshold(app);
        List<Nvd.Cve> matched = new ArrayList<>();
        progress(app, 0, estimate);

        for (int y = 0; y < YEARS; y++) {
            int year = currentYear - y;
            int remaining = PER_YEAR;
            long yearStart = utc(year, 0);
            long cursor = Math.min(utc(year + 1, 0) - 1000L, System.currentTimeMillis());
            while (cursor >= yearStart && remaining > 0) {
                if (stopRequested) throw new Stopped();
                long from = Math.max(yearStart, cursor - 119L * DAY);
                String params = "pubStartDate=" + Nvd.stamp(from) + "&pubEndDate=" + Nvd.stamp(cursor);
                int available = Nvd.count(params, key);
                if (available > 0) {
                    Thread.sleep(Nvd.pause(key));
                    int take = Math.min(remaining, available);
                    int startIndex = Math.max(0, available - take);
                    JSONObject response = Nvd.page(params, startIndex, take, key);
                    JSONArray items = response.optJSONArray("vulnerabilities");
                    int got = items == null ? 0 : items.length();
                    if (got > 0) {
                        List<Nvd.Cve> parsed = Nvd.parseAll(items);
                        db.save(parsed, true, null);
                        if (!watch.isEmpty()) {
                            for (Nvd.Cve cve : parsed) {
                                if (matched.size() >= 20) break;
                                if (Nvd.match(cve, watch, threshold) != null) matched.add(cve);
                            }
                        }
                        remaining -= got;
                        completed += got;
                    }
                }
                estimate = completed + Math.max(0, YEARS - y - 1) * PER_YEAR + remaining;
                progress(app, completed, estimate);
                if (remaining <= 0) break;
                cursor = from - 1000L;
                if (cursor >= yearStart) Thread.sleep(Nvd.pause(key));
            }
            if (y < YEARS - 1) Thread.sleep(Nvd.pause(key));
        }
        int actual = db.count();
        prefs.edit().putBoolean("complete", true).putString("loadedMode", "latest")
                .putLong("lastChange", System.currentTimeMillis()).putInt("done", completed).putInt("total", completed).apply();
        done = completed;
        total = completed;
        percent = 100;
        alertFor(app, matched);
        Prefs.log(app, "Latest CVEs loaded: " + actual + " records across " + YEARS + " years");
    }

    /** Full history. Small batches and one pause per batch keep memory and battery flat. */
    private static void loadAll(Context app) throws Exception {
        SharedPreferences prefs = Prefs.get(app);
        String key = Prefs.apiKey(app);
        Db db = Db.get(app);
        int start = prefs.getInt("offset", 0);
        int count = prefs.getInt("total", 0);
        List<String> watch = Prefs.watchlist(app);
        double threshold = Prefs.threshold(app);
        List<Nvd.Cve> matched = new ArrayList<>();
        progress(app, start, count);
        do {
            if (stopRequested) throw new Stopped();
            JSONObject page = Nvd.page("", start, GENTLE_PAGE, key);
            count = page.optInt("totalResults", count);
            JSONArray items = page.optJSONArray("vulnerabilities");
            if (items == null || items.length() == 0) break;
            List<Nvd.Cve> parsed = Nvd.parseAll(items);
            db.save(parsed, true, null);
            if (!watch.isEmpty()) {
                for (Nvd.Cve cve : parsed) {
                    if (matched.size() >= 20) break;
                    if (Nvd.match(cve, watch, threshold) != null) matched.add(cve);
                }
            }
            start += items.length();
            prefs.edit().putInt("offset", start).putInt("total", count).apply();
            progress(app, start, count);
            if (start < count) Thread.sleep(Nvd.pause(key));
        } while (start < count);
        prefs.edit().putBoolean("complete", true).putString("loadedMode", "all")
                .putLong("lastChange", System.currentTimeMillis()).putInt("done", start).putInt("total", count).apply();
        alertFor(app, matched);
        Prefs.log(app, "Full database loaded: " + count + " CVEs");
    }

    /** Fetch CVEs published or modified since the previous successful run. */
    private static void loadChanges(Context app) throws Exception {
        SharedPreferences prefs = Prefs.get(app);
        long end = System.currentTimeMillis();
        long since = Math.min(end, Math.max(prefs.getLong("lastChange", end), end - 119 * DAY));
        List<Nvd.Cve> fresh = new ArrayList<>();
        note = "Checking for new and modified CVEs";
        pull(app, "lastModStartDate=" + Nvd.stamp(since - 300_000L) + "&lastModEndDate=" + Nvd.stamp(end), false, fresh);
        prefs.edit().putLong("lastChange", end).apply();
        alertFor(app, fresh);
        done = Db.get(app).count(); total = done;
    }

    private static void pull(Context app, String params, boolean replace, List<Nvd.Cve> fresh) throws Exception {
        String key = Prefs.apiKey(app);
        int start = 0, count;
        do {
            if (stopRequested) throw new Stopped();
            JSONObject page = Nvd.page(params, start, 1000, key);
            count = page.optInt("totalResults", 0);
            JSONArray items = page.optJSONArray("vulnerabilities");
            if (items == null || items.length() == 0) break;
            Db.get(app).save(Nvd.parseAll(items), replace, fresh);
            start += items.length();
            progress(app, start, count);
            if (start < count) Thread.sleep(Nvd.pause(key));
        } while (start < count);
    }

    private static void progress(Context app, int finished, int planned) {
        done = finished;
        total = planned;
        percent = planned <= 0 ? 99 : Math.max(1, Math.min(99, (int) (100L * finished / planned)));
        Prefs.get(app).edit().putInt("done", finished).putInt("total", planned).apply();
        revision++;
    }

    private static void alertFor(Context app, List<Nvd.Cve> fresh) {
        List<String> watch = Prefs.watchlist(app);
        double threshold = Prefs.threshold(app);
        int sent = 0;
        for (Nvd.Cve c : fresh) {
            String hit = Nvd.match(c, watch, threshold);
            if (hit == null || sent >= 8) continue;
            Notify.alert(app, c.id, "Your watchlist \"" + hit + "\" has been exploited",
                    c.id + " (" + c.severity() + "): " + c.description);
            sent++;
        }
        if (sent == 0 && !fresh.isEmpty()) {
            int critical = 0, high = 0;
            for (Nvd.Cve c : fresh) {
                if (c.score >= 9) critical++;
                else if (c.score >= 7) high++;
            }
            Notify.alert(app, "new-cves", fresh.size() + " new CVE" + (fresh.size() == 1 ? "" : "s") + " detected",
                    critical + " critical and " + high + " high severity. Open CVE Checker to review them.");
        }
        Prefs.log(app, "Sync finished: " + fresh.size() + " new CVEs, " + sent + " alerts");
    }

    private static void markExploited(Context app) {
        try {
            JSONArray list = new JSONObject(Nvd.get(KEV_URL, null)).getJSONArray("vulnerabilities");
            List<String> ids = new ArrayList<>();
            for (int i = 0; i < list.length(); i++) ids.add(list.getJSONObject(i).getString("cveID"));
            Db.get(app).markExploited(ids);
        } catch (Exception e) {
            Prefs.log(app, "CISA exploited list failed: " + e.getMessage());
        }
    }

    static String status(Context app) {
        try {
            SharedPreferences p = Prefs.get(app);
            if (cachedRevision != revision) { cachedCount = Db.get(app).count(); cachedRevision = revision; }
            boolean complete = p.getBoolean("complete", false);
            int storedTotal = p.getInt("total", 0);
            int storedDone = p.getInt("done", 0);
            int shownTotal = total > 0 ? total : (storedTotal > 0 ? storedTotal : cachedCount);
            int shownDone = done > 0 ? done : (complete ? cachedCount : Math.max(storedDone, cachedCount));
            int pending = Math.max(0, shownTotal - shownDone);
            String shownState = state;
            if (Prefs.paused(app) && !LOCK.isLocked()) shownState = "paused";
            return new JSONObject().put("state", shownState).put("note", note).put("percent", percent)
                    .put("revision", revision).put("complete", complete).put("count", cachedCount)
                    .put("total", shownTotal).put("done", shownDone).put("pending", pending)
                    .put("loadedMode", p.getString("loadedMode", "")).put("mode", Prefs.mode(app))
                    .put("last", p.getLong("lastRun", 0)).put("hasKey", Prefs.hasKey(app))
                    .put("paused", Prefs.paused(app)).put("scopeChosen", Prefs.scopeChosen(app))
                    .put("verified", Prefs.verified(app)).toString();
        } catch (Exception e) { return "{}"; }
    }

    /** Makes a tiny authenticated request; only a successful NVD response accepts the key. */
    static String testKey(String key) {
        if (key == null || key.trim().isEmpty()) return "Paste an NVD API key first.";
        try {
            JSONObject response = new JSONObject(Nvd.get(Nvd.ENDPOINT + "?resultsPerPage=1", key.trim()));
            if (!response.has("totalResults") || !response.has("vulnerabilities")) return "Could not validate the NVD response.";
            return "Key accepted. NVD API access is working.";
        } catch (Exception e) {
            String m = String.valueOf(e.getMessage());
            if (m.contains("401") || m.contains("403")) return "Key rejected by NVD (" + m + "). Check the key and try again.";
            return "Could not validate the key: " + m;
        }
    }

    private static long utc(int year, int month) {
        Calendar cal = Calendar.getInstance(TimeZone.getTimeZone("UTC"), Locale.US);
        cal.clear();
        cal.set(Calendar.YEAR, year);
        cal.set(Calendar.MONTH, month);
        cal.set(Calendar.DAY_OF_MONTH, 1);
        return cal.getTimeInMillis();
    }

    private static int yearNow() {
        return Calendar.getInstance(TimeZone.getTimeZone("UTC"), Locale.US).get(Calendar.YEAR);
    }
}
