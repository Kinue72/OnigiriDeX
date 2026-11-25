package com.android.server.wm;

import android.graphics.Rect;

public class Task {
    public int mTaskId;
    public Rect getBounds() { return null; }
    public int getChildCount() { return 0; }
    public android.content.res.Configuration getConfiguration() { return null; }
    public int getDexTaskDockingState() { return 0; }
    public DisplayContent getDisplayContent() { return null; }
    public int getFreeformThickness() { return 0; }
    public int getWindowingMode() { return 0; }
    public boolean inFreeformWindowingMode() { return false; }
    public boolean inFullscreenWindowingMode() { return false; }
    public boolean isActivityTypeStandard() { return false; }
    public boolean isActivityTypeStandardOrUndefined() { return false; }
    public boolean isDexMode() { return false; }
    public boolean isVisible() { return false; }
    public final void setLastNonFullscreenBounds(Rect bounds) {}
    public final ActivityRecord topRunningActivity(boolean focusableOnly) { return null; }
}
