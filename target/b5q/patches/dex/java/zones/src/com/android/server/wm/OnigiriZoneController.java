package com.android.server.wm;

import android.app.ActivityOptions;
import android.content.Context;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.os.IBinder;
import android.os.SystemProperties;
import android.view.Display;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.WindowManager;
import com.android.server.UiThread;
import java.util.function.Consumer;

/**
 * Onigiri zones in system_server: where new DeX windows open, the keyboard shortcuts, and
 * keeping tiled windows together when a line moves or the layout is swapped. Called from the
 * hooks services.jar patch 0003 adds to the stock classes: onKey takes the WM lock, the others
 * are called with it held.
 *
 * An instance walks the freeform windows of a DeX desktop: with a target layout it moves the
 * tiled ones to it, without one it looks for a window tiled outside the main zone.
 */
public final class OnigiriZoneController implements Consumer<Task> {
    private static final int WINDOWING_MODE_FULLSCREEN = 1;
    private static final int WINDOWING_MODE_FREEFORM = 5;
    /** ActivityTaskManager.RESIZE_MODE_USER_FORCED, as DexDockingController resizes neighbours. */
    private static final int RESIZE_MODE_USER_FORCED = 3;

    private final ActivityTaskManagerService mAtm;
    private final OnigiriZones mFrom;
    private final OnigiriZones mTo;
    private final Rect mFrame;
    private final int mGap;
    private final Task mSkip;
    private boolean mSideInUse;

    private OnigiriZoneController(ActivityTaskManagerService atm, OnigiriZones from, OnigiriZones to,
            Rect frame, int gap, Task skip) {
        mAtm = atm;
        mFrom = from;
        mTo = to;
        mFrame = frame;
        mGap = gap;
        mSkip = skip;
    }

    @Override
    public void accept(Task task) {
        if (task == mSkip || !task.isVisible() || task.getWindowingMode() != WINDOWING_MODE_FREEFORM
                || !task.isActivityTypeStandard()) {
            return;
        }
        Rect bounds = new Rect(task.getBounds());
        if (mTo == null) {
            int[] span = mFrom.span(mFrame, mGap, bounds);
            int main = mFrom.main * 4;
            mSideInUse |= span != null && (span[0] > mFrom.cells[main] || span[1] > mFrom.cells[main + 1]
                    || span[2] < mFrom.cells[main + 2] || span[3] < mFrom.cells[main + 3]);
        } else if (mFrom.fit(mTo, mFrame, mGap, bounds)) {
            mAtm.resizeTask(task.mTaskId, bounds, RESIZE_MODE_USER_FORCED);
        }
    }

    /**
     * Last in LaunchParamsController.calculate, before the assistant overlay policy. A brand-new
     * DeX window opens in the zone its app was given in Settings, otherwise in the main zone
     * while a window is tiled outside it.
     */
    public static void applyLaunch(Task task, ActivityRecord activity, ActivityOptions options,
            LaunchParamsController.LaunchParams params) {
        // Relaunching an existing window keeps its place.
        if (task != null && task.getChildCount() != 0 || activity == null || params == null) {
            return;
        }
        TaskDisplayArea area = params.mPreferredTaskDisplayArea;
        // Undefined means inherit the display area mode, which is freeform on DeX. DeX reopens an
        // app it last showed maximized in fullscreen; only an app given a zone leaves it.
        int mode = params.mWindowingMode != 0 || area == null ? params.mWindowingMode : area.getWindowingMode();
        if (area == null || mode != WINDOWING_MODE_FREEFORM && mode != WINDOWING_MODE_FULLSCREEN) {
            return;
        }
        // Explicit placement (launcher drag) wins.
        Rect asked = options != null ? options.getLaunchBounds() : null;
        // The new ActivityRecord has no type until it joins its task.
        if (asked != null && !asked.isEmpty() || !activity.isActivityTypeStandardOrUndefined()
                || !area.isDexMode()) {
            return;
        }
        OnigiriZones zones = OnigiriZones.current();
        if (zones == null) {
            return;
        }
        Rect frame = new Rect();
        area.getStableRect(frame);
        int gap = area.getFreeformThickness();
        for (int i = 0; i < zones.count(); i++) {
            if (activity.packageName.equals(SystemProperties.get("persist.sys.onigiri.dex_zone_app." + i, ""))) {
                // Undefined: the desktop's freeform, also for an app DeX would reopen maximized.
                params.mWindowingMode = 0;
                zones.zoneRect(frame, i, gap, params.mBounds);
                return;
            }
        }
        // Any other app DeX reopens maximized stays that way.
        if (params.mWindowingMode == WINDOWING_MODE_FULLSCREEN) {
            return;
        }
        OnigiriZoneController probe = new OnigiriZoneController(null, zones, null, frame, gap, null);
        area.forAllRootTasks(probe);
        if (probe.mSideInUse) {
            zones.zoneRect(frame, zones.main, gap, params.mBounds);
        }
    }

    /**
     * First in DexMetaKeyPolicy.handleMetaKeyEvent. Meta+Left or Right moves the focused window
     * to the zone on that side (a window that is not tiled snaps in near where it is); Meta+Up
     * or Down moves between stacked zones. False leaves the key to stock DeX: zones off, Shift
     * held, or Up and Down with no zone that way (maximize, minimize).
     */
    public static boolean onArrow(ActivityTaskManagerService atm, IBinder focus, KeyEvent event) {
        OnigiriZones zones;
        if (event.isShiftPressed() || (zones = OnigiriZones.current()) == null) {
            return false;
        }
        WindowState window = (WindowState) atm.mWindowManager.mInputToWindowMap.get(focus);
        Task task = window != null ? window.getTask() : null;
        if (task == null || task.getDisplayContent() == null || !task.isDexMode()) {
            return false;
        }
        boolean freeform = task.inFreeformWindowingMode();
        if (!freeform && !(task.inFullscreenWindowingMode() && task.isActivityTypeStandardOrUndefined())) {
            return false;
        }
        int key = event.getKeyCode();
        int dx = key == KeyEvent.KEYCODE_DPAD_LEFT ? -1 : key == KeyEvent.KEYCODE_DPAD_RIGHT ? 1 : 0;
        int dy = key == KeyEvent.KEYCODE_DPAD_UP ? -1 : key == KeyEvent.KEYCODE_DPAD_DOWN ? 1 : 0;
        Rect frame = new Rect();
        task.getDisplayContent().getStableRect(frame);
        int gap = task.getFreeformThickness();
        Rect bounds = task.getBounds();
        int[] span = freeform ? zones.span(frame, gap, bounds) : null;
        int zone = span != null ? zones.zoneOf(span) : -1;
        if (zone >= 0) {
            zone = zones.beside(zone, dx, dy);
            if (zone < 0) {
                return dx != 0;
            }
        } else if (dx != 0) {
            // Not in one zone. A freeform window starts from the zone under it; a maximized one
            // has no place of its own and goes beside the main zone, or in it.
            int under = freeform ? zones.zoneAt(frame, bounds.centerX(), bounds.centerY()) : zones.main;
            zone = zones.beside(under, dx, 0);
            zone = zone < 0 ? under : zone;
        } else {
            return false;
        }
        Rect target = new Rect();
        zones.zoneRect(frame, zone, gap, target);
        if (freeform) {
            atm.resizeTask(task.mTaskId, target, 0);
        } else {
            // A maximized window restores into the zone, the way stock restores into a half.
            ActivityRecord top = task.topRunningActivity(false);
            if (top != null) {
                task.setLastNonFullscreenBounds(target);
                atm.mActivityClientController.toggleFreeformWindowingMode(top.token);
            }
        }
        return true;
    }

    /**
     * In PhoneWindowManagerExt.interceptKeyBeforeDispatching, for the first press of a Meta
     * combination on a DeX display. Meta+Ctrl+Alt+1 to 5 picks a layout and 0 turns zones off;
     * windows tiled in a zone move to the zone of the same number, and the new zones flash.
     * Picking the layout already in use puts its lines back where they started.
     */
    public static boolean onKey(WindowManagerService wm, KeyEvent event, int displayId) {
        int digit = event.getKeyCode() - KeyEvent.KEYCODE_0;
        if (digit < 0 || digit >= OnigiriZones.NAMES.length || !event.isCtrlPressed() || !event.isAltPressed()) {
            return false;
        }
        String name = OnigiriZones.NAMES[digit];
        synchronized (wm.mGlobalLock) {
            DisplayContent display = wm.mRoot.getDisplayContent(displayId);
            if (display == null) {
                return false;
            }
            OnigiriZones from = OnigiriZones.current();
            if (from != null && from.name.equals(name)) {
                SystemProperties.set(OnigiriZones.LINES_PROP + name, "");
            } else {
                SystemProperties.set(OnigiriZones.LAYOUT_PROP, name);
            }
            OnigiriZones to = OnigiriZones.named(name);
            if (to != null) {
                TaskDisplayArea area = display.getDefaultTaskDisplayArea();
                Rect frame = new Rect();
                display.getStableRect(frame);
                int gap = area.getFreeformThickness();
                if (from != null) {
                    area.forAllRootTasks(new OnigiriZoneController(wm.mAtmService, from, to, frame, gap, null));
                }
                UiThread.getHandler().post(new Flash(wm.mContext, display.mDisplay, to, frame, gap));
            }
        }
        return true;
    }

    /**
     * First in DexDockingController.resizeOtherTaskIfNeeded, which the DeX shell calls before it
     * applies a border drag of a tiled window (OnigiriZoneGuide.onResize): moves the lines under
     * the dragged edges, saves them, and fits the other tiled windows to them. False leaves the
     * call to stock DeX: zones off, or a pair of stock docked halves.
     */
    public static boolean onResize(ActivityTaskManagerService atm, Task task, Rect bounds) {
        OnigiriZones from;
        if (task == null || task.getDexTaskDockingState() != 0 || task.getDisplayContent() == null
                || (from = OnigiriZones.current()) == null) {
            return false;
        }
        Rect frame = new Rect();
        task.getDisplayContent().getStableRect(frame);
        int gap = task.getFreeformThickness();
        OnigiriZones to = OnigiriZones.current();
        if (to.resize(frame, gap, task.getBounds(), new Rect(bounds))) {
            SystemProperties.set(OnigiriZones.LINES_PROP + to.name, to.lines());
            task.getDisplayContent().getDefaultTaskDisplayArea().forAllRootTasks(
                    new OnigiriZoneController(atm, from, to, frame, gap, task));
        }
        return true;
    }

    /** Shows the zones of a layout over a display for a moment. Runs on the UI thread. */
    private static final class Flash implements Runnable {
        private static final int SHOWN_MS = 700;
        private static final int TYPE_SECURE_SYSTEM_OVERLAY = 2015;
        private static final int SYSTEM_FLAG_SHOW_FOR_ALL_USERS = 0x10;

        private final Context mContext;
        private final Display mDisplay;
        private final OnigiriZones mZones;
        private final Rect mFrame;
        private final int mGap;
        private OnigiriZoneOverlay mView;

        Flash(Context context, Display display, OnigiriZones zones, Rect frame, int gap) {
            mContext = context;
            mDisplay = display;
            mZones = zones;
            mFrame = frame;
            mGap = gap;
        }

        @Override
        public void run() {
            if (mView != null) {
                mView.getContext().getSystemService(WindowManager.class).removeViewImmediate(mView);
                return;
            }
            Context context = mContext.createDisplayContext(mDisplay)
                    .createWindowContext(TYPE_SECURE_SYSTEM_OVERLAY, null);
            WindowManager windows = context.getSystemService(WindowManager.class);
            mView = new OnigiriZoneOverlay(context);
            mView.show(mZones, mFrame, mGap);
            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
                    TYPE_SECURE_SYSTEM_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                            | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                            | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                    PixelFormat.TRANSLUCENT);
            params.setTitle("OnigiriZones");
            params.gravity = Gravity.TOP | Gravity.LEFT;
            params.privateFlags |= SYSTEM_FLAG_SHOW_FOR_ALL_USERS;
            // The overlay draws in display pixels.
            params.setFitInsetsTypes(0);
            windows.addView(mView, params);
            UiThread.getHandler().postDelayed(this, SHOWN_MS);
        }
    }
}
