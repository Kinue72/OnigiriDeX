package com.android.settings.core;
public abstract class BasePreferenceController extends com.android.settingslib.core.AbstractPreferenceController {
    public static final int AVAILABLE = 0;
    public BasePreferenceController(android.content.Context c, String key) { super(c); }
    public abstract int getAvailabilityStatus();
    public String getPreferenceKey() { throw null; }
    public void updateState(androidx.preference.Preference p) { }
}
