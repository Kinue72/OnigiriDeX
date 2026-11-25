package com.android.server.wm;

import android.os.IBinder;

public final class ActivityRecord {
    public String packageName;
    public IBinder token;
    public boolean isActivityTypeStandardOrUndefined() { return false; }
}
