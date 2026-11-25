package com.android.wm.shell.freeform;

import android.app.TaskInfo;
import android.graphics.Rect;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.widget.FrameLayout;
import com.android.wm.shell.windowdecor.MultiTaskingTaskPositioner;
import com.samsung.android.multiwindow.MultiWindowManager;

/**
 * Onigiri zones in the DeX shell: where a dragged window snaps, and what a border drag of a
 * tiled window does. Called from the hooks SystemUI patch 0002 adds to the stock classes.
 */
public final class OnigiriZoneGuide {
    /** Never a stock snap type, so DexSnappingGuide asks again on every pointer move. */
    private static final int SNAP_ZONE = 16;
    private static final int WINDOWING_MODE_FREEFORM = 5;

    // One drag at a time, all on the shell main thread.
    private static OnigiriZones sZones;
    private static int sSpace;
    private static int sMeta;
    private static int sX;
    private static int sY;
    private static final Rect sTarget = new Rect();

    private OnigiriZoneGuide() {
    }

    /** Every touch on a window caption: reads the settings once per drag, and Shift as it goes. */
    public static void onTouch(MotionEvent event) {
        if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
            sZones = OnigiriZones.current();
            sSpace = OnigiriZones.space();
        }
        sMeta = event.getMetaState();
    }

    /**
     * First in DexSnappingGuide.show(). With Shift held, a freeform window snaps into the zone
     * under the pointer, or across the zones that meet near it. Returns the snap type, or -1 to
     * leave this move to the edge guides. outline is the freeform outline thickness.
     */
    public static int show(DexSnappingGuide guide, float x, float y, TaskInfo task, int outline) {
        sX = Math.round(x);
        sY = Math.round(y);
        OnigiriZones zones = sZones;
        boolean freeform = task.getWindowingMode() == WINDOWING_MODE_FREEFORM;
        if (zones == null || (sMeta & KeyEvent.META_SHIFT_ON) == 0 || !freeform) {
            // The stock guide for restoring a maximized window draws without the zones behind
            // it. A freeform window that was on a zone either gets guide() next or no guide.
            if (!freeform || guide.mLastSnapType != SNAP_ZONE) {
                outline(guide, null);
            }
            return -1;
        }
        int[] span = zones.spanAt(guide.mVisibleFrame, sX, sY, guide.mBoundaryFinger);
        zones.rect(grown(guide.mVisibleFrame, outline), span[0], span[1], span[2], span[3],
                sSpace + 2 * outline, guide.mSnappingBounds);
        return target(guide, zones, outline);
    }

    /**
     * The pointer is at screen edges (the stock snap type bits): the zone nearest to it instead
     * of the stock half or quarter. The top edge keeps maximize while the layout has two zones.
     * outline is the freeform outline thickness, which stock halves leave between them.
     */
    public static int guide(DexSnappingGuide guide, int edges, int outline) {
        OnigiriZones zones = sZones;
        Rect frame = guide.mVisibleFrame;
        if (zones == null || edges == 2 && zones.count() < 3) {
            outline(guide, null);
            DexSnappingGuide.calculateGuideSize(edges, outline, frame, guide.mSnappingBounds,
                    guide.mSnappingOtherBounds);
            guide.mView.show(edges, guide.mSnappingBounds);
            return edges;
        }
        int x = (edges & 1) != 0 ? frame.left : (edges & 4) != 0 ? frame.right - 1 : sX;
        int y = (edges & 2) != 0 ? frame.top : (edges & 8) != 0 ? frame.bottom - 1 : sY;
        zones.zoneRect(grown(frame, outline), zones.zoneAt(frame, x, y), sSpace + 2 * outline,
                guide.mSnappingBounds);
        return target(guide, zones, outline);
    }

    private static Rect grown(Rect frame, int outline) {
        Rect grown = new Rect(frame);
        grown.inset(-outline, -outline);
        return grown;
    }

    /** Shows where the window dropped at mSnappingBounds will show, over the outlines of all zones. */
    private static int target(DexSnappingGuide guide, OnigiriZones zones, int outline) {
        // No docking partner, so no Snap Assist: DeX lays those out for halves only.
        guide.mSnappingOtherBounds.setEmpty();
        // This runs on every pointer move: lay the guide out again only when the target changed.
        if (guide.mLastSnapType != SNAP_ZONE || !guide.mSnappingBounds.equals(sTarget)
                || guide.mView.getVisibility() != View.VISIBLE) {
            sTarget.set(guide.mSnappingBounds);
            outline(guide, zones);
            // Type 0 makes the guide view use the rect as is; its typed modes assume halves.
            guide.mView.show(0, grown(sTarget, outline));
        }
        return SNAP_ZONE;
    }

    private static void outline(DexSnappingGuide guide, OnigiriZones zones) {
        View first = guide.mView.getChildAt(0);
        if (first instanceof OnigiriZoneOverlay) {
            if (zones == null) {
                first.setVisibility(View.GONE);
            } else {
                ((OnigiriZoneOverlay) first).show(zones, guide.mVisibleFrame, sSpace);
            }
        } else if (zones != null) {
            OnigiriZoneOverlay overlay = new OnigiriZoneOverlay(guide.mView.getContext());
            guide.mView.addView(overlay, 0, new FrameLayout.LayoutParams(-1, -1));
            overlay.show(zones, guide.mVisibleFrame, sSpace);
        }
    }

    /**
     * In onDragPositioningEnd, before the bounds of a border or corner drag are applied. A tiled
     * window stays on its lines (the bounds are adjusted to them), and system_server moves the
     * lines and the other tiled windows with it (OnigiriZoneController.onResize).
     */
    public static void onResize(MultiTaskingTaskPositioner positioner) {
        OnigiriZones zones;
        int outline = positioner.getFreeformThickness$1();
        if (positioner.mWindowDecoration.mIsDexMode && (zones = OnigiriZones.current()) != null
                && zones.resize(grown(positioner.mStableBounds, outline), OnigiriZones.gap(outline),
                        OnigiriZones.minSize(positioner.mWindowDecoration.mTaskInfo.configuration.densityDpi),
                        positioner.mTaskBoundsAtDragStart, positioner.mRepositionTaskBounds)) {
            MultiWindowManager.getInstance().resizeOtherTaskIfNeeded(
                    positioner.mWindowDecoration.mTaskInfo.taskId, positioner.mRepositionTaskBounds);
        }
    }
}
