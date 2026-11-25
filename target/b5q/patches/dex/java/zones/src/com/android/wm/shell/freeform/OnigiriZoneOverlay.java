package com.android.wm.shell.freeform;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Rect;
import android.view.View;

/**
 * Outlines of every zone of a layout where a window would fill it, in the style of the stock
 * DeX snap guide but fainter: it sits behind that guide while a window is dragged, and alone
 * when a shortcut swaps the layout.
 * Fills its window, which must cover the display. Shared like OnigiriZones.
 */
final class OnigiriZoneOverlay extends View {
    private final Paint mFill = new Paint();
    private final Paint mStroke = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Rect mFrame = new Rect();
    private final Rect mZone = new Rect();
    private final float mRadius;
    private OnigiriZones mZones;
    private int mGap;

    OnigiriZoneOverlay(Context context) {
        super(context);
        float dp = context.getResources().getDisplayMetrics().density;
        // dex_snapping_guide_view's corner radius, its colours at about half strength.
        mRadius = 12 * dp;
        mFill.setColor(0x14252525);
        mStroke.setColor(0x66fafafa);
        mStroke.setStyle(Paint.Style.STROKE);
        mStroke.setStrokeWidth(dp);
    }

    /**
     * Shows the zones of a layout as windows fill them: in frame, the work area in display
     * pixels, with OnigiriZones.space() between them.
     */
    void show(OnigiriZones zones, Rect frame, int gap) {
        if (zones != mZones || !frame.equals(mFrame) || gap != mGap) {
            mZones = zones;
            mFrame.set(frame);
            mGap = gap;
            invalidate();
        }
        setVisibility(VISIBLE);
    }

    @Override
    protected void onDraw(Canvas canvas) {
        for (int i = 0; mZones != null && i < mZones.count(); i++) {
            mZones.zoneRect(mFrame, i, mGap, mZone);
            canvas.drawRoundRect(mZone.left, mZone.top, mZone.right, mZone.bottom, mRadius, mRadius, mFill);
            canvas.drawRoundRect(mZone.left, mZone.top, mZone.right, mZone.bottom, mRadius, mRadius, mStroke);
        }
    }
}
