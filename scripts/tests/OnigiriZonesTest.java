package com.android.wm.shell.freeform;

import android.graphics.Rect;
import android.os.SystemProperties;
import java.util.Arrays;

/** Host test of the DeX zone layout maths; test_dex_zones.py builds and runs it. */
public final class OnigiriZonesTest {
    // A 1920x1080 DeX desktop above its taskbar, and the default space around zones.
    static final Rect FRAME = new Rect(0, 0, 1920, 1020);
    static final int GAP = 8;
    // The smallest window on a 240 dpi desktop: 330 pixels.
    static final int SMALLEST = OnigiriZones.minSize(240);

    static void same(Object expected, Object actual) {
        if (!String.valueOf(expected).equals(String.valueOf(actual))) {
            throw new AssertionError("expected " + expected + ", got " + actual);
        }
    }

    static Rect zone(OnigiriZones zones, int zone) {
        Rect rect = new Rect();
        zones.zoneRect(FRAME, zone, GAP, rect);
        return rect;
    }

    static OnigiriZones use(String name) {
        SystemProperties.VALUES.clear();
        SystemProperties.VALUES.put(OnigiriZones.LAYOUT_PROP, name);
        return OnigiriZones.current();
    }

    public static void main(String[] args) {
        // Zones tile the work area with the gap on every side of every window.
        OnigiriZones map = use("map_left");
        same("8,8,637,1012", zone(map, 0));
        same("645,8,1912,1012", zone(map, 1));
        same(null, use("off"));

        // The space is 8 pixels until Settings saves another; with none, zones touch.
        same(8, OnigiriZones.space());
        SystemProperties.VALUES.put(OnigiriZones.GAP_PROP, "16");
        same(16, OnigiriZones.space());
        SystemProperties.VALUES.put(OnigiriZones.GAP_PROP, "64");
        same(32, OnigiriZones.space());
        Rect touching = new Rect();
        map.zoneRect(FRAME, 0, 0, touching);
        same("0,0,640,1020", touching);

        // DeX draws an outline around the bounds of a window (8 pixels here). With the work
        // area grown by it and gap(outline), the bounds sit that far inside where a zone shows.
        SystemProperties.VALUES.remove(OnigiriZones.GAP_PROP);
        Rect bounds = new Rect();
        map.zoneRect(new Rect(-8, -8, 1928, 1028), 1, OnigiriZones.gap(8), bounds);
        same("653,16,1904,1004", bounds);

        // A window counts as tiled when every edge is near a line, also across several zones.
        OnigiriZones grid = use("grid");
        same("[0, 0, 1, 1]", Arrays.toString(grid.span(FRAME, GAP, zone(grid, 0))));
        same("[0, 0, 2, 1]", Arrays.toString(grid.span(FRAME, GAP, new Rect(18, 8, 1912, 500))));
        same(null, grid.span(FRAME, GAP, new Rect(100, 8, 956, 506)));
        same(1, grid.zoneOf(new int[] {1, 0, 2, 1}));
        same(-1, grid.zoneOf(new int[] {0, 0, 2, 1}));

        // Dragging the border of a tiled window moves its line, and the neighbour fits to it.
        Rect dragged = new Rect(8, 8, 800, 1012);
        OnigiriZones moved = use("map_left");
        same(true, moved.resize(FRAME, GAP, SMALLEST, zone(map, 0), dragged));
        same("8,8,800,1012", dragged);
        Rect neighbour = zone(map, 1);
        same(true, map.fit(moved, FRAME, GAP, neighbour));
        same("808,8,1912,1012", neighbour);
        same("5021/", moved.lines());

        // A window tiled before the space changed (here with none) lands on its lines whole.
        dragged.set(0, 0, 800, 1020);
        moved = use("map_left");
        same(true, moved.resize(FRAME, GAP, SMALLEST, new Rect(0, 0, 640, 1020), dragged));
        same("8,8,800,1012", dragged);

        // The moved line is what the layout loads next time; lines that don't fit it are dropped.
        SystemProperties.VALUES.put(OnigiriZones.LINES_PROP + "map_left", moved.lines());
        same("808,8,1912,1012", zone(OnigiriZones.current(), 1));
        SystemProperties.VALUES.put(OnigiriZones.LINES_PROP + "map_left", "11500/");
        same("645,8,1912,1012", zone(OnigiriZones.current(), 1));

        // A line stops where the zone beside it could no longer hold the smallest window, on
        // either side, and the dragged window stops with it.
        dragged.set(8, 8, 50, 1012);
        moved = use("map_left");
        same(true, moved.resize(FRAME, GAP, SMALLEST, zone(map, 0), dragged));
        same("8,8,339,1012", dragged);
        dragged.set(8, 8, 1900, 1012);
        moved = use("map_left");
        same(true, moved.resize(FRAME, GAP, SMALLEST, zone(map, 0), dragged));
        same(true, zone(moved, 1).width() >= SMALLEST);

        // On a desktop too small for two such zones the line stays where it is.
        Rect small = new Rect(0, 0, 600, 1020);
        Rect before = new Rect();
        moved = use("map_left");
        moved.zoneRect(small, 0, GAP, before);
        dragged.set(8, 8, 150, 1012);
        same(true, moved.resize(small, GAP, SMALLEST, before, dragged));
        same(before, dragged);

        // A corner drag moves a column and a row line: all four grid windows follow.
        dragged.set(8, 8, 1196, 404);
        moved = use("grid");
        same(true, moved.resize(FRAME, GAP, SMALLEST, zone(grid, 0), dragged));
        same("1204,412,1912,1012", zone(moved, 3));
        same("7506/4791", moved.lines());

        // A corner on the work area's edge: the inner line moves, the outer edge stays.
        dragged.set(8, 30, 800, 1012);
        moved = use("map_left");
        same(true, moved.resize(FRAME, GAP, SMALLEST, zone(map, 0), dragged));
        same("8,8,800,1012", dragged);

        // Pulling only an edge off the work area's edge, or resizing a loose window, moves nothing.
        moved = use("grid");
        same(false, moved.resize(FRAME, GAP, SMALLEST, zone(grid, 0), new Rect(40, 8, 956, 506)));
        same(false, moved.resize(FRAME, GAP, SMALLEST, new Rect(100, 100, 500, 500), new Rect(100, 100, 600, 500)));
        same("6000/6000", moved.lines());

        // Swapping layouts keeps windows in the zone of the same number. A window in a zone
        // the new layout lacks, or across zones, goes to the zone under its middle.
        OnigiriZones columns = use("columns");
        Rect window = zone(map, 1);
        same(true, map.fit(columns, FRAME, GAP, window));
        same(zone(columns, 1), window);
        window = zone(grid, 3);
        same(true, grid.fit(map, FRAME, GAP, window));
        same(zone(map, 1), window);
        OnigiriZones priority = use("priority");
        window.set(8, 8, 1275, 1012);
        same(true, columns.fit(priority, FRAME, GAP, window));
        same(zone(priority, 1), window);
        same(false, map.fit(columns, FRAME, GAP, new Rect(100, 100, 500, 500)));

        // Meta+arrow: the zone across an edge, or none at the work area's edge.
        same(1, grid.beside(0, 1, 0));
        same(2, grid.beside(0, 0, 1));
        same(-1, grid.beside(0, -1, 0));
        same(-1, columns.beside(1, 0, -1));
        same(2, columns.beside(1, 1, 0));

        // Shift-drag: the zone under the pointer, joined with its neighbours near a border.
        same("[1, 0, 2, 1]", Arrays.toString(columns.spanAt(FRAME, 960, 500, 40)));
        same("[0, 0, 2, 1]", Arrays.toString(columns.spanAt(FRAME, 650, 500, 40)));
        same("[0, 0, 2, 2]", Arrays.toString(grid.spanAt(FRAME, 950, 500, 40)));
    }
}
