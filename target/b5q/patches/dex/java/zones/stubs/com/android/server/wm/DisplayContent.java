package com.android.server.wm;

import android.graphics.Rect;
import android.view.Display;

public class DisplayContent {
    public Display mDisplay;
    public final TaskDisplayArea getDefaultTaskDisplayArea() { return null; }
    public final void getStableRect(Rect out) {}
}
