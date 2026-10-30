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
        db.execSQL("CREATE INDEX cve_sev ON cve(sev)");
    }

    @Override public void onUpgrade(SQLiteDatabase db, int from, int to) { }

    int count() {
        try (Cursor c = getReadableDatabase().rawQuery("SELECT COUNT(*) FROM cve", null)) {
            c.moveToFirst();
            return c.getInt(0);
        } catch (Exception e) { return 0; }
    }

    void markSeen() { try { getWritableDatabase().execSQL("UPDATE cve SET seen=1 WHERE seen=0"); } catch (Exception ignored) { } }

    /** Clears the local CVE cache. Saved CVEs live in preferences, so they survive this. */
    void clear() { try { getWritableDatabase().delete("cve", null, null); } catch (Exception ignored) { } }

    /** Inserts CVEs. With replace=false, rows that did not exist yet are added to fresh and flagged unseen. */
    void save(List<Nvd.Cve> list, boolean replace, List<Nvd.Cve> fresh) {
        if (list == null || list.isEmpty()) return;
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
        if (ids == null || ids.isEmpty()) return;
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

    void saveOne(JSONObject c) {
        ContentValues v = new ContentValues();
        v.put("id", c.optString("id"));
        v.put("pub", c.optString("pub"));
        v.put("score", c.optDouble("score", -1));
        v.put("sev", c.optString("sev", "Unrated"));
        v.put("vendor", c.optString("vendor"));
        v.put("descr", c.optString("desc"));
        v.put("seen", 1);
        try { getWritableDatabase().insertWithOnConflict("cve", null, v, SQLiteDatabase.CONFLICT_REPLACE); }
        catch (Exception ignored) { }
    }

    /**
     * Query used by the home feed and the search bar.
     * sort is "new" (default), "old" or "score". Multi-word queries must match every word.
     */
    String rows(String query, String severity, String sort, int limit) {
        StringBuilder where = new StringBuilder("1=1");
        List<String> args = new ArrayList<>();
        if (severity != null && !severity.equals("All") && !severity.isEmpty()) { where.append(" AND sev=?"); args.add(severity); }
        String q = query == null ? "" : query.trim().toLowerCase(Locale.US);
        if (q.startsWith("cve-") || q.startsWith("cve")) {
            String rest = q.substring(q.startsWith("cve-") ? 4 : 3).replaceAll("^[-\\s]+", "");
            where.append(" AND id LIKE ?");
            args.add("CVE-" + rest.toUpperCase(Locale.US) + "%");
        } else if (!q.isEmpty()) {
            String[] words = q.split("\\s+");
            int used = 0;
            for (String w : words) {
                if (w.isEmpty()) continue;
                where.append(" AND (id LIKE ? OR vendor LIKE ? OR descr LIKE ?)");
                for (int i = 0; i < 3; i++) args.add("%" + w + "%");
                if (++used >= 6) break;
            }
        }
        String order = "pub DESC";
        if ("old".equals(sort)) order = "pub ASC";
        else if ("score".equals(sort)) order = "score DESC, pub DESC";
        JSONArray out = new JSONArray();
        String sql = "SELECT id,pub,score,sev,vendor,descr,kev,seen FROM cve WHERE " + where + " ORDER BY " + order
                + " LIMIT " + Math.max(1, Math.min(500, limit));
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

    /** Backwards-compatible wrapper used by the system_server scanner. */
    String search(String query, String severity) { return rows(query, severity, "new", 120); }

    /** One CVE by id, or null. */
    JSONObject one(String id) {
        try (Cursor c = getReadableDatabase().rawQuery("SELECT id,pub,score,sev,vendor,descr,kev,seen FROM cve WHERE id=? LIMIT 1", new String[]{id})) {
            if (!c.moveToNext()) return null;
            return new JSONObject().put("id", c.getString(0)).put("pub", c.getString(1)).put("score", c.getDouble(2))
                    .put("sev", c.getString(3)).put("vendor", c.getString(4) == null ? "" : c.getString(4))
                    .put("desc", c.getString(5) == null ? "" : c.getString(5))
                    .put("kev", c.getInt(6) == 1).put("isNew", c.getInt(7) == 0);
        } catch (Exception e) { return null; }
    }
}
