package moe.foss.onigiri.settings;

import android.content.Context;
import android.os.SemSystemProperties;
import android.widget.SeekBar;
import androidx.preference.Preference;
import androidx.preference.PreferenceScreen;
import com.android.settings.core.SliderPreferenceController;
import com.android.settings.widget.SeekBarPreference;

/**
 * The space DeX zones leave around every window, in pixels: persist.sys.onigiri.dex_zone_gap,
 * read by OnigiriZones in SystemUI and system_server (8 when unset). The row
 * (onigiri_zone_gap_seekbar) shows the value and a picture that follow the slider as it is
 * dragged; the prop is written once, when the drag ends.
 */
public class DexZoneGapPreferenceController extends SliderPreferenceController
        implements SeekBar.OnSeekBarChangeListener {
    private static final String PROP = "persist.sys.onigiri.dex_zone_gap";
    private static final int DEFAULT = 8;
    private static final int MAX = 32;

    private DexZoneGapDemo mDemo;
    private boolean mDragging;

    public DexZoneGapPreferenceController(Context context, String key) {
        super(context, key);
    }

    @Override
    public int getAvailabilityStatus() {
        return AVAILABLE;
    }

    @Override
    public int getMin() {
        return 0;
    }

    @Override
    public int getMax() {
        return MAX;
    }

    @Override
    public void displayPreference(PreferenceScreen screen) {
        super.displayPreference(screen);
        Preference preference = screen.findPreference(getPreferenceKey());
        if (preference instanceof SeekBarPreference) {
            SeekBarPreference slider = (SeekBarPreference) preference;
            mDemo = new DexZoneGapDemo(mContext);
            // The row layout puts the icon above the slider.
            slider.setIcon(mDemo);
            slider.mContinuousUpdates = true;
            slider.mOnSeekBarChangeListener = this;
        }
    }

    /** As OnigiriZones.space() reads it. */
    @Override
    public int getSliderPosition() {
        try {
            return Math.max(0, Math.min(MAX, Integer.parseInt(SemSystemProperties.get(PROP, ""))));
        } catch (NumberFormatException e) {
            return DEFAULT;
        }
    }

    @Override
    public boolean setSliderPosition(int position) {
        if (!mDragging) {
            SemSystemProperties.set(PROP, String.valueOf(position));
        }
        return true;
    }

    @Override
    public boolean onPreferenceChange(Preference preference, Object value) {
        show(preference, (Integer) value);
        return super.onPreferenceChange(preference, value);
    }

    @Override
    public void updateState(Preference preference) {
        super.updateState(preference);
        show(preference, getSliderPosition());
    }

    private void show(Preference preference, int gap) {
        preference.setSummary(gap + " px");
        if (mDemo != null) {
            mDemo.setLevel(gap);
        }
    }

    @Override
    public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
    }

    @Override
    public void onStartTrackingTouch(SeekBar seekBar) {
        mDragging = true;
    }

    @Override
    public void onStopTrackingTouch(SeekBar seekBar) {
        mDragging = false;
        setSliderPosition(seekBar.getProgress());
    }
}
