package com.android.settings.dashboard;
public abstract class DashboardFragment extends androidx.preference.PreferenceFragmentCompat {
    public abstract String getLogTag();
    public abstract int getPreferenceScreenResId();
    public abstract int getMetricsCategory();
}
