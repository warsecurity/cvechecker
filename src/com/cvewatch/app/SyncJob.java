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
        long cveInterval = Prefs.intervalMinutes(c) * 60_000L;
        int newsMinutes = Prefs.newsIntervalMinutes(c);
        long newsInterval = newsMinutes > 0 ? newsMinutes * 60_000L : cveInterval;
        long interval = Math.max(15 * 60_000L, Math.min(cveInterval, newsInterval));
        JobInfo existing = scheduler.getPendingJob(1);
        if (existing != null && existing.getIntervalMillis() == interval) return;
        scheduler.schedule(new JobInfo.Builder(1, new ComponentName(c, SyncJob.class))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPeriodic(interval).setPersisted(true).build());
    }

    @Override public boolean onStartJob(JobParameters params) {
        new Thread(() -> {
            if (Sync.due(this) && !Sync.running()) Sync.run(this);
            int newsMinutes = Prefs.newsIntervalMinutes(this);
            if (newsMinutes > 0 && System.currentTimeMillis() - Prefs.newsLoadedAt(this) >= newsMinutes * 60_000L) {
                News.trimToLimit(this);
                News.refresh(this);
                long deadline = System.currentTimeMillis() + 90_000L;
                while (News.active() && System.currentTimeMillis() < deadline) {
                    try { Thread.sleep(500); } catch (InterruptedException e) { Thread.currentThread().interrupt(); break; }
                }
            }
            jobFinished(params, false);
        }, "cve-sync-job").start();
        return true;
    }

    @Override public boolean onStopJob(JobParameters params) { return true; }
}
