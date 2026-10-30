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
    private static final int THREADS = 16;

    /** filter=1 feeds are general tech outlets: keep only headlines that mention security. */
    private static final String[] KEYWORDS = {
            "cve", "vulnerab", "exploit", "malware", "ransom", "breach", "hack", "attacker", "phishing",
            "zero-day", "0day", "patch", "security", "cyber", "data leak", "stolen", "spyware", "trojan",
            "botnet", "backdoor", "privilege", "rootkit", "ddos", "fraud", "scam", "compromis", "flutter",
            "hijack", "leak", "bug bounty", "sanction", "threat", "worm", "keylogger", "cryptolocker"
    };

    private static volatile boolean busy;
    private static volatile boolean again;
    private static volatile int runId;
    private static volatile int fetched;
    private static volatile int total;

    private News() {}

    static final class Item {
        String cat = "n", source = "", title = "", link = "";
        long time;
    }

    // ---- public API used by Bridge -----------------------------------------------------------

    static String json(Context c) {
        trimToLimit(c);
        autoRefresh(c);
        return Prefs.newsCache(c);
    }

    static String meta(Context c) {
        trimToLimit(c);
        autoRefresh(c);
        try {
            JSONArray a = new JSONArray(Prefs.newsCache(c));
            return new JSONObject().put("count", a.length()).put("at", Prefs.newsLoadedAt(c))
                    .put("busy", busy).put("done", fetched).put("total", total).toString();
        } catch (Exception e) {
            return "{\"count\":0,\"at\":0,\"busy\":false,\"done\":0,\"total\":0}";
        }
    }

    static void refresh(Context c) {
        if (busy) { again = true; return; }
        busy = true;
        again = false;
        fetched = 0;
        final Context app = c.getApplicationContext();
        final int id = ++runId;
        new Thread(() -> {
            try { run(app, id); } catch (Throwable t) { Prefs.log(app, "News refresh failed: " + t.getMessage()); }
            busy = false;
            if (again) { again = false; refresh(app); }
        }, "cve-news").start();
    }

    static boolean active() { return busy || again; }

    static void clear(Context c) {
        runId++;
        Prefs.saveNewsCache(c, "[]");
        Prefs.saveNewsLoadedAt(c, 0);
        if (busy) again = true; else refresh(c);
    }

    static void trimToLimit(Context c) {
        try {
            JSONArray a = new JSONArray(Prefs.newsCache(c));
            int limit = Prefs.newsLimit(c);
            if (a.length() <= limit) return;
            JSONArray out = new JSONArray();
            for (int i = 0; i < limit; i++) out.put(a.get(i));
            Prefs.saveNewsCache(c, out.toString());
        } catch (Exception ignored) { }
    }

    private static void autoRefresh(Context c) {
        int minutes = Prefs.newsIntervalMinutes(c);
        if (minutes <= 0) return;
        long age = System.currentTimeMillis() - Prefs.newsLoadedAt(c);
        if (!busy && age >= minutes * 60_000L) refresh(c);
    }

    // ---- fetching ---------------------------------------------------------------------------

    private static void run(Context app, int id) throws Exception {
        List<String[]> feeds = feeds(app);
        total = feeds.size();

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
            if (id != runId) { pool.shutdownNow(); return; }
            List<Item> part;
            try {
                Future<List<Item>> f = done.take();
                part = f.get();
            } catch (Throwable t) {
                part = Collections.emptyList();
            }
            fetched++;
            int added = merge(merged, part);
            if (added > 0 || ++batches % 40 == 0) publish(app, merged, id);
        }
        pool.shutdown();
        try { pool.awaitTermination(5, TimeUnit.SECONDS); } catch (InterruptedException ignored) { }
        if (id != runId) return;
        publish(app, merged, id);
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

    private static void publish(Context app, Map<String, Item> merged, int id) {
        if (id != runId) return;
        List<Item> all = new ArrayList<>(merged.values());
        Collections.sort(all, (a, b) -> Long.compare(b.time, a.time));
        JSONArray out = new JSONArray();
        int limit = Prefs.newsLimit(app);
        try {
            for (int i = 0; i < all.size() && i < limit; i++) {
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
            http.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14) CVEChecker/0.6");
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
