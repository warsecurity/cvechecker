package com.cvewatch.app;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.TimeZone;

/** NVD API client and parser. Pure Java: it also runs inside system_server. */
final class Nvd {
    static final String ENDPOINT = "https://services.nvd.nist.gov/rest/json/cves/2.0";
    static final String CVE_ORG = "https://cveawg.mitre.org/api/cve/";
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

    static final class HttpError extends IOException {
        final int code;

        HttpError(int code, String message) {
            super(message);
            this.code = code;
        }
    }

    static String get(String url, String apiKey) throws IOException {
        HttpURLConnection http = (HttpURLConnection) new URL(url).openConnection();
        try {
            http.setConnectTimeout(20_000);
            http.setReadTimeout(120_000);
            http.setRequestProperty("User-Agent", "CVEChecker/0.6");
            http.setRequestProperty("Accept", "application/json");
            if (apiKey != null && !apiKey.isEmpty()) http.setRequestProperty("apiKey", apiKey);
            int code = http.getResponseCode();
            if (code != 200) throw new HttpError(code, "HTTP " + code + errorText(http));
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

    private static String errorText(HttpURLConnection http) {
        try (BufferedReader in = new BufferedReader(new InputStreamReader(http.getErrorStream(), "UTF-8"))) {
            String line = in.readLine();
            return line == null || line.isEmpty() ? "" : ": " + line;
        } catch (Exception ignored) {
            return "";
        }
    }

    /** totalResults for a filter without downloading anything. One cheap request. */
    static int count(String params, String apiKey) throws Exception {
        return page(params, 0, 1, apiKey).optInt("totalResults", 0);
    }

    /** Search NVD by CVE ID or free-text keywords. */
    static JSONObject search(String terms, String apiKey) throws Exception {
        String id = parseCveId(terms);
        if (id != null) {
            return new JSONObject(get(ENDPOINT + "?cveId=" + URLEncoder.encode(id, "UTF-8") + "&resultsPerPage=1", apiKey));
        }
        String q = URLEncoder.encode(terms.trim(), "UTF-8");
        return new JSONObject(get(ENDPOINT + "?keywordSearch=" + q + "&resultsPerPage=100&startIndex=0", apiKey));
    }

    /** Normalizes "cve 2026 119086", "CVE-2026-119086", etc. to a canonical CVE ID. */
    static String parseCveId(String term) {
        if (term == null) return null;
        String compact = term.trim().toUpperCase(Locale.US).replaceAll("[^A-Z0-9]", "");
        if (!compact.startsWith("CVE") || compact.length() < 11) return null;
        String rest = compact.substring(3);
        String year = rest.substring(0, 4);
        String sequence = rest.substring(4);
        if (!year.matches("\\d{4}") || !sequence.matches("\\d{4,}")) return null;
        return "CVE-" + year + "-" + sequence;
    }

    /**
     * Fallback for CVEs published by a CNA but not yet indexed by NVD.
     * CVE.org exposes the current CVE Record for a known ID.
     */
    static Cve byCveOrg(String id) throws Exception {
        String cveId = parseCveId(id);
        if (cveId == null) return null;
        JSONObject root = new JSONObject(get(CVE_ORG + URLEncoder.encode(cveId, "UTF-8"), null));
        JSONObject meta = root.optJSONObject("cveMetadata");
        if (meta == null || !"PUBLISHED".equalsIgnoreCase(meta.optString("state"))) return null;
        JSONObject containers = root.optJSONObject("containers");
        JSONObject cna = containers == null ? null : containers.optJSONObject("cna");
        if (cna == null) return null;
        Cve cve = new Cve();
        cve.id = meta.optString("cveId", cveId);
        cve.published = meta.optString("datePublished", "");
        cve.description = english(cna.optJSONArray("descriptions"));
        cve.score = cveOrgScore(containers);
        cve.vendor = cveOrgVendor(cna.optJSONArray("affected"));
        return cve;
    }

    private static double cveOrgScore(JSONObject containers) {
        double best = -1;
        JSONObject cna = containers.optJSONObject("cna");
        if (cna != null) best = Math.max(best, metricsScore(cna.optJSONArray("metrics")));
        JSONArray adp = containers.optJSONArray("adp");
        for (int i = 0; adp != null && i < adp.length(); i++) {
            JSONObject item = adp.optJSONObject(i);
            if (item != null) best = Math.max(best, metricsScore(item.optJSONArray("metrics")));
        }
        return best;
    }

    private static double metricsScore(JSONArray metrics) {
        double best = -1;
        for (int i = 0; metrics != null && i < metrics.length(); i++) {
            JSONObject item = metrics.optJSONObject(i);
            if (item == null) continue;
            for (String key : new String[]{"cvssV4_0", "cvssV3_1", "cvssV3_0", "cvssV2_0"}) {
                JSONObject data = item.optJSONObject(key);
                if (data != null) best = Math.max(best, data.optDouble("baseScore", -1));
            }
        }
        return best;
    }

    private static String cveOrgVendor(JSONArray affected) {
        if (affected == null) return "";
        for (int i = 0; i < affected.length(); i++) {
            JSONObject item = affected.optJSONObject(i);
            if (item == null) continue;
            String vendor = item.optString("vendor", "").trim();
            String product = item.optString("product", "").trim();
            if (!vendor.isEmpty()) return product.isEmpty() ? vendor : vendor + " " + product;
            if (!product.isEmpty()) return product;
        }
        return "";
    }

    /** Fetch one known CVE by ID using the authenticated NVD endpoint. */
    static JSONObject byId(String id, String apiKey) throws Exception {
        String q = URLEncoder.encode(id.trim(), "UTF-8");
        return new JSONObject(get(ENDPOINT + "?cveId=" + q + "&resultsPerPage=1", apiKey));
    }

    /** One page of results with retries. Halves the page size if memory runs out. */
    static JSONObject page(String params, int start, String apiKey) throws Exception {
        return page(params, start, pageSize, apiKey);
    }

    /** One page with an explicit size, so gentle background fetches can use smaller batches. */
    static JSONObject page(String params, int start, int size, String apiKey) throws Exception {
        Exception last = null;
        for (int attempt = 1; attempt <= 5; attempt++) {
            try {
                String query = (params.isEmpty() ? "" : params + "&") + "resultsPerPage=" + size + "&startIndex=" + start;
                return new JSONObject(get(ENDPOINT + "?" + query, apiKey));
            } catch (OutOfMemoryError e) {
                size = Math.max(250, size / 2);
                pageSize = size;
                last = new Exception("out of memory, batch reduced to " + size);
            } catch (Exception e) {
                last = e;
                if (e instanceof HttpError) {
                    int code = ((HttpError) e).code;
                    if (code != 429 && code < 500) throw e;
                }
            }
            Thread.sleep(4000L * attempt);
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
