package com.android.settings.core;
import com.samsung.android.settings.cube.*;
public abstract class BasePreferenceController {
    public BasePreferenceController(android.content.Context c, String key) { }
    public abstract int getAvailabilityStatus();
    public void updateState(androidx.preference.Preference p) { }
    public abstract android.content.Intent getLaunchIntent();
    public abstract String getStatusText();
    public abstract ControlValue getValue();
    public abstract boolean isControllable();
    public abstract Controllable.ControllableType needUserInteraction(Object o);
    public abstract boolean runDefaultAction();
    public abstract ControlResult setValue(ControlValue v);
    public abstract int getSliceHighlightMenuRes();
}
