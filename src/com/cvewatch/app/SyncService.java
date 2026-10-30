package com.cvewatch.app;

import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import android.os.PowerManager;

/** Foreground service keeps a long CVE download running while the screen is off. */
public class SyncService extends Service {
    @Override public IBinder onBind(Intent intent) { return null; }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        startForeground(7, Notify.progress(this, 0, "Fetching CVEs from NVD"));
        if (!Prefs.hasKey(this)) {
            Sync.state = "error";
            Sync.note = "An NVD API key is required before syncing.";
            Sync.revision++;
            stopForeground(true);
            stopSelf(startId);
            return START_NOT_STICKY;
        }
        boolean forceFull = intent != null && intent.getBooleanExtra("forceFull", false);
        boolean resync = intent != null && intent.getBooleanExtra("resync", false);
        new Thread(() -> work(forceFull, resync), "cve-sync-service").start();
        return START_NOT_STICKY;
    }

    private void work(boolean forceFull, boolean resync) {
        PowerManager.WakeLock lock = ((PowerManager) getSystemService(POWER_SERVICE))
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "cvechecker:sync");
        lock.acquire(6 * 3600 * 1000L);
        Thread sync = new Thread(() -> Sync.run(this, forceFull, resync), "cve-sync");
        sync.start();
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        try {
            while (sync.isAlive()) {
                nm.notify(7, Notify.progress(this, Sync.percent, progressText()));
                Thread.sleep(2500);
            }
        } catch (InterruptedException ignored) {
            Thread.currentThread().interrupt();
        } finally {
            if (lock.isHeld()) lock.release();
            stopForeground(true);
            stopSelf();
        }
    }

    private String progressText() {
        if (Sync.total <= 0) return "Fetching CVEs from NVD";
        int pending = Math.max(0, Sync.total - Sync.done);
        return String.format(java.util.Locale.US, "%,d / %,d downloaded", Sync.done, Sync.total)
                + (pending > 0 ? String.format(java.util.Locale.US, " \u00b7 %,d remaining", pending) : "");
    }
}
