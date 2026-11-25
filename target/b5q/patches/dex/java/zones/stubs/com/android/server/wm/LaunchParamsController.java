package com.android.server.wm;

import android.graphics.Rect;

public class LaunchParamsController {
    public static class LaunchParams {
        public Rect mBounds;
        public TaskDisplayArea mPreferredTaskDisplayArea;
        public int mWindowingMode;
    }
}
