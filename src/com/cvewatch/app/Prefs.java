package com.cvewatch.app;

import android.content.Context;
import android.content.SharedPreferences;
import org.json.JSONArray;
import org.json.JSONObject;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/** Settings, watchlist, news cache and activity log. One SharedPreferences file. */
final class Prefs {
    private static final int[] INTERVALS = {15, 60, 360, 1440};
    private static final double[] THRESHOLDS = {0, 4.0, 7.0, 9.0};
    /** News refresh choices in minutes. 0 means manual only. */
    private static final int[] NEWS_INTERVALS = {30, 60, 120, 240, 0};
    private static final String[] NEWS_NAMES = {"Every 30 minutes", "Every hour", "Every 2 hours", "Every 4 hours", "Manual only"};
    static final int NEWS_LIMIT_DEFAULT = 150;
    static final int NEWS_LIMIT_MAX = 500;

    private Prefs() {}

    static SharedPreferences get(Context c) {
        return c.getApplicationContext().getSharedPreferences("cfg", Context.MODE_PRIVATE);
    }

    static String apiKey(Context c) { return get(c).getString("apiKey", "").trim(); }
    static boolean hasKey(Context c) { return !apiKey(c).isEmpty(); }
    static boolean verified(Context c) { return get(c).getBoolean("verified", false) && hasKey(c); }
    static void setVerified(Context c, boolean value) { get(c).edit().putBoolean("verified", value).apply(); }
    static long verifiedAt(Context c) { return get(c).getLong("verifiedAt", 0); }

    static int intervalMinutes(Context c) { return INTERVALS[index(c, "interval", 0, INTERVALS.length)]; }
    static double threshold(Context c) { return THRESHOLDS[index(c, "threshold", 2, THRESHOLDS.length)]; }

    /** latest = newest CVEs of each year (default), all = the whole NVD history. */
    static String mode(Context c) {
        String m = get(c).getString("mode", "latest");
        return m == null || m.isEmpty() ? "latest" : m;
    }
    static void setMode(Context c, String mode) { get(c).edit().putString("mode", mode).apply(); }

    static boolean scopeChosen(Context c) { return get(c).getBoolean("scopeChosen", false); }
    static void setScopeChosen(Context c, boolean value) { get(c).edit().putBoolean("scopeChosen", value).apply(); }

    static boolean paused(Context c) { return get(c).getBoolean("paused", false); }
    static void setPaused(Context c, boolean value) { get(c).edit().putBoolean("paused", value).apply(); }

    // ---- news refresh interval -------------------------------------------------

    static int newsIntervalIndex(Context c) { return index(c, "newsInterval", 2, NEWS_INTERVALS.length); }
    static int newsIntervalMinutes(Context c) { return NEWS_INTERVALS[newsIntervalIndex(c)]; }
    static boolean newsAuto(Context c) { return newsIntervalMinutes(c) > 0; }
    static String[] newsIntervalNames() { return NEWS_NAMES.clone(); }
    static String newsIntervalName(Context c) { return NEWS_NAMES[newsIntervalIndex(c)]; }
    static void setNewsInterval(Context c, int index) {
        get(c).edit().putInt("newsInterval", Math.max(0, Math.min(NEWS_NAMES.length - 1, index))).apply();
    }

    static int newsLimit(Context c) {
        return Math.max(1, Math.min(NEWS_LIMIT_MAX, get(c).getInt("newsLimit", NEWS_LIMIT_DEFAULT)));
    }
    static void setNewsLimit(Context c, int limit) {
        get(c).edit().putInt("newsLimit", Math.max(1, Math.min(NEWS_LIMIT_MAX, limit))).apply();
    }

    private static int index(Context c, String key, int fallback, int size) {
        return Math.max(0, Math.min(size - 1, get(c).getInt(key, fallback)));
    }

    // ---- watchlist -------------------------------------------------------------

    static synchronized List<String> watchlist(Context c) {
        List<String> out = new ArrayList<>();
        try {
            JSONArray a = new JSONArray(get(c).getString("watch", "[]"));
            for (int i = 0; i < a.length(); i++) out.add(a.getString(i));
        } catch (Exception ignored) { }
        return out;
    }

    static synchronized void saveWatchlist(Context c, List<String> items) {
        get(c).edit().putString("watch", new JSONArray(items).toString()).apply();
    }

    // Saved CVEs are full records kept in preferences, so a database refresh cannot lose them.
    static synchronized JSONArray savedJson(Context c) {
        JSONArray out = new JSONArray();
        JSONArray raw;
        try { raw = new JSONArray(get(c).getString("savedCves", "[]")); }
        catch (Exception e) { return out; }
        for (int i = 0; i < raw.length(); i++) {
            Object entry = raw.opt(i);
            if (entry instanceof JSONObject) { out.put(entry); continue; }
            if (entry == null) continue;
            try { out.put(new JSONObject().put("id", String.valueOf(entry))); }
            catch (Exception ignored) { }
        }
        return out;
    }

    static synchronized boolean isSaved(Context c, String id) {
        JSONArray a = savedJson(c);
        for (int i = 0; i < a.length(); i++) {
            JSONObject o = a.optJSONObject(i);
            if (o != null && id.equals(o.optString("id"))) return true;
        }
        return false;
    }

    static synchronized void saveCve(Context c, JSONObject cve) {
        String id = cve.optString("id");
        if (id.isEmpty()) return;
        JSONArray old = savedJson(c);
        JSONArray out = new JSONArray();
        try {
            out.put(new JSONObject(cve.toString()));
            for (int i = 0; i < old.length(); i++) {
                JSONObject o = old.optJSONObject(i);
                if (o != null && !id.equals(o.optString("id"))) out.put(o);
            }
            get(c).edit().putString("savedCves", out.toString()).apply();
        } catch (Exception ignored) { }
    }

    static synchronized void removeSavedCve(Context c, String id) {
        JSONArray old = savedJson(c);
        JSONArray out = new JSONArray();
        try {
            for (int i = 0; i < old.length(); i++) {
                JSONObject o = old.optJSONObject(i);
                if (o != null && !id.equals(o.optString("id"))) out.put(o);
            }
            get(c).edit().putString("savedCves", out.toString()).apply();
        } catch (Exception ignored) { }
    }

    static synchronized int savedCount(Context c) { return savedJson(c).length(); }

    static synchronized void clearSavedCves(Context c) { get(c).edit().putString("savedCves", "[]").apply(); }

    // ---- activity log ----------------------------------------------------------

    static synchronized JSONArray logs(Context c) {
        try { return new JSONArray(get(c).getString("logs", "[]")); }
        catch (Exception e) { return new JSONArray(); }
    }

    static synchronized void log(Context c, String message) {
        try {
            JSONArray old = logs(c);
            JSONArray out = new JSONArray();
            String time = new SimpleDateFormat("dd/MM HH:mm", Locale.US).format(new Date());
            out.put(new JSONArray().put(time).put(message));
            for (int i = 0; i < old.length() && i < 199; i++) out.put(old.get(i));
            get(c).edit().putString("logs", out.toString()).apply();
        } catch (Exception ignored) { }
    }

    static synchronized void clearLogs(Context c) { get(c).edit().putString("logs", "[]").apply(); }

    // ---- news cache ------------------------------------------------------------

    static String newsCache(Context c) { return get(c).getString("newsCache", "[]"); }
    static void saveNewsCache(Context c, String json) { get(c).edit().putString("newsCache", json).apply(); }
    static long newsLoadedAt(Context c) { return get(c).getLong("newsLoadedAt", 0); }
    static void saveNewsLoadedAt(Context c, long time) { get(c).edit().putLong("newsLoadedAt", time).apply(); }

    /** Called by the system_server scanner after every cycle. */
    static void saveBeat(Context c, long time, int found, String error) {
        get(c).edit().putLong("beat", time).putInt("beatFound", found).putString("beatError", error == null ? "" : error).apply();
    }

    static boolean systemScannerAlive(Context c) {
        long beat = get(c).getLong("beat", 0);
        long window = Math.max(2L * intervalMinutes(c), 30L) * 60_000L;
        return beat > 0 && System.currentTimeMillis() - beat < window;
    }

    static long beat(Context c) { return get(c).getLong("beat", 0); }
}
