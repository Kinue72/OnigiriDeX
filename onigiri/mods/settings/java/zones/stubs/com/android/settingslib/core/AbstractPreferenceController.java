package com.android.settingslib.core;
public abstract class AbstractPreferenceController {
    protected final android.content.Context mContext;
    public AbstractPreferenceController(android.content.Context c) { mContext = c; }
    public void displayPreference(androidx.preference.PreferenceScreen s) { }
}
