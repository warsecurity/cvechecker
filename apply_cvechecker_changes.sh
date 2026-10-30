#!/usr/bin/env bash
# Apply the CVE Checker changes from the project root.
set -euo pipefail
if [ ! -f AndroidManifest.xml ] || [ ! -d src/com/cvewatch/app ]; then
  echo "Run this from ~/Videos/cvechecker" >&2
  exit 1
fi

cat > 'src/com/cvewatch/app/Prefs.java' <<'CVE_FILE_Prefs_java'
package com.cvewatch.app;

import android.content.Context;
import android.content.SharedPreferences;
import org.json.JSONArray;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/** Settings, watchlist, news cache and activity log. One SharedPreferences file. */
final class Prefs {
    private static final int[] INTERVALS = {15, 60, 360, 1440};
    private static final double[] THRESHOLDS = {0, 4.0, 7.0, 9.0};

    private Prefs() {}

    static SharedPreferences get(Context c) {
        return c.getApplicationContext().getSharedPreferences("cfg", Context.MODE_PRIVATE);
    }

    static String apiKey(Context c) { return get(c).getString("apiKey", "").trim(); }
    static boolean hasKey(Context c) { return !apiKey(c).isEmpty(); }
    static int intervalMinutes(Context c) { return INTERVALS[index(c, "interval", 1, INTERVALS.length)]; }
    static double threshold(Context c) { return THRESHOLDS[index(c, "threshold", 2, THRESHOLDS.length)]; }

    private static int index(Context c, String key, int fallback, int size) {
        return Math.max(0, Math.min(size - 1, get(c).getInt(key, fallback)));
    }

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
}
CVE_FILE_Prefs_java

cat > 'src/com/cvewatch/app/Db.java' <<'CVE_FILE_Db_java'
package com.cvewatch.app;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;
import android.database.sqlite.SQLiteStatement;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/** Local CVE database. */
final class Db extends SQLiteOpenHelper {
    private static Db instance;

    static synchronized Db get(Context c) {
        if (instance == null) instance = new Db(c.getApplicationContext());
        return instance;
    }

    private Db(Context c) { super(c, "cve.db", null, 1); }

    @Override public void onCreate(SQLiteDatabase db) {
        db.execSQL("CREATE TABLE cve(id TEXT PRIMARY KEY, pub TEXT, score REAL, sev TEXT, vendor TEXT, descr TEXT, kev INTEGER DEFAULT 0, seen INTEGER DEFAULT 1)");
        db.execSQL("CREATE INDEX cve_pub ON cve(pub DESC)");
    }

    @Override public void onUpgrade(SQLiteDatabase db, int from, int to) { }

    int count() {
        try (Cursor c = getReadableDatabase().rawQuery("SELECT COUNT(*) FROM cve", null)) {
            c.moveToFirst();
            return c.getInt(0);
        }
    }

    void markSeen() { getWritableDatabase().execSQL("UPDATE cve SET seen=1 WHERE seen=0"); }

    /** Clears all locally cached CVEs before a verified full database refresh. */
    void clear() { getWritableDatabase().delete("cve", null, null); }

    /** Inserts CVEs. With replace=false, rows that did not exist yet are added to fresh and flagged unseen. */
    void save(List<Nvd.Cve> list, boolean replace, List<Nvd.Cve> fresh) {
        SQLiteDatabase db = getWritableDatabase();
        db.beginTransaction();
        try {
            for (Nvd.Cve c : list) {
                ContentValues v = new ContentValues();
                v.put("id", c.id);
                v.put("pub", c.published);
                v.put("score", c.score);
                v.put("sev", c.severity());
                v.put("vendor", c.vendor);
                v.put("descr", c.description);
                if (replace) {
                    v.put("seen", 1);
                    db.insertWithOnConflict("cve", null, v, SQLiteDatabase.CONFLICT_REPLACE);
                    continue;
                }
                v.put("seen", 0);
                if (db.insertWithOnConflict("cve", null, v, SQLiteDatabase.CONFLICT_IGNORE) != -1) {
                    if (fresh != null) fresh.add(c);
                } else {
                    v.remove("seen");
                    db.update("cve", v, "id=?", new String[]{c.id});
                }
            }
            db.setTransactionSuccessful();
        } finally {
            db.endTransaction();
        }
    }

    void markExploited(List<String> ids) {
        SQLiteDatabase db = getWritableDatabase();
        db.beginTransaction();
        try {
            SQLiteStatement s = db.compileStatement("UPDATE cve SET kev=1 WHERE id=?");
            for (String id : ids) { s.bindString(1, id); s.executeUpdateDelete(); }
            db.setTransactionSuccessful();
        } finally {
            db.endTransaction();
        }
    }

    /** Newest CVEs for the home feed. An empty query is the normal case: nothing to type, the list is always current. */
    String search(String query, String severity) {
        StringBuilder where = new StringBuilder("1=1");
        List<String> args = new ArrayList<>();
        if (severity != null && !severity.equals("All")) { where.append(" AND sev=?"); args.add(severity); }
        String q = query == null ? "" : query.trim().toLowerCase(Locale.US);
        if (q.startsWith("cve")) {
            where.append(" AND id LIKE ?");
            args.add("CVE-" + q.substring(3).replaceAll("^[-\\s]+", "").toUpperCase(Locale.US) + "%");
        } else if (q.matches("\\d{4}(-\\d*)?")) {
            where.append(" AND id LIKE ?");
            args.add("CVE-" + q + "%");
        } else if (!q.isEmpty()) {
            where.append(" AND (id LIKE ? OR vendor LIKE ? OR descr LIKE ?)");
            for (int i = 0; i < 3; i++) args.add("%" + q + "%");
        }
        JSONArray out = new JSONArray();
        String sql = "SELECT id,pub,score,sev,vendor,descr,kev,seen FROM cve WHERE " + where + " ORDER BY pub DESC LIMIT 120";
        try (Cursor c = getReadableDatabase().rawQuery(sql, args.toArray(new String[0]))) {
            while (c.moveToNext()) {
                String vendor = c.getString(4);
                if (vendor == null || vendor.isEmpty()) vendor = c.getDouble(2) < 0 ? "Awaiting NVD analysis" : "";
                out.put(new JSONObject().put("id", c.getString(0)).put("pub", c.getString(1)).put("score", c.getDouble(2))
                        .put("sev", c.getString(3)).put("vendor", vendor).put("desc", c.getString(5))
                        .put("kev", c.getInt(6) == 1).put("isNew", c.getInt(7) == 0));
            }
        } catch (Exception ignored) { }
        return out.toString();
    }
}
CVE_FILE_Db_java

cat > 'src/com/cvewatch/app/Nvd.java' <<'CVE_FILE_Nvd_java'
package com.cvewatch.app;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.TimeZone;

/** NVD API client and parser. Pure Java: it also runs inside system_server. */
final class Nvd {
    static final String ENDPOINT = "https://services.nvd.nist.gov/rest/json/cves/2.0";
    static volatile int pageSize = 2000;

    private Nvd() {}

    static final class Cve {
        String id = "", published = "", vendor = "", description = "";
        double score = -1;

        String severity() {
            if (score >= 9) return "Critical";
            if (score >= 7) return "High";
            if (score >= 4) return "Medium";
            return score > 0 ? "Low" : "Unrated";
        }
    }

    static String get(String url, String apiKey) throws IOException {
        HttpURLConnection http = (HttpURLConnection) new URL(url).openConnection();
        try {
            http.setConnectTimeout(20_000);
            http.setReadTimeout(120_000);
            http.setRequestProperty("User-Agent", "CVEChecker/0.3");
            if (apiKey != null && !apiKey.isEmpty()) http.setRequestProperty("apiKey", apiKey);
            int code = http.getResponseCode();
            if (code != 200) throw new IOException("HTTP " + code);
            StringBuilder sb = new StringBuilder();
            try (BufferedReader in = new BufferedReader(new InputStreamReader(http.getInputStream(), "UTF-8"), 65536)) {
                char[] buf = new char[65536];
                int n;
                while ((n = in.read(buf)) != -1) sb.append(buf, 0, n);
            }
            return sb.toString();
        } finally {
            http.disconnect();
        }
    }

    /** One page of results with retries. Halves the page size if memory runs out. */
    static JSONObject page(String params, int start, String apiKey) throws Exception {
        Exception last = null;
        for (int attempt = 1; attempt <= 5; attempt++) {
            try {
                String query = (params.isEmpty() ? "" : params + "&") + "resultsPerPage=" + pageSize + "&startIndex=" + start;
                return new JSONObject(get(ENDPOINT + "?" + query, apiKey));
            } catch (OutOfMemoryError e) {
                pageSize = Math.max(250, pageSize / 2);
                last = new Exception("out of memory, page size reduced to " + pageSize);
            } catch (Exception e) {
                last = e;
            }
            Thread.sleep(8000L * attempt);
        }
        throw last;
    }

    /** NVD allows 5 requests per 30 s without a key and 50 with one. A key is mandatory in this build. */
    static long pause(String apiKey) { return apiKey == null || apiKey.isEmpty() ? 6500 : 700; }

    static String stamp(long millis) {
        SimpleDateFormat f = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US);
        f.setTimeZone(TimeZone.getTimeZone("UTC"));
        return f.format(new Date(millis)) + "%2B00:00";
    }

    static List<Cve> parseAll(JSONArray items) throws JSONException {
        List<Cve> out = new ArrayList<>(items.length());
        for (int i = 0; i < items.length(); i++) out.add(parse(items.getJSONObject(i)));
        return out;
    }

    static Cve parse(JSONObject item) throws JSONException {
        JSONObject c = item.getJSONObject("cve");
        Cve cve = new Cve();
        cve.id = c.getString("id");
        cve.published = c.optString("published");
        cve.description = english(c.optJSONArray("descriptions"));
        cve.score = baseScore(c.optJSONObject("metrics"));
        cve.vendor = vendor(c.optJSONArray("configurations"));
        return cve;
    }

    private static String english(JSONArray list) {
        if (list == null) return "";
        for (int i = 0; i < list.length(); i++) {
            JSONObject d = list.optJSONObject(i);
            if (d != null && "en".equals(d.optString("lang"))) return d.optString("value");
        }
        return "";
    }

    private static double baseScore(JSONObject metrics) {
        if (metrics == null) return -1;
        for (String version : new String[]{"cvssMetricV40", "cvssMetricV31", "cvssMetricV30", "cvssMetricV2"}) {
            JSONArray list = metrics.optJSONArray(version);
            if (list == null || list.length() == 0) continue;
            JSONObject data = list.optJSONObject(0).optJSONObject("cvssData");
            if (data != null) return data.optDouble("baseScore", -1);
        }
        return -1;
    }

    /** First "vendor product" pair found in the CPE configuration, or empty. */
    private static String vendor(JSONArray configurations) {
        if (configurations == null) return "";
        for (int i = 0; i < configurations.length(); i++) {
            JSONArray nodes = configurations.optJSONObject(i).optJSONArray("nodes");
            if (nodes == null) continue;
            for (int j = 0; j < nodes.length(); j++) {
                JSONArray matches = nodes.optJSONObject(j).optJSONArray("cpeMatch");
                if (matches == null || matches.length() == 0) continue;
                String[] part = matches.optJSONObject(0).optString("criteria").split(":");
                if (part.length > 4) return part[3] + " " + part[4];
            }
        }
        return "";
    }

    /** Returns the watchlist entry that matches this CVE, or null. Unscored CVEs always pass the threshold. */
    static String match(Cve cve, List<String> watchlist, double threshold) {
        if (cve.score >= 0 && cve.score < threshold) return null;
        String text = (cve.id + " " + cve.vendor + " " + cve.description).toLowerCase(Locale.US);
        for (String w : watchlist) if (text.contains(w.toLowerCase(Locale.US))) return w;
        return null;
    }
}
CVE_FILE_Nvd_java

cat > 'src/com/cvewatch/app/News.java' <<'CVE_FILE_News_java'
package com.cvewatch.app;

import android.content.Context;
import android.content.res.AssetManager;
import android.util.Xml;
import org.json.JSONArray;
import org.json.JSONObject;
import org.xmlpull.v1.XmlPullParser;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TimeZone;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorCompletionService;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

/**
 * Aggregates every feed listed in assets/feeds.txt. Feeds are fetched in parallel and the merged list is
 * published after every batch, so the News tab fills up in seconds instead of waiting for the last feed.
 * The merged list is cached in SharedPreferences, which is why the tab opens instantly on the next launch.
 */
final class News {
    static final int MAX_ITEMS = 400;
    private static final int THREADS = 16;

    /** filter=1 feeds are general tech outlets: keep only headlines that mention security. */
    private static final String[] KEYWORDS = {
            "cve", "vulnerab", "exploit", "malware", "ransom", "breach", "hack", "attacker", "phishing",
            "zero-day", "0day", "patch", "security", "cyber", "data leak", "stolen", "spyware", "trojan",
            "botnet", "backdoor", "privilege", "rootkit", "ddos", "fraud", "scam", "compromis", "flutter",
            "hijack", "leak", "bug bounty", "sanction", "threat", "worm", "keylogger", "cryptolocker"
    };

    private static volatile boolean busy;
    private static volatile int fetched;
    private static volatile int total;
    private static volatile long loadedAt;

    private News() {}

    static final class Item {
        String cat = "n", source = "", title = "", link = "";
        long time;
    }

    // ---- public API used by Bridge -----------------------------------------------------------

    static String json(Context c) {
        autoRefresh(c);
        return Prefs.newsCache(c);
    }

    static String meta(Context c) {
        try {
            JSONArray a = new JSONArray(Prefs.newsCache(c));
            return new JSONObject().put("count", a.length()).put("at", Prefs.newsLoadedAt(c))
                    .put("busy", busy).put("done", fetched).put("total", total).toString();
        } catch (Exception e) {
            return "{\"count\":0,\"at\":0,\"busy\":false,\"done\":0,\"total\":0}";
        }
    }

    /** Called by the refresh button and by autoRefresh(). Returns immediately. */
    static void refresh(Context c) {
        if (busy) return;
        busy = true;
        fetched = 0;
        final Context app = c.getApplicationContext();
        new Thread(() -> {
            try { run(app); } catch (Throwable t) { Prefs.log(app, "News refresh failed: " + t.getMessage()); }
            busy = false;
        }, "cve-news").start();
    }

    /** Realtime behaviour: the list is refreshed in the background whenever it is older than 3 minutes. */
    private static void autoRefresh(Context c) {
        long age = System.currentTimeMillis() - Prefs.newsLoadedAt(c);
        if (!busy && age > 180_000L) refresh(c);
    }

    // ---- fetching ---------------------------------------------------------------------------

    private static void run(Context app) throws Exception {
        List<String[]> feeds = feeds(app);
        total = feeds.size();
        loadedAt = System.currentTimeMillis();

        Map<String, Item> merged = loadCache(app);
        int before = merged.size();

        ExecutorService pool = Executors.newFixedThreadPool(THREADS);
        ExecutorCompletionService<List<Item>> done = new ExecutorCompletionService<>(pool);
        for (final String[] feed : feeds) {
            done.submit(new Callable<List<Item>>() {
                @Override public List<Item> call() {
                    List<Item> out = new ArrayList<>();
                    try { read(feed[0], feed[1], feed[2], "1".equals(feed[3]), out); } catch (Throwable ignored) { }
                    return out;
                }
            });
        }
        int batches = 0;
        for (int i = 0; i < feeds.size(); i++) {
            List<Item> part;
            try {
                Future<List<Item>> f = done.take();
                part = f.get();
            } catch (Throwable t) {
                part = Collections.emptyList();
            }
            fetched++;
            int added = merge(merged, part);
            if (added > 0 || ++batches % 40 == 0) publish(app, merged);
        }
        pool.shutdown();
        try { pool.awaitTermination(5, TimeUnit.SECONDS); } catch (InterruptedException ignored) { }
        publish(app, merged);
        Prefs.log(app, "News refreshed: " + fetched + "/" + total + " feeds, " + merged.size() + " headlines");
        if (merged.size() > before) Prefs.saveNewsLoadedAt(app, System.currentTimeMillis());
    }

    private static int merge(Map<String, Item> merged, List<Item> part) {
        int added = 0;
        for (Item n : part) {
            if (n.link.isEmpty() || n.title.isEmpty()) continue;
            Item old = merged.get(n.link);
            if (old == null) {
                merged.put(n.link, n);
                added++;
            } else if (old.time == 0 && n.time > 0) {
                old.time = n.time;
            }
        }
        return added;
    }

    private static void publish(Context app, Map<String, Item> merged) {
        List<Item> all = new ArrayList<>(merged.values());
        Collections.sort(all, (a, b) -> Long.compare(b.time, a.time));
        JSONArray out = new JSONArray();
        try {
            for (int i = 0; i < all.size() && i < MAX_ITEMS; i++) {
                Item n = all.get(i);
                out.put(new JSONArray().put(n.source).put(n.title).put(n.time).put(n.link).put(n.cat));
            }
        } catch (Exception ignored) { }
        Prefs.saveNewsCache(app, out.toString());
        Prefs.saveNewsLoadedAt(app, System.currentTimeMillis());
    }

    private static Map<String, Item> loadCache(Context app) {
        Map<String, Item> merged = new LinkedHashMap<>();
        try {
            JSONArray a = new JSONArray(Prefs.newsCache(app));
            for (int i = 0; i < a.length(); i++) {
                JSONArray r = a.getJSONArray(i);
                Item n = new Item();
                n.source = r.optString(0);
                n.title = r.optString(1);
                n.time = r.optLong(2);
                n.link = r.optString(3);
                n.cat = r.optString(4, "n");
                if (!n.link.isEmpty()) merged.put(n.link, n);
            }
        } catch (Exception ignored) { }
        return merged;
    }

    /** cat|name|url|filter */
    private static List<String[]> feeds(Context app) {
        List<String[]> out = new ArrayList<>();
        AssetManager assets = app.getAssets();
        try (BufferedReader in = new BufferedReader(new InputStreamReader(assets.open("feeds.txt"), "UTF-8"))) {
            String line;
            while ((line = in.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                String[] p = line.split("\\|");
                if (p.length < 3) continue;
                out.add(new String[]{p[0], p[1], p[2], p.length > 3 ? p[3] : "0"});
            }
        } catch (Exception e) {
            Prefs.log(app, "Feed list unreadable: " + e.getMessage());
        }
        return out;
    }

    // ---- one feed: RSS 2.0 or Atom ----------------------------------------------------------

    private static void read(String cat, String name, String url, boolean filter, List<Item> out) throws Exception {
        HttpURLConnection http = (HttpURLConnection) new URL(url).openConnection();
        try {
            http.setConnectTimeout(6_000);
            http.setReadTimeout(9_000);
            http.setInstanceFollowRedirects(true);
            http.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14) CVEChecker/0.3");
            http.setRequestProperty("Accept", "application/rss+xml, application/atom+xml, application/xml, text/xml, */*");
            if (http.getResponseCode() != 200) return;

            XmlPullParser xml = Xml.newPullParser();
            xml.setInput(http.getInputStream(), null);

            StringBuilder title = new StringBuilder(), link = new StringBuilder(),
                    date = new StringBuilder(), body = new StringBuilder();
            String tag = null, href = null;
            boolean inItem = false;

            for (int e = xml.getEventType(); e != XmlPullParser.END_DOCUMENT; e = xml.next()) {
                if (e == XmlPullParser.START_TAG) {
                    tag = xml.getName();
                    if (tag.equals("item") || tag.equals("entry")) {
                        inItem = true;
                        title.setLength(0); link.setLength(0); date.setLength(0); body.setLength(0);
                    } else if (inItem && tag.equals("link")) {
                        href = xml.getAttributeValue(null, "href");
                        String rel = xml.getAttributeValue(null, "rel");
                        if (href != null && (rel == null || rel.equals("alternate")) && link.length() == 0) link.append(href);
                    } else if (inItem && tag.equals("guid") && link.length() == 0) {
                        href = xml.getAttributeValue(null, "isPermaLink");
                    }
                } else if ((e == XmlPullParser.TEXT || e == XmlPullParser.CDSECT) && inItem && tag != null) {
                    String t = xml.getText();
                    if (tag.equals("title")) title.append(t);
                    else if (tag.equals("link")) link.append(t);
                    else if (tag.equals("pubDate") || tag.equals("published") || tag.equals("updated") || tag.equals("date")) date.append(t);
                    else if (tag.equals("description") || tag.equals("summary") || tag.equals("content")) body.append(t);
                } else if (e == XmlPullParser.END_TAG) {
                    if (inItem && (xml.getName().equals("item") || xml.getName().equals("entry"))) {
                        inItem = false;
                        Item n = new Item();
                        n.cat = cat;
                        n.source = name;
                        n.title = clean(title.toString());
                        n.link = link.toString().trim();
                        n.time = parseDate(date.toString().trim());
                        if (n.link.startsWith("http") && !n.title.isEmpty()) {
                            if (!filter || relevant(n.title + " " + clean(body.toString()))) out.add(n);
                        }
                        if (out.size() >= 60) return;
                    }
                    tag = null;
                }
            }
        } finally {
            http.disconnect();
        }
    }

    private static boolean relevant(String text) {
        String t = text.toLowerCase(Locale.US);
        for (String k : KEYWORDS) if (t.contains(k)) return true;
        return false;
    }

    private static String clean(String s) {
        String t = s.replaceAll("<[^>]*>", " ").replace("&amp;", "&").replace("&quot;", "\"")
                .replace("&#8217;", "'").replace("&#039;", "'").replace("&apos;", "'")
                .replace("&lt;", "<").replace("&gt;", ">").replace("&nbsp;", " ")
                .replaceAll("\\s+", " ").trim();
        return t.length() > 220 ? t.substring(0, 217) + "..." : t;
    }

    private static final String[] DATE_PATTERNS = {
            "EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm Z", "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXX", "yyyy-MM-dd'T'HH:mm:ssXXX", "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", "yyyy-MM-dd HH:mm:ss", "dd MMM yyyy HH:mm:ss Z"
    };

    private static long parseDate(String raw) {
        if (raw.isEmpty()) return 0;
        String s = raw.trim();
        for (String pattern : DATE_PATTERNS) {
            try {
                SimpleDateFormat f = new SimpleDateFormat(pattern, Locale.US);
                if (pattern.endsWith("'Z'")) f.setTimeZone(TimeZone.getTimeZone("UTC"));
                f.setLenient(true);
                return f.parse(s).getTime();
            } catch (Exception ignored) { }
        }
        return 0;
    }
}
CVE_FILE_News_java

cat > 'src/com/cvewatch/app/Sync.java' <<'CVE_FILE_Sync_java'
package com.cvewatch.app;

import android.content.Context;
import android.content.SharedPreferences;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.locks.ReentrantLock;

/** Downloads and maintains the local NVD CVE database. A verified NVD key is required for every request. */
final class Sync {
    static final ReentrantLock LOCK = new ReentrantLock();
    static volatile String state = "idle"; // idle, running, ready, error
    static volatile String note = "";
    static volatile int percent;
    static volatile int revision;
    static volatile int done;
    static volatile int total;

    private static final String KEV_URL = "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json";
    private static final long DAY = 86_400_000L;
    private static int cachedCount;
    private static int cachedRevision = -1;

    private Sync() {}

    static boolean running() { return LOCK.isLocked(); }

    static boolean due(Context c) {
        SharedPreferences p = Prefs.get(c);
        long wait = Prefs.intervalMinutes(c) * 60_000L - 60_000L;
        return Prefs.hasKey(c) && p.getBoolean("complete", false)
                && System.currentTimeMillis() - p.getLong("lastRun", 0) >= wait;
    }

    static void run(Context context) { run(context, false); }

    /** forceFull means refresh the entire local CVE database, but only after the supplied key is verified. */
    static void run(Context context, boolean forceFull) {
        if (!LOCK.tryLock()) return;
        Context app = context.getApplicationContext();
        SharedPreferences prefs = Prefs.get(app);
        try {
            state = "running"; note = "Validating NVD API key"; percent = 0;
            done = 0; total = 0;
            String key = Prefs.apiKey(app);
            String validation = testKey(key);
            if (!validation.startsWith("Key accepted")) throw new Exception(validation);

            if (forceFull) {
                note = "Resetting local database for full refresh";
                Db.get(app).clear();
                prefs.edit().putBoolean("complete", false).putInt("offset", 0).putInt("total", 0)
                        .putLong("lastChange", 0).putLong("lastRun", 0).apply();
            }
            if (prefs.getBoolean("complete", false)) loadChanges(app);
            else loadAll(app);
            markExploited(app);
            prefs.edit().putLong("lastRun", System.currentTimeMillis()).apply();
            percent = 100; state = "ready"; note = "Database up to date";
        } catch (Throwable e) {
            state = "error"; note = String.valueOf(e.getMessage());
            Prefs.log(app, "Sync stopped: " + note);
        } finally {
            revision++;
            LOCK.unlock();
        }
    }

    /** The newest 120 days are loaded first; the full NVD history then resumes by saved offset. */
    private static void loadAll(Context app) throws Exception {
        SharedPreferences prefs = Prefs.get(app);
        String key = Prefs.apiKey(app);
        Db db = Db.get(app);
        if (db.count() == 0 && prefs.getInt("offset", 0) == 0) {
            note = "Loading recent CVEs first";
            long now = System.currentTimeMillis();
            pull(app, "pubStartDate=" + Nvd.stamp(now - 119 * DAY) + "&pubEndDate=" + Nvd.stamp(now), true, null);
            Thread.sleep(Nvd.pause(key));
        }
        note = "Downloading all NVD CVEs";
        int start = prefs.getInt("offset", 0);
        int count = prefs.getInt("total", 0);
        do {
            JSONObject page = Nvd.page("", start, key);
            count = page.getInt("totalResults");
            JSONArray items = page.getJSONArray("vulnerabilities");
            if (items.length() == 0) break;
            db.save(Nvd.parseAll(items), true, null);
            start += items.length();
            prefs.edit().putInt("offset", start).putInt("total", count).apply();
            done = start; total = count;
            percent = Math.max(1, Math.min(99, count == 0 ? 99 : (int) (100L * start / count)));
            revision++;
            if (start < count) Thread.sleep(Nvd.pause(key));
        } while (start < count);
        prefs.edit().putBoolean("complete", true).putLong("lastChange", System.currentTimeMillis()).apply();
        Prefs.log(app, "Database loaded: " + count + " CVEs");
    }

    /** Fetch CVEs published or modified since the previous successful run. */
    private static void loadChanges(Context app) throws Exception {
        SharedPreferences prefs = Prefs.get(app);
        long end = System.currentTimeMillis();
        long since = Math.max(prefs.getLong("lastChange", end), end - 119 * DAY);
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
            JSONObject page = Nvd.page(params, start, key);
            count = page.getInt("totalResults");
            JSONArray items = page.getJSONArray("vulnerabilities");
            if (items.length() == 0) break;
            Db.get(app).save(Nvd.parseAll(items), replace, fresh);
            start += items.length();
            done = start; total = count;
            revision++;
            if (start < count) Thread.sleep(Nvd.pause(key));
        } while (start < count);
    }

    private static void alertFor(Context app, List<Nvd.Cve> fresh) {
        if (Prefs.systemScannerAlive(app)) {
            Prefs.log(app, "Sync finished: " + fresh.size() + " new CVEs (alerts handled by system scanner)");
            return;
        }
        List<String> watch = Prefs.watchlist(app);
        double threshold = Prefs.threshold(app);
        int sent = 0;
        for (Nvd.Cve c : fresh) {
            String hit = Nvd.match(c, watch, threshold);
            if (hit == null || sent >= 8) continue;
            Notify.alert(app, c.id, c.id + " (" + c.severity() + ")", "Matches \u201c" + hit + "\u201d: " + c.description);
            sent++;
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
            return new JSONObject().put("state", state).put("note", note).put("percent", percent).put("revision", revision)
                    .put("complete", complete).put("total", total > 0 ? total : (complete || storedTotal == 0 ? cachedCount : storedTotal))
                    .put("done", done > 0 ? done : (complete ? cachedCount : Math.max(cachedCount, p.getInt("offset", 0))))
                    .put("last", p.getLong("lastRun", 0)).put("hasKey", Prefs.hasKey(app)).toString();
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
}
CVE_FILE_Sync_java

cat > 'src/com/cvewatch/app/SyncService.java' <<'CVE_FILE_SyncService_java'
package com.cvewatch.app;

import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import android.os.PowerManager;

/** Foreground service keeps a full CVE database download running while the screen is off. */
public class SyncService extends Service {
    @Override public IBinder onBind(Intent intent) { return null; }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        startForeground(7, Notify.progress(this, 0, "Starting"));
        if (!Prefs.hasKey(this)) {
            Sync.state = "error"; Sync.note = "An NVD API key is required before syncing."; Sync.revision++;
            stopForeground(true);
            stopSelf(startId);
            return START_NOT_STICKY;
        }
        boolean forceFull = intent != null && intent.getBooleanExtra("forceFull", false);
        new Thread(() -> work(forceFull), "cve-sync-service").start();
        return START_NOT_STICKY;
    }

    private void work(boolean forceFull) {
        PowerManager.WakeLock lock = ((PowerManager) getSystemService(POWER_SERVICE)).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "cvechecker:sync");
        lock.acquire(2 * 3600 * 1000L);
        Thread sync = new Thread(() -> Sync.run(this, forceFull), "cve-sync");
        sync.start();
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        try {
            while (sync.isAlive()) {
                nm.notify(7, Notify.progress(this, Sync.percent, Sync.note));
                Thread.sleep(2500);
            }
        } catch (InterruptedException ignored) { Thread.currentThread().interrupt(); }
        finally {
            if (lock.isHeld()) lock.release();
            stopForeground(true);
            stopSelf();
        }
    }
}
CVE_FILE_SyncService_java

cat > 'src/com/cvewatch/app/SyncJob.java' <<'CVE_FILE_SyncJob_java'
package com.cvewatch.app;

import android.app.job.JobInfo;
import android.app.job.JobParameters;
import android.app.job.JobScheduler;
import android.app.job.JobService;
import android.content.ComponentName;
import android.content.Context;

/** Periodic refresh of the local CVE database, kept across reboots. */
public class SyncJob extends JobService {
    static void schedule(Context c) {
        JobScheduler scheduler = (JobScheduler) c.getSystemService(Context.JOB_SCHEDULER_SERVICE);
        if (scheduler == null) return;
        long interval = Math.max(15 * 60_000L, Prefs.intervalMinutes(c) * 60_000L);
        JobInfo existing = scheduler.getPendingJob(1);
        if (existing != null && existing.getIntervalMillis() == interval) return;
        scheduler.schedule(new JobInfo.Builder(1, new ComponentName(c, SyncJob.class))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPeriodic(interval).setPersisted(true).build());
    }

    @Override public boolean onStartJob(JobParameters params) {
        new Thread(() -> {
            if (Sync.due(this) && !Sync.running()) Sync.run(this);
            jobFinished(params, false);
        }, "cve-sync-job").start();
        return true;
    }

    @Override public boolean onStopJob(JobParameters params) { return true; }
}
CVE_FILE_SyncJob_java

cat > 'src/com/cvewatch/app/ConfigProvider.java' <<'CVE_FILE_ConfigProvider_java'
package com.cvewatch.app;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.os.Binder;
import android.os.Bundle;
import android.os.Process;
import org.json.JSONArray;
import org.json.JSONObject;

/** App/system_server handoff for scanner configuration, alerts, and liveness. */
public class ConfigProvider extends ContentProvider {
    @Override public boolean onCreate() { return true; }

    @Override public Bundle call(String method, String arg, Bundle extras) {
        if (Binder.getCallingUid() != Process.SYSTEM_UID) return null;
        Context c = getContext();
        Bundle out = new Bundle();
        try {
            switch (method) {
                case "config":
                    out.putString("json", new JSONObject().put("key", Prefs.apiKey(c))
                            .put("watch", new JSONArray(Prefs.watchlist(c))).put("threshold", Prefs.threshold(c))
                            .put("interval", Prefs.intervalMinutes(c)).toString());
                    break;
                case "alert":
                    Notify.alert(c, arg, extras.getString("title"), extras.getString("text"));
                    break;
                case "beat":
                    Prefs.saveBeat(c, extras.getLong("time"), extras.getInt("found"), extras.getString("error"));
                    break;
                default: return null;
            }
        } catch (Exception e) { return null; }
        return out;
    }

    @Override public Cursor query(Uri u, String[] p, String s, String[] a, String o) { return null; }
    @Override public String getType(Uri u) { return null; }
    @Override public Uri insert(Uri u, ContentValues v) { return null; }
    @Override public int delete(Uri u, String s, String[] a) { return 0; }
    @Override public int update(Uri u, ContentValues v, String s, String[] a) { return 0; }
}
CVE_FILE_ConfigProvider_java

cat > 'src/com/cvewatch/app/MainActivity.java' <<'CVE_FILE_MainActivity_java'
package com.cvewatch.app;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.inputmethod.InputMethodManager;
import android.content.Context;
import android.widget.Button;
import android.widget.EditText;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import org.json.JSONArray;
import org.json.JSONObject;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/** Native UI only: this app intentionally contains no WebView or embedded browser. */
public class MainActivity extends Activity {
    private static final int BG = Color.rgb(15, 18, 27), PANEL = Color.rgb(27, 32, 45), LINE = Color.rgb(48, 55, 72);
    private static final int TEXT = Color.rgb(236, 238, 247), MUTED = Color.rgb(159, 167, 188), ACCENT = Color.rgb(151, 178, 255);
    private static final int GREEN = Color.rgb(134, 210, 159), RED = Color.rgb(255, 142, 139), AMBER = Color.rgb(255, 194, 116);

    static boolean isModuleActive() { return false; } // LSPosed Hook.java replaces this with true.

    private final Handler handler = new Handler(Looper.getMainLooper());
    private LinearLayout root, page, bottom;
    private ScrollView scroller;
    private String tab = "Home";
    private String newsFilter = "All";
    private int severityIndex = 0;
    private static long lastKick;
    private boolean alive;
    private int lastRevision = -1;
    private int lastNewsCount = -1;
    private boolean lastNewsBusy;

    /** Polls cheaply: the home list only rebuilds when the database revision changes. */
    private final Runnable poller = new Runnable() {
        @Override public void run() {
            if (!alive) return;
            if (tab.equals("Home")) {
                JSONObject st = json(Sync.status(MainActivity.this));
                if (st.optInt("revision", 0) != lastRevision) renderHome();
            } else if (tab.equals("News")) {
                News.json(MainActivity.this); // triggers the three-minute background refresh while News is open
                JSONObject meta = json(News.meta(MainActivity.this));
                if (meta.optInt("count", 0) != lastNewsCount || meta.optBoolean("busy") != lastNewsBusy) renderNews();
            }
            handler.postDelayed(this, 3000);
        }
    };

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(PANEL);
        if (Build.VERSION.SDK_INT >= 23) getWindow().getDecorView().setSystemUiVisibility(0);
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission("android.permission.POST_NOTIFICATIONS") != 0)
            requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"}, 1);
        SyncJob.schedule(this);
        buildShell();
        render();
    }

    @Override protected void onStart() {
        super.onStart();
        alive = true;
        handler.removeCallbacks(poller);
        handler.post(poller);
        maybeStartSync();
    }

    @Override protected void onStop() {
        alive = false;
        handler.removeCallbacks(poller);
        new Thread(() -> Db.get(this).markSeen(), "cve-mark-seen").start();
        super.onStop();
    }

    private void buildShell() {
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(BG);
        root.setLayoutParams(new ViewGroup.LayoutParams(-1, -1));
        TextView brand = text("CVE CHECKER", 13, ACCENT, true);
        brand.setLetterSpacing(.12f);
        brand.setPadding(dp(22), dp(18), dp(22), dp(4));
        root.addView(brand);
        scroller = new ScrollView(this);
        scroller.setFillViewport(true);
        scroller.setClipToPadding(false);
        page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(dp(18), dp(10), dp(18), dp(24));
        scroller.addView(page, new ScrollView.LayoutParams(-1, -2));
        root.addView(scroller, new LinearLayout.LayoutParams(-1, 0, 1));
        bottom = new LinearLayout(this);
        bottom.setOrientation(LinearLayout.HORIZONTAL);
        bottom.setGravity(Gravity.CENTER);
        bottom.setBackgroundColor(PANEL);
        bottom.setPadding(dp(6), dp(8), dp(6), dp(10));
        root.addView(bottom, new LinearLayout.LayoutParams(-1, -2));
        setContentView(root);
        drawTabs();
    }

    private void drawTabs() {
        bottom.removeAllViews();
        String[] tabs = {"Home", "Logs", "Settings", "News"};
        for (String name : tabs) {
            TextView b = text(name, 13, tab.equals(name) ? ACCENT : MUTED, tab.equals(name));
            b.setGravity(Gravity.CENTER);
            b.setPadding(dp(7), dp(12), dp(7), dp(12));
            b.setBackground(tab.equals(name) ? round(0x333C63C7, 30) : null);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, -2, 1);
            lp.setMargins(dp(3), 0, dp(3), 0);
            bottom.addView(b, lp);
            b.setOnClickListener(v -> { tab = name; render(); });
        }
    }

    private void render() {
        drawTabs();
        page.removeAllViews();
        scroller.scrollTo(0, 0);
        if (tab.equals("Home")) renderHome();
        else if (tab.equals("News")) renderNews();
        else if (tab.equals("Logs")) renderLogs();
        else renderSettings();
    }

    private void renderHome() {
        page.removeAllViews();
        JSONObject st = json(Sync.status(this));
        lastRevision = st.optInt("revision", 0);
        boolean hasKey = Prefs.hasKey(this);
        addTitle("Latest CVEs");
        TextView status = text(statusLine(st), 13, MUTED, false);
        status.setPadding(0, 0, 0, dp(10));
        page.addView(status);
        if (!hasKey) {
            addCard("NVD API key required", "Set and verify your NVD API key in Settings. The complete CVE database will start downloading automatically after verification.");
            Button settings = button("Open Settings");
            settings.setOnClickListener(v -> { tab = "Settings"; render(); });
            page.addView(settings, fullLp(0, 8));
            return;
        }
        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        Button refresh = button(st.optString("state").equals("running") ? "Updating…" : "Refresh CVE database");
        refresh.setEnabled(!Sync.running());
        refresh.setOnClickListener(v -> confirmFullRefresh());
        actions.addView(refresh, new LinearLayout.LayoutParams(0, -2, 1));
        Button severity = button(severityLabel());
        severity.setOnClickListener(v -> chooseSeverity());
        LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(-2, -2);
        sp.setMargins(dp(8), 0, 0, 0);
        actions.addView(severity, sp);
        page.addView(actions);

        JSONArray rows;
        try { rows = new JSONArray(Db.get(this).search("", severityLabel().equals("All severities") ? "All" : severityLabel())); }
        catch (Exception e) { rows = new JSONArray(); }
        if (rows.length() == 0) {
            String msg = st.optString("state").equals("error") ? "Sync failed: " + st.optString("note")
                    : (st.optBoolean("complete") ? "No CVEs found in the local database." : "The database is loading. Recent CVEs will appear here as they download.");
            addCard("Database status", msg);
            return;
        }
        for (int i = 0; i < rows.length(); i++) {
            JSONObject c = rows.optJSONObject(i);
            if (c != null) addCveRow(c);
        }
    }

    private String statusLine(JSONObject s) {
        if (!Prefs.hasKey(this)) return "NVD API key required";
        String state = s.optString("state", "idle");
        if (state.equals("running")) {
            int percent = s.optInt("percent", 0);
            String p = s.optInt("total", 0) > 0 ? " · " + format(s.optInt("done")) + " / " + format(s.optInt("total")) : "";
            return s.optString("note", "Syncing") + " · " + percent + "%" + p;
        }
        if (state.equals("error")) return "Sync error · " + s.optString("note");
        if (s.optBoolean("complete")) return format(s.optInt("total")) + " CVEs · " + (s.optLong("last") > 0 ? "Updated " + age(s.optLong("last")) : "Ready");
        return "CVE database not downloaded yet";
    }

    private void addCveRow(JSONObject c) {
        LinearLayout box = cardBox();
        TextView id = text(c.optString("id"), 16, TEXT, true);
        box.addView(id);
        String vendor = c.optString("vendor");
        if (!vendor.isEmpty()) box.addView(text(vendor, 13, MUTED, false));
        String d = c.optString("desc");
        if (!d.isEmpty()) {
            TextView desc = text(d, 13, MUTED, false);
            desc.setPadding(0, dp(5), 0, dp(5));
            box.addView(desc);
        }
        String severity = c.optString("sev", "Unrated");
        int color = severity.equals("Critical") ? RED : severity.equals("High") ? AMBER : severity.equals("Medium") ? 0xFFE5CE69 : GREEN;
        String score = c.optDouble("score", -1) >= 0 ? String.format(Locale.US, "%.1f", c.optDouble("score")) + " · " : "";
        String kev = c.optBoolean("kev") ? " · Actively exploited" : "";
        box.addView(text(score + severity + kev + " · Published " + shortDate(c.optString("pub")), 12, color, false));
        box.setOnClickListener(v -> openExternal("https://nvd.nist.gov/vuln/detail/" + c.optString("id")));
        page.addView(box, fullLp(0, 8));
    }

    private void renderNews() {
        page.removeAllViews();
        addTitle("Security & cyber news");
        JSONObject meta = json(News.meta(this));
        lastNewsCount = meta.optInt("count", 0);
        lastNewsBusy = meta.optBoolean("busy");
        String stamp = meta.optLong("at") == 0 ? "Not refreshed yet" : "Updated " + age(meta.optLong("at"));
        page.addView(text(meta.optInt("count") + " headlines · " + stamp + (meta.optBoolean("busy") ? " · Refreshing " + meta.optInt("done") + "/" + meta.optInt("total") : ""), 13, MUTED, false));
        Button refresh = button(meta.optBoolean("busy") ? "Refreshing…" : "Refresh news");
        refresh.setEnabled(!meta.optBoolean("busy"));
        refresh.setOnClickListener(v -> { News.refresh(this); Toast.makeText(this, "Refreshing feeds…", Toast.LENGTH_SHORT).show(); renderNews(); });
        page.addView(refresh, fullLp(0, 10));
        addNewsFilters();
        JSONArray all;
        try { all = new JSONArray(News.json(this)); } catch (Exception e) { all = new JSONArray(); }
        int visible = 0;
        for (int i = 0; i < all.length(); i++) {
            JSONArray row = all.optJSONArray(i);
            if (row == null) continue;
            String source = row.optString(0), title = row.optString(1), url = row.optString(3), cat = row.optString(4, "n");
            if (!matchesNewsFilter(cat)) continue;
            addNewsRow(source, title, row.optLong(2), url, cat);
            visible++;
        }
        if (visible == 0) addCard("Fetching live feeds", "Headlines load from more than 300 public RSS and Atom feeds. Keep this screen open briefly, or tap Refresh news.");
    }

    private void addNewsFilters() {
        HorizontalScrollView hs = new HorizontalScrollView(this);
        hs.setHorizontalScrollBarEnabled(false);
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        for (String filter : new String[]{"All", "Cyber", "CVE & advisories", "Crypto"}) {
            Button b = button(filter);
            b.setTextSize(12);
            b.setTextColor(newsFilter.equals(filter) ? ACCENT : MUTED);
            b.setOnClickListener(v -> { newsFilter = filter; renderNews(); });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
            lp.setMargins(0, 0, dp(7), 0);
            row.addView(b, lp);
        }
        hs.addView(row);
        page.addView(hs, fullLp(0, 8));
    }

    private boolean matchesNewsFilter(String cat) {
        if (newsFilter.equals("All")) return true;
        if (newsFilter.equals("Crypto")) return cat.equals("c");
        if (newsFilter.equals("CVE & advisories")) return cat.equals("v");
        return cat.equals("n") || cat.equals("r");
    }

    private void addNewsRow(String source, String title, long time, String url, String cat) {
        LinearLayout box = cardBox();
        String label = cat.equals("v") ? "CVE / ADVISORY" : cat.equals("c") ? "CRYPTO" : cat.equals("r") ? "RESEARCH" : "CYBER NEWS";
        box.addView(text(label + "  ·  " + source + (time > 0 ? "  ·  " + age(time) : ""), 11, ACCENT, true));
        TextView headline = text(title, 15, TEXT, true);
        headline.setPadding(0, dp(5), 0, 0);
        box.addView(headline);
        box.setOnClickListener(v -> openExternal(url));
        page.addView(box, fullLp(0, 7));
    }

    private void renderLogs() {
        page.removeAllViews();
        addTitle("Activity logs");
        JSONArray logs = Prefs.logs(this);
        if (logs.length() == 0) addCard("No activity yet", "CVE syncs, news refreshes, and scanner events will appear here.");
        for (int i = 0; i < logs.length(); i++) {
            JSONArray row = logs.optJSONArray(i);
            if (row == null) continue;
            LinearLayout box = cardBox();
            box.addView(text(row.optString(0), 12, ACCENT, true));
            box.addView(text(row.optString(1), 14, TEXT, false));
            page.addView(box, fullLp(0, 7));
        }
    }

    private void renderSettings() {
        page.removeAllViews();
        addTitle("Settings");
        String module;
        if (!isModuleActive()) module = "Not active. In LSPosed enable CVE Checker and System Framework, then reboot.";
        else module = "Active. Scanner last reported " + age(Prefs.get(this).getLong("beat", 0)) + ".";
        addSection("LSPosed");
        addCard("System scanner", module);

        addSection("NVD API key");
        String key = Prefs.apiKey(this);
        addCard("Key status", key.isEmpty() ? "A valid NVD API key is required before any CVE database download." : "Verified key saved (ending " + key.substring(Math.max(0, key.length() - 4)) + ").");
        Button edit = button(key.isEmpty() ? "Add and verify API key" : "Replace API key");
        edit.setOnClickListener(v -> showKeyDialog());
        page.addView(edit, fullLp(0, 8));
        TextView getKey = text("Request a free key from the NVD website", 13, ACCENT, false);
        getKey.setPadding(dp(4), dp(10), dp(4), dp(14));
        getKey.setOnClickListener(v -> openExternal("https://nvd.nist.gov/developers/request-an-api-key"));
        page.addView(getKey);

        addSection("Background sync");
        Button full = button("Refresh full CVE database");
        full.setOnClickListener(v -> confirmFullRefresh());
        page.addView(full, fullLp(0, 7));
        Button interval = button("Sync interval · " + intervalName());
        interval.setOnClickListener(v -> chooseInterval());
        page.addView(interval, fullLp(0, 7));
        Button battery = button("Battery optimization settings");
        battery.setOnClickListener(v -> openBatterySettings());
        page.addView(battery, fullLp(0, 7));

        addSection("About");
        addCard("CVE Checker 0.3", "CVE database: NVD. Known exploited vulnerabilities: CISA KEV. News: public RSS and Atom sources, refreshed periodically. All article links open in your external browser.");
    }

    private void showKeyDialog() {
        final EditText input = new EditText(this);
        input.setSingleLine(true);
        input.setText(Prefs.apiKey(this));
        input.setHint("Paste NVD API key");
        input.setInputType(129); // textPassword
        LinearLayout wrap = new LinearLayout(this);
        wrap.setPadding(dp(22), dp(4), dp(22), 0);
        wrap.addView(input, new LinearLayout.LayoutParams(-1, -2));
        AlertDialog dialog = new AlertDialog.Builder(this).setTitle("Verify NVD API key").setMessage("The key is tested with NVD before it is stored. A successful check starts the complete CVE database download automatically.")
                .setView(wrap).setNegativeButton("Cancel", null).setPositiveButton("Verify and save", null).create();
        dialog.setOnShowListener(d -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            String candidate = input.getText().toString().trim();
            if (candidate.isEmpty()) { input.setError("An API key is required"); return; }
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(false);
            dialog.setTitle("Checking key with NVD…");
            new Thread(() -> {
                String result = Sync.testKey(candidate);
                runOnUiThread(() -> {
                    if (result.startsWith("Key accepted")) {
                        Prefs.get(this).edit().putString("apiKey", candidate).putBoolean("complete", false)
                                .putInt("offset", 0).putInt("total", 0).apply();
                        dialog.dismiss();
                        Toast.makeText(this, "API key verified. Starting full CVE download.", Toast.LENGTH_LONG).show();
                        startSync(false);
                        render();
                    } else {
                        dialog.setTitle("API key not accepted");
                        dialog.setMessage(result);
                        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(true);
                        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setText("Try again");
                    }
                });
            }, "nvd-key-check").start();
        }));
        dialog.show();
    }

    private void confirmFullRefresh() {
        if (!Prefs.hasKey(this)) {
            new AlertDialog.Builder(this).setTitle("API key required").setMessage("Add and verify an NVD API key in Settings before refreshing the CVE database.")
                    .setPositiveButton("Open Settings", (d, w) -> { tab = "Settings"; render(); }).setNegativeButton("Cancel", null).show();
            return;
        }
        new AlertDialog.Builder(this).setTitle("Refresh entire CVE database?")
                .setMessage("This clears the local CVE cache, verifies the saved API key, and downloads the full NVD database again. The download may take several minutes.")
                .setNegativeButton("Cancel", null).setPositiveButton("Refresh database", (d, w) -> startSync(true)).show();
    }

    private void startSync(boolean forceFull) {
        if (!Prefs.hasKey(this)) { Toast.makeText(this, "A verified NVD API key is required.", Toast.LENGTH_LONG).show(); return; }
        lastKick = System.currentTimeMillis();
        Intent i = new Intent(this, SyncService.class).putExtra("forceFull", forceFull);
        try {
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(i); else startService(i);
        } catch (Exception e) {
            Toast.makeText(this, "Could not start CVE sync: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void maybeStartSync() {
        if (!Prefs.hasKey(this) || Sync.running()) return;
        if (System.currentTimeMillis() - lastKick < 120_000L) return;
        SharedPreferences p = Prefs.get(this);
        if (!p.getBoolean("complete", false) || Sync.due(this)) { lastKick = System.currentTimeMillis(); startSync(false); }
    }

    private void chooseSeverity() {
        String[] choices = {"All severities", "Critical", "High", "Medium", "Low"};
        new AlertDialog.Builder(this).setTitle("Filter CVEs").setSingleChoiceItems(choices, severityIndex, (d, which) -> {
            severityIndex = which; d.dismiss(); renderHome();
        }).setNegativeButton("Cancel", null).show();
    }

    private String severityLabel() {
        return new String[]{"All severities", "Critical", "High", "Medium", "Low"}[Math.max(0, Math.min(4, severityIndex))];
    }

    private void chooseInterval() {
        String[] names = {"Every 15 minutes", "Every hour", "Every 6 hours", "Every 24 hours"};
        int current = Prefs.get(this).getInt("interval", 1);
        new AlertDialog.Builder(this).setTitle("Background sync interval").setSingleChoiceItems(names, current, (d, which) -> {
            Prefs.get(this).edit().putInt("interval", which).apply();
            SyncJob.schedule(this); d.dismiss(); renderSettings();
        }).setNegativeButton("Cancel", null).show();
    }

    private String intervalName() {
        String[] a = {"15 minutes", "1 hour", "6 hours", "24 hours"};
        int i = Math.max(0, Math.min(a.length - 1, Prefs.get(this).getInt("interval", 1)));
        return a[i];
    }

    private void openBatterySettings() {
        String pkg = getPackageName();
        new Thread(() -> {
            try { Runtime.getRuntime().exec(new String[]{"su", "-c", "dumpsys deviceidle whitelist +" + pkg}).waitFor(); }
            catch (Exception ignored) { }
        }, "battery-whitelist").start();
        try { startActivity(new Intent("android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS", Uri.parse("package:" + pkg))); }
        catch (Exception e) {
            try { startActivity(new Intent("android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS")); } catch (Exception ignored) { }
        }
    }

    private void openExternal(String url) {
        if (url == null || !(url.startsWith("https://") || url.startsWith("http://"))) return;
        try { startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url))); }
        catch (ActivityNotFoundException e) { Toast.makeText(this, "No browser is available to open this link.", Toast.LENGTH_LONG).show(); }
    }

    private void addTitle(String title) {
        TextView t = text(title, 27, TEXT, false);
        t.setPadding(0, dp(5), 0, dp(10));
        page.addView(t);
    }
    private void addSection(String title) {
        TextView t = text(title.toUpperCase(Locale.US), 12, ACCENT, true);
        t.setLetterSpacing(.08f);
        t.setPadding(0, dp(15), 0, dp(7));
        page.addView(t);
    }
    private void addCard(String title, String body) {
        LinearLayout box = cardBox();
        box.addView(text(title, 16, TEXT, true));
        TextView b = text(body, 13, MUTED, false);
        b.setPadding(0, dp(5), 0, 0);
        box.addView(b);
        page.addView(box, fullLp(0, 7));
    }
    private LinearLayout cardBox() {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(14), dp(13), dp(14), dp(13));
        box.setBackground(round(PANEL, 16));
        return box;
    }
    private TextView text(String s, int sp, int color, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s); t.setTextSize(sp); t.setTextColor(color);
        if (bold) t.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        t.setIncludeFontPadding(true);
        return t;
    }
    private Button button(String label) {
        Button b = new Button(this);
        b.setText(label); b.setAllCaps(false); b.setTextSize(13); b.setTextColor(TEXT);
        b.setPadding(dp(9), dp(2), dp(9), dp(2));
        b.setBackground(round(0xFF303A50, 12));
        return b;
    }
    private GradientDrawable round(int color, int radius) {
        GradientDrawable d = new GradientDrawable(); d.setColor(color); d.setCornerRadius(dp(radius)); return d;
    }
    private LinearLayout.LayoutParams fullLp(int top, int bottom) {
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
        p.setMargins(0, dp(top), 0, dp(bottom)); return p;
    }
    private int dp(float v) { return (int) (v * getResources().getDisplayMetrics().density + .5f); }
    private String format(int n) { return String.format(Locale.US, "%,d", n); }
    private JSONObject json(String s) { try { return new JSONObject(s); } catch (Exception e) { return new JSONObject(); } }
    private String age(long ms) {
        if (ms <= 0) return "not yet";
        long m = Math.max(0, (System.currentTimeMillis() - ms) / 60_000L);
        if (m < 1) return "just now";
        if (m < 60) return m + " min ago";
        if (m < 1440) return (m / 60) + " h ago";
        return (m / 1440) + " d ago";
    }
    private String shortDate(String value) {
        if (value == null || value.length() < 10) return "unknown";
        return value.substring(0, 10);
    }
}
CVE_FILE_MainActivity_java

cat > 'assets/feeds.txt' <<'CVE_FEEDS_EOF'
# cat|name|url|filter    cat: n=news c=crypto v=vulns/advisories r=research    filter=1 keeps only security-related headlines
n|BleepingComputer|https://www.bleepingcomputer.com/feed/|0
n|The Hacker News|https://feeds.feedburner.com/TheHackersNews|0
n|Krebs on Security|https://krebsonsecurity.com/feed/|0
n|SecurityWeek|https://feeds.feedburner.com/securityweek|0
n|Dark Reading|https://www.darkreading.com/rss.xml|0
n|Ars Technica Security|https://arstechnica.com/security/feed/|0
n|Wired Security|https://www.wired.com/feed/category/security/latest/rss|0
n|The Register Security|https://www.theregister.com/security/headlines.atom|0
n|Schneier on Security|https://www.schneier.com/feed/atom/|0
n|Graham Cluley|https://grahamcluley.com/feed/|0
n|Infosecurity Magazine|https://www.infosecurity-magazine.com/rss/news/|0
n|Infosecurity Vulnerabilities|https://www.infosecurity-magazine.com/rss/vulnerabilities/|0
n|SC Media|https://www.scmagazine.com/feed|0
n|SC Media UK|https://www.scmagazineuk.com/rss.xml|0
n|CSO Online|https://www.csoonline.com/feed|0
n|HackRead|https://www.hackread.com/feed/|0
n|Security Affairs|https://securityaffairs.com/feed|0
n|Help Net Security|https://www.helpnetsecurity.com/feed/|0
n|CyberScoop|https://cyberscoop.com/feed/|0
n|The Record|https://therecord.media/feed|0
n|Recorded Future News|https://therecord.media/feed|0
n|TechCrunch Security|https://techcrunch.com/category/security/feed/|0
n|DataBreaches.net|https://databreaches.net/feed/|0
n|Security Boulevard|https://securityboulevard.com/feed/|0
n|GBHackers|https://gbhackers.com/feed/|0
n|Cyber Security News|https://cybersecuritynews.com/feed/|0
n|Latest Hacking News|https://latesthackingnews.com/feed/|0
n|Cyber Defense Magazine|https://www.cyberdefensemagazine.com/feed/|0
n|Heimdal Security|https://heimdalsecurity.com/blog/feed/|0
n|The Cyber Express|https://thecyberexpress.com/feed/|0
n|SecurityOnline|https://securityonline.info/feed/|0
n|Cybersecurity Insiders|https://www.cybersecurity-insiders.com/feed/|0
n|Cybersecurity Dive|https://www.cybersecuritydive.com/feeds/news/|0
n|Industrial Cyber|https://industrialcyber.co/feed/|0
n|HIPAA Journal|https://www.hipaajournal.com/feed/|0
n|Risky Business News|https://risky.biz/feeds/risky-business-news/|0
n|404 Media|https://www.404media.co/rss/|1
n|Hackaday|https://hackaday.com/blog/feed/|1
n|Darknet Diaries|https://feeds.megaphone.fm/darknetdiaries|0
n|Heise Security|https://www.heise.de/security/feed.xml|0
n|Security.nl|https://www.security.nl/rss/headlines.xml|0
n|ComputerWeekly Security|https://www.computerweekly.com/rss/IT-security.xml|0
n|ZDNet Security|https://www.zdnet.com/topic/security/rss.xml|0
n|ITPro Security|https://www.itpro.com/feeds/tag/security|0
n|TechRadar|https://www.techradar.com/feeds/articletype/news|1
n|Ars Technica|https://feeds.arstechnica.com/arstechnica/index|1
n|The Verge|https://www.theverge.com/rss/index.xml|1
n|TechCrunch|https://techcrunch.com/feed/|1
n|Engadget|https://www.engadget.com/rss.xml|1
n|Wired|https://www.wired.com/feed/rss|1
n|MIT Technology Review|https://www.technologyreview.com/feed/|1
n|Techmeme|https://www.techmeme.com/feed.xml|1
n|BBC Technology|https://feeds.bbci.co.uk/news/technology/rss.xml|1
n|The Guardian Cybersecurity|https://www.theguardian.com/technology/data-computer-security/rss|0
n|NYT Technology|https://rss.nytimes.com/services/xml/rss/nyt/Technology.xml|1
n|Slashdot|https://rss.slashdot.org/Slashdot/slashdotMain|1
n|Lobsters Security|https://lobste.rs/t/security.rss|0
n|Hacker News security|https://hnrss.org/newest?q=vulnerability+OR+exploit+OR+breach+OR+hacked+OR+CVE&points=30|0
n|Reddit r/netsec|https://www.reddit.com/r/netsec/.rss|0
n|Reddit r/cybersecurity|https://www.reddit.com/r/cybersecurity/.rss|0
n|Reddit r/blueteamsec|https://www.reddit.com/r/blueteamsec/.rss|0
n|Reddit r/ReverseEngineering|https://www.reddit.com/r/ReverseEngineering/.rss|0
n|Reddit r/Malware|https://www.reddit.com/r/Malware/.rss|0
n|Reddit r/AskNetsec|https://www.reddit.com/r/AskNetsec/.rss|0
n|Reddit r/hacking|https://www.reddit.com/r/hacking/.rss|0
n|Reddit r/androidsecurity|https://www.reddit.com/r/androidsecurity/.rss|0
n|Reddit r/ExploitDev|https://www.reddit.com/r/ExploitDev/.rss|0
n|Reddit r/privacy|https://www.reddit.com/r/privacy/.rss|1
n|Reddit r/technology|https://www.reddit.com/r/technology/.rss|1
n|Techweez Kenya|https://techweez.com/feed/|1
n|TechCabal|https://techcabal.com/feed/|1
n|Disrupt Africa|https://disrupt-africa.com/feed/|1
n|IT News Africa|https://www.itnewsafrica.com/feed/|1
n|MyBroadband Security|https://mybroadband.co.za/news/security/feed|0
n|Hackers Online Club|https://www.hackersonlineclub.com/feed/|0
n|PCMag Security|https://www.pcmag.com/feeds/rss/security|0
n|Tom's Hardware|https://www.tomshardware.com/feeds/all|1
n|Android Authority|https://www.androidauthority.com/feed/|1
n|9to5Google|https://9to5google.com/feed/|1
n|XDA Developers|https://www.xda-developers.com/feed/|1
n|Android Police|https://www.androidpolice.com/feed/|1
n|9to5Mac|https://9to5mac.com/feed/|1
n|MacRumors|https://feeds.macrumors.com/MacRumors-All|1
n|Phoronix|https://www.phoronix.com/rss.php|1
n|LWN.net|https://lwn.net/headlines/rss|1
n|Cyble Blog|https://cyble.com/feed/|0
n|Flashpoint|https://flashpoint.io/feed/|0
n|Cybercrime Magazine|https://cybersecurityventures.com/feed/|0
n|Dark Reading Threat Intel|https://www.darkreading.com/rss/threat-intelligence.xml|0
n|SecurityWeek Malware|https://www.securityweek.com/category/malware-cyber-threats/feed/|0
n|CyberSecurity Hub|https://www.cshub.com/rss/articles|0
n|Techopedia Security|https://www.techopedia.com/feed|1
n|IT Security Guru|https://www.itsecurityguru.org/feed/|0
n|Information Security Buzz|https://informationsecuritybuzz.com/feed/|0
n|Cybernews|https://cybernews.com/feed/|0
n|Cybernews Security|https://cybernews.com/security/feed/|0
n|TechTarget SearchSecurity|https://www.techtarget.com/searchsecurity/rss/Security-Wire.xml|0
n|Dark Web Informer|https://darkwebinformer.com/rss/|0
n|The Cybersecurity Times|https://thecybersecuritytimes.com/feed/|0
n|Cyber Magazine|https://cybermagazine.com/rss|0
n|Silicon UK Security|https://www.silicon.co.uk/security/feed|0
n|SiliconANGLE Security|https://siliconangle.com/category/security/feed/|0
n|VentureBeat Security|https://venturebeat.com/category/security/feed/|0
n|Tech Monitor|https://techmonitor.ai/feed|1
n|Digital Trends|https://www.digitaltrends.com/feed/|1
n|Gizmodo|https://gizmodo.com/rss|1
n|Lifehacker|https://lifehacker.com/feed/rss|1
n|CNET|https://www.cnet.com/rss/news/|1
n|PCWorld|https://www.pcworld.com/feed|1
n|ExtremeTech|https://www.extremetech.com/feed|1
n|Neowin|https://www.neowin.net/news/rss/|1
n|BetaNews|https://betanews.com/feed/|1
n|BGR|https://bgr.com/feed/|1
n|The Next Web|https://thenextweb.com/feed|1
n|Mashable|https://mashable.com/feeds/rss/all|1
n|Fast Company Tech|https://www.fastcompany.com/technology/rss|1
n|Washington Post Tech|https://feeds.washingtonpost.com/rss/business/technology|1
n|Al Jazeera|https://www.aljazeera.com/xml/rss/all.xml|1
n|Sky News Tech|https://feeds.skynews.com/feeds/rss/technology.xml|1
n|NPR Technology|https://feeds.npr.org/1019/rss.xml|1
n|CBS News Tech|https://www.cbsnews.com/latest/rss/technology|1
n|Independent Tech|https://www.independent.co.uk/tech/rss|1
n|Telegraph Tech|https://www.telegraph.co.uk/technology/rss.xml|1
n|The Hindu Tech|https://www.thehindu.com/sci-tech/technology/feeder/default.rss|1
n|Times of India Tech|https://timesofindia.indiatimes.com/rssfeeds/66949542.cms|1
n|ABC News Tech|https://abcnews.go.com/abcnews/technologyheadlines|1
n|InfoWorld Security|https://www.infoworld.com/category/security/index.rss|0
n|Computerworld Security|https://www.computerworld.com/category/security/feed/|0
n|Network World Security|https://www.networkworld.com/category/security/feed/|0
n|The Stack|https://www.thestack.technology/rss/|1
n|ISACA Now|https://www.isaca.org/rss/news|0
n|Dark Reading Vulnerabilities|https://www.darkreading.com/rss/vulnerabilities-threats.xml|0
n|CSO Online Threats|https://www.csoonline.com/category/cyber-attacks-extortion/feed/|0
n|BankInfoSecurity|https://www.bankinfosecurity.com/rss|0
n|GovInfoSecurity|https://www.govinfosecurity.com/rss|0
n|Digital Health Security|https://www.healthcareinfosecurity.com/rss|0
n|Schneier Essays|https://www.schneier.com/blog/atom.xml|0
n|Troy Hunt|https://www.troyhunt.com/rss/|0
n|Malware Unicorn|https://malwareunicorn.org/feed.xml|0
n|SANS Blog|https://www.sans.org/blog/feed|0
n|DevSecOps Now|https://devsecopsnow.io/feed/|1
n|The New Stack Security|https://thenewstack.io/category/security/feed/|0
n|Register Cybersecurity|https://www.theregister.com/security/rss|0
n|Heise IT News|https://www.heise.de/rss/heise-atom.xml|1
n|Golem Security|https://www.golem.de/specials/security/rss.xml|0
n|Bitport|https://bitport.hu/rss/hirek|1
n|Security Magazine|https://www.securitymagazine.com/rss/topic/2237-cyber-security|0
n|CyberRisk Alliance|https://www.cyberscoop.com/feed/|0
n|Threatpost|https://threatpost.com/feed/|0
n|CSO Australia|https://www.cso.com.au/rss/|0
n|ITNews Australia Security|https://www.itnews.com.au/RSS/rss.ashx|0
n|The Register APAC|https://www.theregister.com/apac/headlines.atom|1
n|Tech in Asia|https://www.techinasia.com/feed|1
n|Inc42 Security|https://inc42.com/feed/|1
n|The Daily Swig|https://portswigger.net/daily-swig/rss|0
n|BleepingComputer Podcasts|https://www.bleepingcomputer.com/feed/|0
c|Rekt News|https://rekt.news/rss.xml|0
c|The Block|https://www.theblock.co/rss.xml|1
c|CoinDesk|https://www.coindesk.com/arc/outboundfeeds/rss/|1
c|Cointelegraph|https://cointelegraph.com/rss|1
c|Decrypt|https://decrypt.co/feed|1
c|Bitcoin Magazine|https://bitcoinmagazine.com/feed|1
c|CryptoSlate|https://cryptoslate.com/feed/|1
c|The Defiant|https://thedefiant.io/feed|1
c|BeInCrypto|https://beincrypto.com/feed/|1
c|CryptoPotato|https://cryptopotato.com/feed/|1
c|NewsBTC|https://www.newsbtc.com/feed/|1
c|U.Today|https://u.today/rss|1
c|Crypto Briefing|https://cryptobriefing.com/feed/|1
c|Bitcoinist|https://bitcoinist.com/feed/|1
c|AMBCrypto|https://ambcrypto.com/feed/|1
c|CryptoNews|https://cryptonews.com/news/feed/|1
c|Blockworks|https://blockworks.co/feed|1
c|DL News|https://www.dlnews.com/arc/outboundfeeds/rss/|1
c|CoinGape|https://coingape.com/feed/|1
c|Coinpedia|https://coinpedia.org/feed/|1
c|The Crypto Basic|https://thecryptobasic.com/feed/|1
c|CCN|https://www.ccn.com/feed/|1
c|Bitcoin.com News|https://news.bitcoin.com/feed/|1
c|CoinJournal|https://coinjournal.net/feed/|1
c|Crypto Daily|https://cryptodaily.io/feed|1
c|ZyCrypto|https://zycrypto.com/feed/|1
c|Protos|https://protos.com/feed/|1
c|Unchained Crypto|https://unchainedcrypto.com/feed/|1
c|Chainalysis Blog|https://www.chainalysis.com/blog/feed/|0
c|Elliptic Blog|https://www.elliptic.co/blog/rss.xml|0
c|SlowMist|https://slowmist.medium.com/feed|0
c|CertiK|https://medium.com/feed/certik|0
c|PeckShield|https://peckshield.medium.com/feed|0
c|Immunefi|https://medium.com/feed/immunefi|0
c|Hacken|https://medium.com/feed/hackenio|0
c|OpenZeppelin|https://blog.openzeppelin.com/rss/|0
c|Trail of Bits|https://blog.trailofbits.com/feed/|0
c|Ethereum Foundation|https://blog.ethereum.org/feed.xml|1
c|Binance Blog|https://www.binance.com/en/blog/rss|1
c|Coinbase Blog|https://www.coinbase.com/blog/rss.xml|1
c|Kraken Blog|https://blog.kraken.com/feed|1
c|MetaMask Blog|https://metamask.io/news/rss.xml|1
c|Ledger Blog|https://www.ledger.com/blog/feed|1
c|Cyvers|https://medium.com/feed/@cyversalerts|0
c|ScamSniffer|https://scamsniffer.medium.com/feed|0
c|Web3 is Going Great|https://web3isgoinggreat.com/feed|0
c|CoinTelegraph Altcoin|https://cointelegraph.com/rss/tag/altcoin|1
c|The Defiant DeFi|https://thedefiant.io/api/feed|1
c|Bitcoin Optech|https://bitcoinops.org/feed.xml|0
v|CISA Advisories|https://www.cisa.gov/cybersecurity-advisories/all.xml|0
v|CISA ICS Advisories|https://www.cisa.gov/cybersecurity-advisories/ics-advisories.xml|0
v|NVD Recent CVEs|https://nvd.nist.gov/feeds/xml/cve/misc/nvd-rss.xml|0
v|Exploit-DB|https://www.exploit-db.com/rss.xml|0
v|Packet Storm Files|https://rss.packetstormsecurity.com/files/|0
v|Packet Storm News|https://rss.packetstormsecurity.com/news/|0
v|Zero Day Initiative Published|https://www.zerodayinitiative.com/rss/published/|0
v|Zero Day Initiative Upcoming|https://www.zerodayinitiative.com/rss/upcoming/|0
v|CERT/CC Vulnerability Notes|https://www.kb.cert.org/vuls/atomfeed/|0
v|SANS Internet Storm Center|https://isc.sans.edu/rssfeed_full.xml|0
v|NCSC UK|https://www.ncsc.gov.uk/api/1/services/v1/all-rss-feed.xml|0
v|CERT-EU Advisories|https://cert.europa.eu/publications/security-advisories-rss|0
v|CERT-FR|https://www.cert.ssi.gouv.fr/feed/|0
v|JPCERT/CC|https://www.jpcert.or.jp/rss/jpcert-en.rdf|0
v|Canadian Centre for Cyber Security|https://www.cyber.gc.ca/api/cccs/rss/v1/get?feed=alerts_advisories&lang=en|0
v|Australian Cyber Security Centre|https://www.cyber.gov.au/rss/news|0
v|Cisco Security Advisories|https://sec.cloudapps.cisco.com/security/center/psirtrss20/CiscoSecurityAdvisory.xml|0
v|FortiGuard PSIRT|https://www.fortiguard.com/rss/ir.xml|0
v|Microsoft MSRC|https://msrc.microsoft.com/blog/feed|0
v|Apple Security Updates|https://support.apple.com/en-us/rss/securityupdates.rss|0
v|Chrome Releases|https://chromereleases.googleblog.com/feeds/posts/default|0
v|Mozilla Security Blog|https://blog.mozilla.org/security/feed/|0
v|Ubuntu Security Notices|https://ubuntu.com/security/notices/rss.xml|0
v|Red Hat Security Blog|https://access.redhat.com/blogs/766093/feed|0
v|VMware Security|https://blogs.vmware.com/security/feed|0
v|AWS Security Bulletins|https://aws.amazon.com/security/security-bulletins/feed/|0
v|AWS Security Blog|https://aws.amazon.com/blogs/security/feed/|0
v|Kubernetes CVE Feed|https://kubernetes.io/docs/reference/issues-security/official-cve-feed/index.xml|0
v|Node.js Vulnerabilities|https://nodejs.org/en/feed/vulnerability.xml|0
v|Drupal Security Advisories|https://www.drupal.org/security/rss.xml|0
v|Ruby Security Announcements|https://www.ruby-lang.org/en/feeds/security-announcements.rss|0
v|Vulners|https://vulners.com/rss.xml|0
v|CVE Feed|https://cvefeed.io/rssfeed/latest.xml|0
v|CVE Details Critical|https://www.cvedetails.com/vulnerability-feed.php?vendor_id=0&product_id=0&version_id=0&orderby=3&cvssscoremin=7|0
v|oss-security|https://seclists.org/rss/oss-sec.rss|0
v|Full Disclosure|https://seclists.org/rss/fulldisclosure.rss|0
v|Bugtraq|https://seclists.org/rss/bugtraq.rss|0
v|WPScan Vulnerabilities|https://wpscan.com/blog/feed/|0
v|Wordfence Vulnerabilities|https://www.wordfence.com/blog/feed/|0
v|Patchstack|https://patchstack.com/feed/|0
v|Android Developers Blog|https://android-developers.googleblog.com/feeds/posts/default|0
v|Google Online Security Blog|https://security.googleblog.com/feeds/posts/default|0
v|Google Cloud Threat Intelligence|https://cloud.google.com/blog/topics/threat-intelligence/rss/|0
v|Qualys Threat Research|https://blog.qualys.com/feed|0
v|Tenable Blog|https://www.tenable.com/blog/feed|0
v|Rapid7 Blog|https://blog.rapid7.com/rss/|0
v|GrapheneOS Releases|https://grapheneos.org/releases.atom|0
v|LineageOS Blog|https://lineageos.org/blog/index.xml|0
v|Mozilla Security Advisories|https://www.mozilla.org/security/advisories/rss|0
v|PHP Security|https://www.php.net/feed.atom|1
v|Django Security|https://www.djangoproject.com/rss/weblog/|1
v|Spring Security|https://spring.io/security.atom|0
v|Apache Security|https://www.apache.org/security/rss.xml|0
v|Jenkins Security|https://www.jenkins.io/security/advisories/rss.xml|0
v|GitLab Security Releases|https://about.gitlab.com/atom.xml|1
v|Splunk Security Advisories|https://advisory.splunk.com/rss|0
v|Ivanti Security|https://www.ivanti.com/blog/rss.xml|0
v|Palo Alto Security Advisories|https://security.paloaltonetworks.com/rss.xml|0
v|SonicWall PSIRT|https://psirt.global.sonicwall.com/rss|0
v|Juniper SIRT|https://kb.juniper.net/InfoCenter/index?page=rss&channel=SECURITY_ADVISORIES|0
v|Adobe Security Bulletins|https://helpx.adobe.com/security/feed.rss|0
v|Oracle Critical Patch Updates|https://www.oracle.com/ocom/groups/public/documents/webcontent/security-alerts-rss.xml|0
v|SAP Security Notes|https://www.sap.com/feed/security.xml|0
v|ZDI Advisories|https://www.zerodayinitiative.com/rss/advisories/|0
v|Snyk Vuln DB|https://snyk.io/blog/feed/|0
v|GitHub Advisory DB|https://github.com/advisories.atom|0
v|osv.dev|https://osv.dev/feed.xml|0
r|Google Project Zero|https://googleprojectzero.blogspot.com/feeds/posts/default|0
r|Google TAG|https://blog.google/threat-analysis-group/rss/|0
r|Microsoft Security Blog|https://www.microsoft.com/en-us/security/blog/feed/|0
r|Mandiant|https://www.mandiant.com/resources/blog/rss.xml|0
r|CrowdStrike|https://www.crowdstrike.com/blog/feed/|0
r|SentinelOne Labs|https://www.sentinelone.com/blog/feed/|0
r|Proofpoint Threat Insight|https://www.proofpoint.com/us/rss.xml|0
r|Fortinet Threat Research|https://feeds.fortinet.com/fortinet/blog/threat-research|0
r|Check Point Research|https://research.checkpoint.com/feed/|0
r|Palo Alto Unit 42|https://unit42.paloaltonetworks.com/feed/|0
r|Cisco Talos|https://blog.talosintelligence.com/rss/|0
r|Securelist Kaspersky|https://securelist.com/feed/|0
r|ESET WeLiveSecurity|https://www.welivesecurity.com/en/rss/feed/|0
r|Trend Micro Research|https://feeds.feedburner.com/TrendMicroResearch|0
r|Malwarebytes Labs|https://www.malwarebytes.com/blog/feed/index.xml|0
r|Bitdefender Labs|https://www.bitdefender.com/blog/api/rss/labs/|0
r|Avast Decoded|https://decoded.avast.io/feed/|0
r|McAfee Labs|https://www.mcafee.com/blogs/feed/|0
r|Trellix|https://www.trellix.com/blogs/feed/|0
r|Zscaler ThreatLabz|https://www.zscaler.com/blogs/feeds/security-research|0
r|Netskope|https://www.netskope.com/feed|0
r|CyberArk Threat Research|https://www.cyberark.com/resources/threat-research-blog/feed|0
r|Varonis|https://www.varonis.com/blog/rss.xml|0
r|Imperva|https://www.imperva.com/blog/feed/|0
r|Cloudflare Security|https://blog.cloudflare.com/tag/security/rss/|0
r|Radware|https://www.radware.com/blog/feed/|0
r|Sucuri|https://blog.sucuri.net/feed|0
r|Snyk Blog|https://snyk.io/blog/feed/|0
r|GitHub Security Blog|https://github.blog/security/feed/|0
r|JFrog Security Research|https://jfrog.com/blog/feed/|0
r|Checkmarx|https://checkmarx.com/feed/|0
r|Sonatype|https://www.sonatype.com/blog/rss.xml|0
r|Socket|https://socket.dev/api/blog/feed.atom|0
r|ReversingLabs|https://www.reversinglabs.com/blog/rss.xml|0
r|Mend|https://www.mend.io/feed/|0
r|Aqua Security|https://blog.aquasec.com/rss.xml|0
r|Wiz|https://www.wiz.io/feed/rss.xml|0
r|Orca Security|https://orca.security/resources/blog/feed/|0
r|Sysdig|https://sysdig.com/blog/feed/|0
r|Red Canary|https://redcanary.com/blog/feed/|0
r|Huntress|https://www.huntress.com/blog/rss.xml|0
r|Elastic Security Labs|https://www.elastic.co/security-labs/rss/feed.xml|0
r|Volexity|https://www.volexity.com/blog/feed/|0
r|Group-IB|https://www.group-ib.com/blog/feed/|0
r|Intezer|https://intezer.com/blog/feed/|0
r|Cybereason|https://www.cybereason.com/blog/rss.xml|0
r|Recorded Future Research|https://www.recordedfuture.com/feed|0
r|ThreatFabric|https://www.threatfabric.com/blogs/rss.xml|0
r|Any.Run|https://any.run/cybersecurity-blog/feed/|0
r|VirusTotal Blog|https://blog.virustotal.com/feeds/posts/default|0
r|abuse.ch|https://abuse.ch/blog/index.xml|0
r|Malware Traffic Analysis|https://www.malware-traffic-analysis.net/blog-entries.rss|0
r|Dragos|https://www.dragos.com/blog/feed/|0
r|Claroty Team82|https://claroty.com/blog/feed|0
r|Forescout|https://www.forescout.com/blog/feed/|0
r|NowSecure|https://www.nowsecure.com/blog/feed/|0
r|Zimperium|https://www.zimperium.com/blog/feed/|0
r|Lookout|https://www.lookout.com/blog/feed|0
r|Quarkslab|https://blog.quarkslab.com/feeds/all.atom.xml|0
r|Objective-See|https://objective-see.org/rss.xml|0
r|Jamf Threat Labs|https://www.jamf.com/blog/rss/|0
r|PortSwigger Research|https://portswigger.net/research/rss|0
r|HackerOne|https://www.hackerone.com/blog.rss|0
r|Bugcrowd|https://www.bugcrowd.com/blog/feed/|0
r|Intigriti|https://blog.intigriti.com/feed/|0
r|Pentest Partners|https://www.pentestpartners.com/security-blog/feed/|0
r|Black Hills InfoSec|https://www.blackhillsinfosec.com/feed/|0
r|TrustedSec|https://trustedsec.com/feed|0
r|SpecterOps|https://posts.specterops.io/feed|0
r|Outflank|https://outflank.nl/blog/feed/|0
r|OffSec|https://www.offsec.com/feed/|0
r|Kali Linux|https://www.kali.org/rss.xml|0
r|OWASP|https://owasp.org/feed.xml|0
r|ZAP|https://www.zaproxy.org/feed.xml|0
r|Hexacorn|https://www.hexacorn.com/blog/feed/|0
r|GitHub Security Lab|https://github.blog/tag/github-security-lab/feed/|0
r|Acronis Threat Research|https://www.acronis.com/en-us/blog/rss/|0
r|Cloud Security Alliance|https://cloudsecurityalliance.org/blog/feed/|0
r|Sophos X-Ops|https://news.sophos.com/en-us/category/threat-research/feed/|0
r|Symantec Threat Intelligence|https://symantec-enterprise-blogs.security.com/blogs/threat-intelligence/feed|0
r|Positive Technologies|https://global.ptsecurity.com/analytics/rss|0
r|Okta Security|https://sec.okta.com/feed|0
r|Akamai Security Research|https://www.akamai.com/blog/security-research/rss|0
r|Veracode|https://www.veracode.com/blog/feed|0
r|F5 Labs|https://www.f5.com/labs/rss.xml|0
r|Arctic Wolf|https://arcticwolf.com/resources/blog/feed/|0
r|Sekoia|https://blog.sekoia.io/feed/|0
r|Securonix|https://www.securonix.com/blog/feed/|0
r|Sophos News|https://news.sophos.com/en-us/feed/|0
r|Kaspersky Blog|https://www.kaspersky.com/blog/feed/|0
r|Avira Blog|https://www.avira.com/en/blog/feed|0
r|G Data Security|https://www.gdatasoftware.com/blog/rss|0
CVE_FEEDS_EOF

# 1) The system_server scanner must also refuse to run without a key.
if [ -f src/com/cvewatch/app/SysScanner.java ]; then
  sed -i 's/cfg\.optString("key");/cfg.optString("key").trim();/' src/com/cvewatch/app/SysScanner.java
  sed -i 's/^\( *\)if (watch\.isEmpty()) { remember(now); return 0; }/\1if (key.isEmpty()) { remember(now); return 0; }\n\1if (watch.isEmpty()) { remember(now); return 0; }/' src/com/cvewatch/app/SysScanner.java
  if grep -q 'key.isEmpty()' src/com/cvewatch/app/SysScanner.java; then
    echo "SysScanner: API-key gate added."
  else
    echo "WARN: SysScanner pattern not found; add the key.isEmpty() guard by hand." >&2
  fi
fi

# 2) No WebView anywhere: drop the old activity from the manifest, delete the WebView sources.
sed -i '/android:name="\.WebActivity"/d' AndroidManifest.xml
rm -f src/com/cvewatch/app/Bridge.java src/com/cvewatch/app/WebActivity.java assets/index.html

# 3) Confirm the feed catalog landed.
echo "feeds.txt: $(grep -vc '^#' assets/feeds.txt) sources."
echo "Sources updated. Export JDK 17 and build-tools in this shell, then run ./build.sh"
