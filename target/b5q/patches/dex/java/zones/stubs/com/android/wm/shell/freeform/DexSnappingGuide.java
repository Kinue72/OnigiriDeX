package com.android.wm.shell.freeform;

import android.graphics.Rect;

public final class DexSnappingGuide {
    public int mBoundaryFinger;
    public int mLastSnapType;
    public Rect mSnappingBounds;
    public Rect mSnappingOtherBounds;
    public DexSnappingGuideView mView;
    public Rect mVisibleFrame;
    public static void calculateGuideSize(int type, int gap, Rect frame, Rect bounds, Rect otherBounds) {}
}
