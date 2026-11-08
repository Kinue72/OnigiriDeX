package moe.foss.onigiri.update;

import android.app.job.JobParameters;
import android.app.job.JobService;
import android.util.Log;

/** The twice-daily check (Updates.schedule): notifies once per release. */
public class UpdateJobService extends JobService {
    @Override
    public boolean onStartJob(final JobParameters params) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    Updates.notifyAvailable(UpdateJobService.this, Updates.check(UpdateJobService.this));
                } catch (Exception e) {
                    Log.w("OnigiriUpdate", "Update check failed", e);
                }
                jobFinished(params, false);
            }
        }).start();
        return true;
    }

    @Override
    public boolean onStopJob(JobParameters params) {
        return false;
    }
}
