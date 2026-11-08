package moe.foss.onigiri.update;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.job.JobInfo;
import android.app.job.JobScheduler;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.SemSystemProperties;
import android.provider.OpenableColumns;
import android.provider.Settings;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.format.Formatter;
import android.text.style.BulletSpan;
import android.text.style.StyleSpan;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.List;
import java.util.zip.ZipFile;

/**
 * Software update (Settings > Onigiri Software). Checks read update.json from the latest GitHub
 * release (scripts/ota_manifest.py): the package for this model and build, and what's new. An
 * install hands the release tag and the package's sha256 to onigiri-update.sh through
 * sys.onigiri.update.*; it downloads to /cache as root, reports progress the same way and restarts
 * to recovery. UpdateJobService checks twice a day and notifies once per release. A package from
 * storage (Install from storage) is copied into Settings' own files and handed over by path instead.
 */
public final class Updates {
    private static final String RELEASES = "https://github.com/Kinue72/OnigiriDeX/releases";
    static final String FRAGMENT = "moe.foss.onigiri.update.UpdateSettingsFragment";
    /** Settings.Global switch for the notification, on by default. */
    static final String NOTIFY = "onigiri_update_notify";
    static final String CHANNEL = "onigiri_update";
    static final int AVAILABLE = 1, UPDATED = 2;
    private static final int JOB = 0x6f6e6901;

    /** What a check found. */
    public static final class Offer {
        /** The latest release and the installed one's tag (null when it isn't a recent release). */
        public String tag, installedTag;
        public boolean upToDate;
        /** The package that updates this build, or null when it needs a full flash. */
        public String file, sha256;
        public long size;
        /** What's new since the installed build, or in it when it's up to date. */
        public final List<String> news = new ArrayList<String>(), fixes = new ArrayList<String>();
    }

    private Updates() {
    }

    static SharedPreferences prefs(Context c) {
        return c.createDeviceProtectedStorageContext().getSharedPreferences("onigiri_update", 0);
    }

    /** The releases, or sys.onigiri.update.releases instead (testing; onigiri-update.sh reads it too). */
    static String releases() {
        return SemSystemProperties.get("sys.onigiri.update.releases", RELEASES);
    }

    static String version() {
        return SemSystemProperties.get("ro.onigiri.version", "");
    }

    /** Fetches update.json and keeps it; on the network, so never on the main thread. */
    static Offer check(Context c) throws IOException, JSONException {
        HttpURLConnection http = (HttpURLConnection) new URL(releases() + "/latest/download/update.json").openConnection();
        http.setConnectTimeout(20000);
        http.setReadTimeout(20000);
        try {
            if (http.getResponseCode() != 200) throw new IOException("HTTP " + http.getResponseCode());
            InputStream in = http.getInputStream();
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            for (int n; (n = in.read(buffer)) > 0; ) out.write(buffer, 0, n);
            String json = out.toString("UTF-8");
            Offer offer = parse(json);
            prefs(c).edit().putString("json", json).putLong("checked", System.currentTimeMillis()).apply();
            // Installed some other way (Odin): the offer is gone.
            if (offer.upToDate) c.getSystemService(NotificationManager.class).cancel(AVAILABLE);
            return offer;
        } finally {
            http.disconnect();
        }
    }

    /** The last check's result, or null before the first. */
    static Offer cached(Context c) {
        String json = prefs(c).getString("json", null);
        try {
            return json == null ? null : parse(json);
        } catch (JSONException e) {
            return null;
        }
    }

    static Offer parse(String json) throws JSONException {
        JSONObject root = new JSONObject(json);
        String current = version();
        Offer offer = new Offer();
        offer.tag = root.getString("tag");
        offer.upToDate = current.equals(root.getString("version"));
        JSONObject model = root.getJSONObject("updates").optJSONObject(SemSystemProperties.get("ro.product.vendor.model", ""));
        JSONObject pkg = model == null || offer.upToDate ? null : model.optJSONObject(current);
        if (pkg != null) {
            offer.file = pkg.getString("file");
            offer.size = pkg.getLong("size");
            offer.sha256 = pkg.getString("sha256");
        }
        JSONArray releases = root.getJSONArray("releases");
        for (int i = 0; i < releases.length(); i++) {
            JSONObject release = releases.getJSONObject(i);
            if (!offer.upToDate && current.equals(release.getString("version"))) {
                offer.installedTag = release.getString("tag");
                break;
            }
            add(offer.news, release.optJSONArray("new"));
            add(offer.fixes, release.optJSONArray("fixed"));
            if (offer.upToDate) {
                offer.installedTag = offer.tag;
                break;
            }
        }
        return offer;
    }

    private static void add(List<String> list, JSONArray items) throws JSONException {
        for (int i = 0; items != null && i < items.length(); i++) list.add(items.getString(i));
    }

    /** New and Fixed, each a heading over a bulleted list. */
    static CharSequence notes(Context c, Offer offer) {
        SpannableStringBuilder text = new SpannableStringBuilder();
        section(c, text, "onigiri_update_new", offer.news);
        section(c, text, "onigiri_update_fixed", offer.fixes);
        int end = text.length();
        while (end > 0 && text.charAt(end - 1) == '\n') end--;
        return text.subSequence(0, end);
    }

    private static void section(Context c, SpannableStringBuilder text, String heading, List<String> items) {
        if (items.isEmpty()) return;
        if (text.length() > 0) text.append('\n');
        int start = text.length();
        text.append(string(c, heading)).append('\n');
        text.setSpan(new StyleSpan(Typeface.BOLD), start, text.length() - 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        int gap = Math.round(8 * c.getResources().getDisplayMetrics().density);
        for (String item : items) {
            start = text.length();
            text.append(item).append('\n');
            text.setSpan(new BulletSpan(gap), start, text.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        }
    }

    static String size(Context c, long bytes) {
        return Formatter.formatShortFileSize(c, bytes);
    }

    /** One of Settings' strings by name: resource IDs added by patches move between builds. */
    static String string(Context c, String name, Object... args) {
        return c.getString(c.getResources().getIdentifier(name, "string", c.getPackageName()), args);
    }

    // The installer (onigiri-update.sh), through system properties.

    static boolean running() {
        return !SemSystemProperties.get("sys.onigiri.update", "").isEmpty();
    }

    /** downloading, verifying, restarting, failed, or empty. */
    static String state() {
        return SemSystemProperties.get("sys.onigiri.update.state", "");
    }

    static long progress() {
        try {
            return Long.parseLong(SemSystemProperties.get("sys.onigiri.update.progress", "0"));
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    static void install(Offer offer) {
        start(offer.tag, "", offer.sha256, "downloading");
    }

    /** Installs the package importPackage kept. */
    static void installLocal(Context c, String sha256) {
        start("", localPackage(c).getPath(), sha256, "verifying");
    }

    private static void start(String tag, String file, String sha256, String state) {
        SemSystemProperties.set("sys.onigiri.update.state", state);
        SemSystemProperties.set("sys.onigiri.update.progress", "0");
        SemSystemProperties.set("sys.onigiri.update.ready", tag);
        SemSystemProperties.set("sys.onigiri.update.file", file);
        SemSystemProperties.set("sys.onigiri.update.sha256", sha256);
        SemSystemProperties.set("sys.onigiri.update", "install");
    }

    // Install from storage.

    static File localPackage(Context c) {
        return new File(c.createDeviceProtectedStorageContext().getFilesDir(), "update.zip");
    }

    /**
     * Copies a picked file into Settings' files, where onigiri-update.sh takes it from, and returns
     * its sha256. Not on the main thread. Throws when it isn't an OTA package (no updater); whether
     * it fits this build only recovery can tell, and it changes nothing when it doesn't.
     */
    static String importPackage(Context c, Uri uri) throws IOException {
        File file = localPackage(c);
        file.getParentFile().mkdirs();
        MessageDigest digest;
        try {
            digest = MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException e) {
            throw new IOException(e);
        }
        InputStream in = c.getContentResolver().openInputStream(uri);
        if (in == null) throw new IOException("Can't open " + uri);
        try {
            OutputStream out = new FileOutputStream(file);
            try {
                byte[] buffer = new byte[1 << 16];
                for (int n; (n = in.read(buffer)) > 0; ) {
                    out.write(buffer, 0, n);
                    digest.update(buffer, 0, n);
                }
            } finally {
                out.close();
            }
        } finally {
            in.close();
        }
        try {
            ZipFile zip = new ZipFile(file);
            try {
                if (zip.getEntry("META-INF/com/google/android/update-binary") == null
                        || zip.getEntry("META-INF/com/google/android/updater-script") == null) {
                    throw new IOException("Not an OTA package");
                }
            } finally {
                zip.close();
            }
        } catch (IOException e) {
            file.delete();
            throw e;
        }
        StringBuilder hex = new StringBuilder();
        for (byte b : digest.digest()) hex.append(String.format("%02x", b));
        return hex.toString();
    }

    static String displayName(Context c, Uri uri) {
        Cursor cursor = c.getContentResolver().query(uri, new String[] {OpenableColumns.DISPLAY_NAME}, null, null, null);
        if (cursor == null) return uri.getLastPathSegment();
        try {
            return cursor.moveToFirst() ? cursor.getString(0) : uri.getLastPathSegment();
        } finally {
            cursor.close();
        }
    }

    static void cancel() {
        SemSystemProperties.set("sys.onigiri.update", "cancel");
    }

    // Background checks and notifications.

    static void schedule(Context c) {
        JobScheduler jobs = c.getSystemService(JobScheduler.class);
        if (jobs.getPendingJob(JOB) != null) return;
        jobs.schedule(new JobInfo.Builder(JOB, new ComponentName(c, UpdateJobService.class))
                .setPeriodic(12 * 3600 * 1000L)
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPersisted(true)
                .build());
    }

    static boolean notifyEnabled(Context c) {
        return Settings.Global.getInt(c.getContentResolver(), NOTIFY, 1) != 0;
    }

    /** Tells about a release once, when the switch is on. */
    static void notifyAvailable(Context c, Offer offer) {
        SharedPreferences prefs = prefs(c);
        if (offer.upToDate || !notifyEnabled(c) || offer.tag.equals(prefs.getString("notified", null))) return;
        prefs.edit().putString("notified", offer.tag).apply();
        String text = offer.file != null
                ? string(c, "onigiri_update_notif_text", offer.tag, size(c, offer.size))
                : string(c, "onigiri_update_notif_full", offer.tag);
        StringBuilder big = new StringBuilder(text);
        for (String item : offer.news) big.append('\n').append(item);
        if (!offer.fixes.isEmpty()) big.append('\n').append(string(c, "onigiri_update_notif_fixes", offer.fixes.size()));
        post(c, AVAILABLE, string(c, "onigiri_update_notif_title"), text, big);
    }

    /** After the restart into a build an update installed. */
    static void notifyUpdated(Context c, String tag) {
        c.getSystemService(NotificationManager.class).cancel(AVAILABLE);
        String text = string(c, "onigiri_update_updated_text");
        post(c, UPDATED, string(c, "onigiri_update_updated_title", tag), text, text);
    }

    private static void post(Context c, int id, String title, String text, CharSequence big) {
        NotificationManager manager = c.getSystemService(NotificationManager.class);
        manager.createNotificationChannel(new NotificationChannel(CHANNEL, string(c, "onigiri_update_title"),
                NotificationManager.IMPORTANCE_DEFAULT));
        Intent page = new Intent().setClassName(c, "com.android.settings.SubSettings")
                .putExtra(":settings:show_fragment", FRAGMENT)
                .putExtra(":settings:show_fragment_title", string(c, "onigiri_update_title"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        manager.notify(id, new Notification.Builder(c, CHANNEL)
                .setSmallIcon(c.getResources().getIdentifier("ic_system_update", "drawable", c.getPackageName()))
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(new Notification.BigTextStyle().bigText(big))
                .setContentIntent(PendingIntent.getActivity(c, id, page,
                        PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT))
                .setAutoCancel(true)
                .build());
    }
}
