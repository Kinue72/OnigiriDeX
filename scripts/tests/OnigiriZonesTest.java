package com.android.wm.shell.freeform;

import android.graphics.Rect;
import android.os.SystemProperties;
import java.util.Arrays;

/** Host test of the DeX zone layout maths; test_dex_zones.py builds and runs it. */
public final class OnigiriZonesTest {
    // A 1920x1080 DeX desktop above its taskbar, and the freeform outline thickness.
    static final Rect FRAME = new Rect(0, 0, 1920, 1020);
    static final int GAP = 4;
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
        // Zones tile the work area; the left one of a pair gives up the outline gap.
        OnigiriZones map = use("map_left");
        same("0,0,636,1020", zone(map, 0));
        same("640,0,1920,1020", zone(map, 1));
        same(null, use("off"));

        // A window counts as tiled when every edge is near a line, also across several zones.
        OnigiriZones grid = use("grid");
        same("[0, 0, 1, 1]", Arrays.toString(grid.span(FRAME, GAP, new Rect(0, 0, 956, 506))));
        same("[0, 0, 2, 1]", Arrays.toString(grid.span(FRAME, GAP, new Rect(10, 0, 1920, 500))));
        same(null, grid.span(FRAME, GAP, new Rect(100, 0, 956, 506)));
        same(1, grid.zoneOf(new int[] {1, 0, 2, 1}));
        same(-1, grid.zoneOf(new int[] {0, 0, 2, 1}));

        // Dragging the border of a tiled window moves its line, and the neighbour fits to it.
        Rect dragged = new Rect(0, 0, 800, 1020);
        OnigiriZones moved = use("map_left");
        same(true, moved.resize(FRAME, GAP, SMALLEST, zone(map, 0), dragged));
        same("0,0,800,1020", dragged);
        Rect neighbour = zone(map, 1);
        same(true, map.fit(moved, FRAME, GAP, neighbour));
        same("804,0,1920,1020", neighbour);
        same("5025/", moved.lines());

        // The moved line is what the layout loads next time; lines that don't fit it are dropped.
        SystemProperties.VALUES.put(OnigiriZones.LINES_PROP + "map_left", moved.lines());
        same("804,0,1920,1020", zone(OnigiriZones.current(), 1));
        SystemProperties.VALUES.put(OnigiriZones.LINES_PROP + "map_left", "11500/");
        same("640,0,1920,1020", zone(OnigiriZones.current(), 1));

        // A line stops where the zone beside it could no longer hold the smallest window, on
        // either side, and the dragged window stops with it.
        dragged.set(0, 0, 50, 1020);
        moved = use("map_left");
        same(true, moved.resize(FRAME, GAP, SMALLEST, zone(map, 0), dragged));
        same("0,0,331,1020", dragged);
        dragged.set(0, 0, 1900, 1020);
        moved = use("map_left");
        same(true, moved.resize(FRAME, GAP, SMALLEST, zone(map, 0), dragged));
        same(true, zone(moved, 1).width() >= SMALLEST);

        // On a desktop too small for two such zones the line stays where it is.
        Rect small = new Rect(0, 0, 600, 1020);
        Rect before = new Rect();
        moved = use("map_left");
        moved.zoneRect(small, 0, GAP, before);
        dragged.set(0, 0, 150, 1020);
        same(true, moved.resize(small, GAP, SMALLEST, before, dragged));
        same(before, dragged);

        // A corner drag moves a column and a row line: all four grid windows follow.
        dragged.set(0, 0, 1196, 404);
        moved = use("grid");
        same(true, moved.resize(FRAME, GAP, SMALLEST, zone(grid, 0), dragged));
        same("1200,408,1920,1020", zone(moved, 3));
        same("7500/4800", moved.lines());

        // A corner on the work area's edge: the inner line moves, the outer edge stays.
        dragged.set(0, 30, 800, 1020);
        moved = use("map_left");
        same(true, moved.resize(FRAME, GAP, SMALLEST, zone(map, 0), dragged));
        same("0,0,800,1020", dragged);

        // Pulling only an edge off the work area's edge, or resizing a loose window, moves nothing.
        moved = use("grid");
        same(false, moved.resize(FRAME, GAP, SMALLEST, zone(grid, 0), new Rect(40, 0, 956, 506)));
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
        window.set(0, 0, 1276, 1020);
        same(true, columns.fit(map, FRAME, GAP, window));
        same(zone(map, 0), window);
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
