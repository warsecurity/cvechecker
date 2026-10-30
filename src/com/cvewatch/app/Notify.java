package com.cvewatch.app;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

/** Notification helpers. Works from the app process and from system_server. */
final class Notify {
    private static final String CHANNEL = "cve_alerts_v2";
    static final int PROGRESS_ID = 7;

    private Notify() {}

    private static void channel(Context c) {
        if (Build.VERSION.SDK_INT < 26) return;
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null || nm.getNotificationChannel(CHANNEL) != null) return;
        NotificationChannel ch = new NotificationChannel(CHANNEL, "CVE watchlist alerts", NotificationManager.IMPORTANCE_HIGH);
        ch.setDescription("Watchlist CVE matches and database download status");
        nm.createNotificationChannel(ch);
    }

    private static PendingIntent open(Context c) {
        Intent i = new Intent(c, MainActivity.class);
        i.putExtra("showLatest", true);
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        int flags = Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0;
        return PendingIntent.getActivity(c, 0, i, flags | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    private static Notification.Builder builder(Context c) {
        channel(c);
        return Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(c, CHANNEL) : new Notification.Builder(c);
    }

    static Notification progress(Context c, int percent, String note) {
        return builder(c)
                .setContentTitle("CVE Checker")
                .setContentText(note == null || note.isEmpty() ? "Fetching CVEs from NVD" : note)
                .setSmallIcon(android.R.drawable.stat_notify_sync)
                .setContentIntent(open(c))
                .setOnlyAlertOnce(true)
                .setOngoing(true)
                .setProgress(100, Math.max(0, Math.min(100, percent)), percent <= 0)
                .build();
    }

    static void alert(Context c, String tag, String title, String text) {
        try {
            Notification n = builder(c)
                    .setContentTitle(title == null ? "CVE alert" : title)
                    .setContentText(text == null ? "" : text)
                    .setStyle(new Notification.BigTextStyle().bigText(text == null ? "" : text))
                    .setSmallIcon(android.R.drawable.stat_notify_error)
                    .setContentIntent(open(c))
                    .setAutoCancel(true)
                    .build();
            NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) return;
            int id = tag == null ? PROGRESS_ID + 1 : Math.abs(tag.hashCode()) % 100000 + 100;
            nm.notify(id, n);
        } catch (Throwable ignored) { }
    }
}
