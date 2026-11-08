package moe.foss.onigiri.update;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.res.ColorStateList;
import android.content.res.TypedArray;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.net.Uri;
import android.os.BatteryManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SemSystemProperties;
import android.provider.Settings;
import android.text.format.DateUtils;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

import androidx.preference.Preference;
import androidx.preference.TwoStatePreference;

import com.android.settings.dashboard.DashboardFragment;

/**
 * The Software update page (res/xml/onigiri_update_settings.xml): the release on offer and its
 * size, what's new, Check for updates and the notification switch, and below the list a bar with
 * Download and install (or the release page when the build needs a full flash), which turns into
 * the installer's progress. Opening the page checks again when the last check is over 30 minutes
 * old. Install from storage picks a package file, which installs the same way once confirmed.
 */
public class UpdateSettingsFragment extends DashboardFragment implements Runnable, View.OnClickListener {
    private static final long STALE = 30 * DateUtils.MINUTE_IN_MILLIS;
    private static final int PICK = 1;

    private final Handler mHandler = new Handler(Looper.getMainLooper());
    private Updates.Offer mOffer;
    private boolean mChecking, mCheckFailed, mImporting;
    private TextView mButton, mStep, mAmount, mCancel;
    private View mBar, mProgressRow;
    private ProgressBar mProgress;

    @Override
    public String getLogTag() {
        return "OnigiriUpdate";
    }

    @Override
    public int getMetricsCategory() {
        return 0x2e8;
    }

    @Override
    public int getPreferenceScreenResId() {
        Context c = getContext();
        return c.getResources().getIdentifier("onigiri_update_settings", "xml", c.getPackageName());
    }

    @Override
    public void onViewCreated(View view, Bundle state) {
        super.onViewCreated(view, state);
        // The list sits in a vertical LinearLayout (preference_list_fragment): pin the bar under it.
        View list = view.findViewById(android.R.id.list_container);
        ViewGroup parent = (ViewGroup) list.getParent();
        mBar = bar(view.getContext());
        parent.addView(mBar, parent.indexOfChild(list) + 1);

        findPreference("onigiri_update_check").setOnPreferenceClickListener(new Preference.OnPreferenceClickListener() {
            @Override
            public boolean onPreferenceClick(Preference p) {
                check();
                return true;
            }
        });
        findPreference("onigiri_update_local").setOnPreferenceClickListener(new Preference.OnPreferenceClickListener() {
            @Override
            public boolean onPreferenceClick(Preference p) {
                Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*")
                        .putExtra(Intent.EXTRA_MIME_TYPES, new String[] {"application/zip", "application/x-zip-compressed",
                                "application/octet-stream"});
                startActivityForResult(pick, PICK);
                return true;
            }
        });
        findPreference(Updates.NOTIFY).setOnPreferenceChangeListener(new Preference.OnPreferenceChangeListener() {
            @Override
            public boolean onPreferenceChange(Preference p, Object value) {
                Settings.Global.putInt(getContext().getContentResolver(), Updates.NOTIFY, (Boolean) value ? 1 : 0);
                return true;
            }
        });
    }

    @Override
    public void onResume() {
        super.onResume();
        Context c = getContext();
        Updates.schedule(c);
        mOffer = Updates.cached(c);
        ((TwoStatePreference) findPreference(Updates.NOTIFY)).setChecked(Updates.notifyEnabled(c));
        if (!Updates.running() && System.currentTimeMillis() - Updates.prefs(c).getLong("checked", 0) > STALE) {
            check();
        }
        run();
    }

    @Override
    public void onPause() {
        super.onPause();
        mHandler.removeCallbacks(this);
    }

    private void check() {
        if (mChecking) return;
        mChecking = true;
        mCheckFailed = false;
        if ("failed".equals(Updates.state())) SemSystemProperties.set("sys.onigiri.update.state", "");
        final Context c = getContext().getApplicationContext();
        render();
        new Thread(new Runnable() {
            @Override
            public void run() {
                Updates.Offer offer = null;
                try {
                    offer = Updates.check(c);
                } catch (Exception e) {
                    // Shown as the header's error.
                }
                final Updates.Offer result = offer;
                mHandler.post(new Runnable() {
                    @Override
                    public void run() {
                        mChecking = false;
                        mCheckFailed = result == null;
                        if (result != null) mOffer = result;
                        if (isAdded()) render();
                    }
                });
            }
        }).start();
    }

    @Override
    public void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request != PICK || result != Activity.RESULT_OK || data == null || data.getData() == null) return;
        final Uri uri = data.getData();
        final Context c = getContext().getApplicationContext();
        mImporting = true;
        render();
        new Thread(new Runnable() {
            @Override
            public void run() {
                String sha256 = null;
                try {
                    sha256 = Updates.importPackage(c, uri);
                } catch (Exception e) {
                    // Said in a dialog below.
                }
                final String result = sha256;
                final String name = Updates.displayName(c, uri);
                mHandler.post(new Runnable() {
                    @Override
                    public void run() {
                        mImporting = false;
                        if (!isAdded()) return;
                        render();
                        confirmLocal(name, result);
                    }
                });
            }
        }).start();
    }

    /** Renders, and while the installer runs, again every half second. */
    @Override
    public void run() {
        render();
        if (Updates.running()) mHandler.postDelayed(this, 500);
    }

    private void render() {
        Context c = getContext();
        Updates.Offer offer = mOffer;
        boolean running = Updates.running();
        String state = Updates.state();
        boolean available = offer != null && !offer.upToDate && offer.file != null;

        String installed = offer != null && offer.installedTag != null ? offer.installedTag
                : SemSystemProperties.get("ro.onigiri.version", "");
        Preference header = findPreference("onigiri_update_header");
        header.setTitle("Onigiri " + (offer != null ? offer.tag : installed));
        String summary;
        if (mChecking) {
            summary = Updates.string(c, "onigiri_update_checking");
        } else if (mCheckFailed) {
            summary = Updates.string(c, "onigiri_update_error");
        } else if (offer == null) {
            summary = SemSystemProperties.get("ro.onigiri.build", "");
        } else if (offer.upToDate) {
            summary = Updates.string(c, "onigiri_update_up_to_date");
        } else if (available) {
            summary = Updates.string(c, "onigiri_update_available", Updates.size(c, offer.size), installed);
        } else {
            summary = Updates.string(c, "onigiri_update_full", installed);
        }
        header.setSummary(summary);

        CharSequence notes = offer == null ? "" : Updates.notes(c, offer);
        findPreference("onigiri_update_notes_group").setVisible(notes.length() > 0);
        findPreference("onigiri_update_notes_gap").setVisible(notes.length() > 0);
        findPreference("onigiri_update_notes").setSummary(notes);

        long checked = Updates.prefs(c).getLong("checked", 0);
        Preference check = findPreference("onigiri_update_check");
        check.setEnabled(!mChecking && !running);
        Preference local = findPreference("onigiri_update_local");
        local.setEnabled(!mImporting && !running);
        local.setSummary(Updates.string(c, mImporting ? "onigiri_update_local_reading" : "onigiri_update_local_summary"));
        check.setSummary(checked == 0 ? null : Updates.string(c, "onigiri_update_last_checked",
                DateUtils.formatSameDayTime(checked, System.currentTimeMillis(),
                        java.text.DateFormat.MEDIUM, java.text.DateFormat.SHORT)));

        if (mButton == null) return;
        boolean full = offer != null && !offer.upToDate && offer.file == null;
        mButton.setVisibility(!running && (available || full) ? View.VISIBLE : View.GONE);
        mButton.setText(Updates.string(c, available ? "onigiri_update_install" : "onigiri_update_release_page"));
        // A failed download says so above the button too: the header may be scrolled away.
        boolean failed = !running && "failed".equals(state) && available;
        mProgressRow.setVisibility(running || failed ? View.VISIBLE : View.GONE);
        mProgress.setVisibility(running ? View.VISIBLE : View.GONE);
        mCancel.setVisibility(running && "downloading".equals(state) ? View.VISIBLE : View.GONE);
        if (failed) {
            mStep.setText(Updates.string(c, "onigiri_update_failed"));
            mAmount.setText("");
        }
        if (!running) return;
        long total = offer != null ? offer.size : 0;
        long done = Math.min(Updates.progress(), total);
        mStep.setText(Updates.string(c, "verifying".equals(state) ? "onigiri_update_verifying"
                : "restarting".equals(state) ? "onigiri_update_restarting" : "onigiri_update_downloading"));
        mAmount.setText(total > 0 && "downloading".equals(state)
                ? Updates.string(c, "onigiri_update_progress", Updates.size(c, done), Updates.size(c, total)) : "");
        mProgress.setProgress(total > 0 && "downloading".equals(state) ? (int) (done * 1000 / total) : 1000);
    }

    @Override
    public void onClick(View v) {
        if (v == mCancel) {
            Updates.cancel();
            return;
        }
        Updates.Offer offer = mOffer;
        if (offer == null) return;
        if (offer.file == null) {
            getActivity().startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(Updates.releases() + "/tag/" + offer.tag)));
            return;
        }
        confirm(offer);
    }

    private void confirm(final Updates.Offer offer) {
        Activity activity = getActivity();
        confirm(Updates.string(activity, "onigiri_update_confirm_title", offer.tag),
                Updates.string(activity, "onigiri_update_confirm_body"), new Runnable() {
                    @Override
                    public void run() {
                        Updates.install(offer);
                    }
                }, null);
    }

    /** A picked package: the usual question when it's the one this build is offered, else a caveat. */
    private void confirmLocal(String name, final String sha256) {
        final Activity activity = getActivity();
        if (sha256 == null) {
            show(new AlertDialog.Builder(activity)
                    .setMessage(Updates.string(activity, "onigiri_update_local_invalid"))
                    .setPositiveButton(android.R.string.ok, null), null);
            return;
        }
        Updates.Offer offer = mOffer;
        String installed = offer != null && offer.installedTag != null ? offer.installedTag
                : SemSystemProperties.get("ro.onigiri.version", "");
        boolean offered = offer != null && sha256.equals(offer.sha256);
        confirm(offered ? Updates.string(activity, "onigiri_update_confirm_title", offer.tag)
                        : Updates.string(activity, "onigiri_update_local_title", name),
                offered ? Updates.string(activity, "onigiri_update_confirm_body")
                        : Updates.string(activity, "onigiri_update_local_body", installed),
                new Runnable() {
                    @Override
                    public void run() {
                        Updates.installLocal(activity, sha256);
                    }
                },
                new Runnable() {
                    @Override
                    public void run() {
                        Updates.localPackage(activity).delete();
                    }
                });
    }

    /** Asks before installing; below 20% battery and unplugged it says to charge instead. */
    private void confirm(String title, String body, final Runnable install, final Runnable cancel) {
        Activity activity = getActivity();
        Intent battery = activity.registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        int level = battery == null ? 100 : battery.getIntExtra(BatteryManager.EXTRA_LEVEL, 100) * 100
                / Math.max(1, battery.getIntExtra(BatteryManager.EXTRA_SCALE, 100));
        boolean plugged = battery != null && battery.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0;
        if (level < 20 && !plugged) {
            if (cancel != null) cancel.run();
            show(new AlertDialog.Builder(activity)
                    .setMessage(Updates.string(activity, "onigiri_update_battery"))
                    .setPositiveButton(android.R.string.ok, null), null);
            return;
        }
        final boolean[] installing = {false};
        show(new AlertDialog.Builder(activity)
                .setTitle(title)
                .setMessage(body)
                .setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton(Updates.string(activity, "onigiri_update_install_button"),
                        new DialogInterface.OnClickListener() {
                            @Override
                            public void onClick(DialogInterface dialog, int which) {
                                installing[0] = true;
                                install.run();
                                UpdateSettingsFragment.this.run();
                            }
                        }),
                new Runnable() {
                    @Override
                    public void run() {
                        if (!installing[0] && cancel != null) cancel.run();
                    }
                });
    }

    /**
     * One UI puts dialogs at the bottom, where the bar's button would peek out under them like a
     * border: the bar hides (keeping its room) until the dialog is gone.
     */
    private void show(AlertDialog.Builder dialog, final Runnable dismissed) {
        mBar.setVisibility(View.INVISIBLE);
        dialog.setOnDismissListener(new DialogInterface.OnDismissListener() {
            @Override
            public void onDismiss(DialogInterface d) {
                if (dismissed != null) dismissed.run();
                mBar.setVisibility(View.VISIBLE);
                if (isAdded()) render();
            }
        }).show();
    }

    /** Download and install, or Downloading with its progress and Cancel. */
    private View bar(Context c) {
        // One UI blue: the app theme's colorPrimary (sesl_primary_color), not android:colorAccent.
        int accent = color(c, c.getResources().getIdentifier("colorPrimary", "attr", c.getPackageName()));
        LinearLayout bar = new LinearLayout(c);
        bar.setOrientation(LinearLayout.VERTICAL);
        bar.setBackgroundColor(c.getColor(c.getResources().getIdentifier("sec_widget_round_and_bgcolor", "color",
                c.getPackageName())));
        bar.setPadding(dp(c, 16), dp(c, 8), dp(c, 16), dp(c, 12));

        mButton = text(c, 16, Typeface.BOLD, 0xffffffff);
        mButton.setGravity(Gravity.CENTER);
        mButton.setPadding(0, dp(c, 12), 0, dp(c, 12));
        GradientDrawable shape = new GradientDrawable();
        shape.setColor(accent);
        shape.setCornerRadius(dp(c, 24));
        mButton.setBackground(new RippleDrawable(ColorStateList.valueOf(0x33ffffff), shape, null));
        mButton.setOnClickListener(this);

        LinearLayout row = new LinearLayout(c);
        mProgressRow = row;
        mStep = text(c, 15, Typeface.NORMAL, color(c, android.R.attr.textColorPrimaryNoDisable));
        mAmount = text(c, 14, Typeface.NORMAL, color(c, android.R.attr.textColorSecondaryNoDisable));
        row.addView(mStep, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        row.addView(mAmount);
        LinearLayout.LayoutParams rowParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        rowParams.bottomMargin = dp(c, 4);
        bar.addView(row, rowParams);

        mProgress = new ProgressBar(c, null, android.R.attr.progressBarStyleHorizontal);
        mProgress.setMax(1000);
        mProgress.setProgressTintList(ColorStateList.valueOf(accent));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(c, 4));
        params.topMargin = dp(c, 8);
        params.bottomMargin = dp(c, 4);
        bar.addView(mProgress, params);

        mCancel = text(c, 15, Typeface.BOLD, accent);
        mCancel.setText(android.R.string.cancel);
        mCancel.setGravity(Gravity.CENTER);
        mCancel.setPadding(0, dp(c, 8), 0, dp(c, 4));
        mCancel.setOnClickListener(this);
        bar.addView(mCancel);
        bar.addView(mButton);
        return bar;
    }

    private static TextView text(Context c, int sp, int style, int color) {
        TextView view = new TextView(c);
        view.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        view.setTypeface(Typeface.create(Typeface.DEFAULT, style));
        view.setTextColor(color);
        return view;
    }

    private static int color(Context c, int attr) {
        TypedArray values = c.obtainStyledAttributes(new int[] {attr});
        try {
            return values.getColor(0, 0xff3e91ff);
        } finally {
            values.recycle();
        }
    }

    private static int dp(Context c, int dp) {
        return Math.round(dp * c.getResources().getDisplayMetrics().density);
    }
}
