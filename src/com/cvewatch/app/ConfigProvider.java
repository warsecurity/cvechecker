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
                            .put("interval", Prefs.intervalMinutes(c))
                            .put("lastChange", Prefs.get(c).getLong("lastChange", 0)).toString());
                    break;
                case "alert":
                    Notify.alert(c, arg, extras == null ? "CVE alert" : extras.getString("title"),
                            extras == null ? "" : extras.getString("text"));
                    break;
                case "beat":
                    Prefs.saveBeat(c, extras == null ? System.currentTimeMillis() : extras.getLong("time"),
                            extras == null ? 0 : extras.getInt("found"), extras == null ? "" : extras.getString("error"));
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
