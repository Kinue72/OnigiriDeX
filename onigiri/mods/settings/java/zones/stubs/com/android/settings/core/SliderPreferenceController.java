package com.android.settings.core;
import androidx.preference.Preference;
public abstract class SliderPreferenceController extends BasePreferenceController
        implements Preference.OnPreferenceChangeListener {
    public SliderPreferenceController(android.content.Context c, String key) { super(c, key); }
    public abstract int getMax();
    public abstract int getMin();
    public abstract int getSliderPosition();
    public abstract boolean setSliderPosition(int position);
    public boolean onPreferenceChange(Preference p, Object v) { throw null; }
}
