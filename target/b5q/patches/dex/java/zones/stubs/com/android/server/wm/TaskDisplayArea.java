package com.android.server.wm;

import android.graphics.Rect;
import java.util.function.Consumer;

public final class TaskDisplayArea {
    public void forAllRootTasks(Consumer callback) {}
    public int getFreeformThickness() { return 0; }
    public void getStableRect(Rect out) {}
    public int getWindowingMode() { return 0; }
    public boolean isDexMode() { return false; }
}
