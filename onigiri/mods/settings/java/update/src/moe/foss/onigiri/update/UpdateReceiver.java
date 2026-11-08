package moe.foss.onigiri.update;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

/**
 * At boot: schedules the update checks, and after a build change that an update installed (the
 * last check offered the build now running) says so.
 */
public class UpdateReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context c, Intent intent) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) return;
        Updates.schedule(c);
        SharedPreferences prefs = Updates.prefs(c);
        String version = Updates.version();
        String last = prefs.getString("installed", null);
        if (version.equals(last)) return;
        prefs.edit().putString("installed", version).apply();
        Updates.Offer offer = Updates.cached(c);
        if (last != null && offer != null && offer.upToDate) Updates.notifyUpdated(c, offer.tag);
    }
}
