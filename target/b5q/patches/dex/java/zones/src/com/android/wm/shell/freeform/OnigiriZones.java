package com.android.wm.shell.freeform;

import android.graphics.Rect;
import android.os.SystemProperties;

/**
 * A DeX zone layout: column and row lines across the work area, and zones that each span the
 * cells between some of them. The layout picked in Settings is in persist.sys.onigiri.dex_zones;
 * dragging the border of a tiled window moves a line, kept per layout in
 * persist.sys.onigiri.dex_zone_lines.<layout>.
 *
 * SystemUI (the drag guide) and system_server (launches, shortcuts, tiled neighbours) each carry
 * a copy of this class: build.sh builds it a second time as com.android.server.wm.
 */
final class OnigiriZones {
    static final String LAYOUT_PROP = "persist.sys.onigiri.dex_zones";
    static final String LINES_PROP = "persist.sys.onigiri.dex_zone_lines.";
    /** In shortcut order: Meta+Ctrl+Alt+1 picks NAMES[1]. */
    static final String[] NAMES = {"off", "map_left", "map_right", "columns", "grid", "priority"};
    /** Lines are positions out of UNIT across the work area. */
    static final int UNIT = 12000;
    /** Lines stay at least this far apart, so no zone can be dragged shut. */
    static final int MIN = 1500;
    /** A window edge this many pixels from a line still sits on it. */
    static final int NEAR = 32;

    final String name;
    /** The zone new windows open in. */
    final int main;
    /** Line positions, from 0 to UNIT. */
    final int[] cols;
    final int[] rows;
    /** Left column line, top row line, right column line, bottom row line of every zone. */
    final int[] cells;

    private OnigiriZones(String name, int main, int[] cols, int[] rows, int[] cells) {
        this.name = name;
        this.main = main;
        this.cols = cols;
        this.rows = rows;
        this.cells = cells;
    }

    /** The layout in use with the user's line positions, or null when zones are off. */
    static OnigiriZones current() {
        return named(SystemProperties.get(LAYOUT_PROP, "off"));
    }

    static OnigiriZones named(String name) {
        OnigiriZones zones = template(name);
        if (zones != null) {
            zones.load(SystemProperties.get(LINES_PROP + name, ""));
        }
        return zones;
    }

    /** Zone order is what Settings numbers its zone apps by. */
    static OnigiriZones template(String name) {
        int[] one = {0, UNIT};
        int[] two = {0, 0, 1, 1, 1, 0, 2, 1};
        int[] three = {0, 0, 1, 1, 1, 0, 2, 1, 2, 0, 3, 1};
        switch (name) {
            case "map_left":
                return new OnigiriZones(name, 1, new int[] {0, 4000, UNIT}, one, two);
            case "map_right":
                return new OnigiriZones(name, 0, new int[] {0, 8000, UNIT}, one, two);
            case "columns":
                return new OnigiriZones(name, 1, new int[] {0, 4000, 8000, UNIT}, one, three);
            case "grid":
                return new OnigiriZones(name, 0, new int[] {0, 6000, UNIT}, new int[] {0, 6000, UNIT},
                        new int[] {0, 0, 1, 1, 1, 0, 2, 1, 0, 1, 1, 2, 1, 1, 2, 2});
            case "priority":
                return new OnigiriZones(name, 1, new int[] {0, 3000, 9000, UNIT}, one, three);
            default:
                return null;
        }
    }

    /** The lines between the outer edges, as saved: columns, a slash, rows. */
    String lines() {
        StringBuilder saved = new StringBuilder();
        for (int i = 1; i < cols.length - 1; i++) {
            saved.append(i > 1 ? "," : "").append(cols[i]);
        }
        saved.append('/');
        for (int i = 1; i < rows.length - 1; i++) {
            saved.append(i > 1 ? "," : "").append(rows[i]);
        }
        return saved.toString();
    }

    /** Takes saved lines if they fit this layout; anything else leaves the default. */
    private void load(String saved) {
        String[] axes = saved.split("/", -1);
        if (axes.length != 2) {
            return;
        }
        int[] newCols = parse(cols, axes[0]);
        int[] newRows = parse(rows, axes[1]);
        if (newCols != null && newRows != null) {
            System.arraycopy(newCols, 0, cols, 0, cols.length);
            System.arraycopy(newRows, 0, rows, 0, rows.length);
        }
    }

    private static int[] parse(int[] lines, String saved) {
        String[] values = saved.isEmpty() ? new String[0] : saved.split(",", -1);
        if (values.length != lines.length - 2) {
            return null;
        }
        int[] parsed = lines.clone();
        try {
            for (int i = 0; i < values.length; i++) {
                parsed[i + 1] = Integer.parseInt(values[i]);
            }
        } catch (NumberFormatException e) {
            return null;
        }
        for (int i = 1; i < parsed.length; i++) {
            if (parsed[i] - parsed[i - 1] < MIN) {
                return null;
            }
        }
        return parsed;
    }

    int count() {
        return cells.length / 4;
    }

    private static int px(int start, int size, int line) {
        return start + (int) (((long) line * size + UNIT / 2) / UNIT);
    }

    private static int line(int start, int size, int px) {
        return (int) (((long) (px - start) * UNIT + size / 2) / size);
    }

    /**
     * Pixels of the cells from column line c0 and row line r0 to c1 and r1. Right and bottom
     * edges on an inner line give up gap like stock DeX halves do: the freeform outline
     * thickness, so the outlines of neighbours don't overlap.
     */
    void rect(Rect frame, int c0, int r0, int c1, int r1, int gap, Rect out) {
        out.left = px(frame.left, frame.width(), cols[c0]);
        out.top = px(frame.top, frame.height(), rows[r0]);
        out.right = px(frame.left, frame.width(), cols[c1]) - (c1 < cols.length - 1 ? gap : 0);
        out.bottom = px(frame.top, frame.height(), rows[r1]) - (r1 < rows.length - 1 ? gap : 0);
    }

    void zoneRect(Rect frame, int zone, int gap, Rect out) {
        int i = zone * 4;
        rect(frame, cells[i], cells[i + 1], cells[i + 2], cells[i + 3], gap, out);
    }

    /** The lines a window is tiled between (c0, r0, c1, r1), or null when an edge is on none. */
    int[] span(Rect frame, int gap, Rect bounds) {
        int c0 = near(cols, frame.left, frame.width(), bounds.left, 0);
        int r0 = near(rows, frame.top, frame.height(), bounds.top, 0);
        int c1 = near(cols, frame.left, frame.width(), bounds.right, gap);
        int r1 = near(rows, frame.top, frame.height(), bounds.bottom, gap);
        return c0 < 0 || r0 < 0 || c1 <= c0 || r1 <= r0 ? null : new int[] {c0, r0, c1, r1};
    }

    private static int near(int[] lines, int start, int size, int px, int gap) {
        for (int i = 0; i < lines.length; i++) {
            int edge = px(start, size, lines[i]) - (i < lines.length - 1 ? gap : 0);
            if (Math.abs(edge - px) <= NEAR) {
                return i;
            }
        }
        return -1;
    }

    /** The zone that fills exactly this span, or -1. */
    int zoneOf(int[] span) {
        for (int i = 0; i < cells.length; i += 4) {
            if (cells[i] == span[0] && cells[i + 1] == span[1] && cells[i + 2] == span[2]
                    && cells[i + 3] == span[3]) {
                return i / 4;
            }
        }
        return -1;
    }

    /** The zone nearest to a point; the first one wins ties. */
    int zoneAt(Rect frame, int x, int y) {
        Rect zone = new Rect();
        int best = 0;
        int bestDistance = Integer.MAX_VALUE;
        for (int i = 0; i < count(); i++) {
            zoneRect(frame, i, 0, zone);
            int distance = Math.max(0, Math.max(zone.left - x, x - (zone.right - 1)))
                    + Math.max(0, Math.max(zone.top - y, y - (zone.bottom - 1)));
            if (distance < bestDistance) {
                bestDistance = distance;
                best = i;
            }
        }
        return best;
    }

    /** The span to drop a window in at a point: its zone, joined with any zone within reach. */
    int[] spanAt(Rect frame, int x, int y, int reach) {
        int[] span = {cols.length, rows.length, 0, 0};
        int[] probes = {0, 0, -reach, 0, reach, 0, 0, -reach, 0, reach};
        for (int i = 0; i < probes.length; i += 2) {
            int zone = zoneAt(frame, x + probes[i], y + probes[i + 1]) * 4;
            span[0] = Math.min(span[0], cells[zone]);
            span[1] = Math.min(span[1], cells[zone + 1]);
            span[2] = Math.max(span[2], cells[zone + 2]);
            span[3] = Math.max(span[3], cells[zone + 3]);
        }
        return span;
    }

    /**
     * The zone across an edge of zone from, in the direction dx, dy (one is -1 or 1, the other
     * 0). The one sharing most of that edge wins; -1 when the edge is the work area's.
     */
    int beside(int from, int dx, int dy) {
        int f = from * 4;
        int best = -1;
        int bestShared = 0;
        for (int i = 0; i < cells.length; i += 4) {
            boolean touches = dx < 0 ? cells[i + 2] == cells[f] : dx > 0 ? cells[i] == cells[f + 2]
                    : dy < 0 ? cells[i + 3] == cells[f + 1] : cells[i + 1] == cells[f + 3];
            int[] lines = dx != 0 ? rows : cols;
            int axis = dx != 0 ? 1 : 0;
            int shared = Math.min(lines[cells[i + axis + 2]], lines[cells[f + axis + 2]])
                    - Math.max(lines[cells[i + axis]], lines[cells[f + axis]]);
            if (touches && shared > bestShared) {
                bestShared = shared;
                best = i / 4;
            }
        }
        return best;
    }

    /**
     * A window went from one size to another by a border or corner drag. If it was tiled and
     * its dragged edges sat on inner lines, those lines follow (never closer than MIN to the
     * next) and to is moved onto them. False, with nothing changed, for a window that was not
     * tiled or pulled an edge off the work area's edge.
     */
    boolean resize(Rect frame, int gap, Rect from, Rect to) {
        int[] span = span(frame, gap, from);
        boolean left = to.left != from.left;
        boolean top = to.top != from.top;
        boolean right = to.right != from.right;
        boolean bottom = to.bottom != from.bottom;
        if (span == null || !(left || top || right || bottom)
                || left && span[0] == 0 || top && span[1] == 0
                || right && span[2] == cols.length - 1 || bottom && span[3] == rows.length - 1) {
            return false;
        }
        if (left) {
            to.left = move(cols, span[0], frame.left, frame.width(), to.left, 0);
        }
        if (top) {
            to.top = move(rows, span[1], frame.top, frame.height(), to.top, 0);
        }
        if (right) {
            to.right = move(cols, span[2], frame.left, frame.width(), to.right, gap);
        }
        if (bottom) {
            to.bottom = move(rows, span[3], frame.top, frame.height(), to.bottom, gap);
        }
        return true;
    }

    /** Moves an inner line to put its edge at px, and returns where the edge ended up. */
    private static int move(int[] lines, int i, int start, int size, int px, int gap) {
        lines[i] = Math.max(lines[i - 1] + MIN,
                Math.min(lines[i + 1] - MIN, line(start, size, px + gap)));
        return px(start, size, lines[i]) - gap;
    }

    /**
     * Where a window tiled in this layout belongs in another: between the same lines when it
     * is this layout with moved lines, in the zone of the same number otherwise. Moves bounds
     * there and returns true, or false when the window is not tiled, spans zones the other
     * layout doesn't have, or is already in place.
     */
    boolean fit(OnigiriZones other, Rect frame, int gap, Rect bounds) {
        int[] span = span(frame, gap, bounds);
        if (span == null) {
            return false;
        }
        Rect fitted = new Rect();
        if (other.name.equals(name)) {
            other.rect(frame, span[0], span[1], span[2], span[3], gap, fitted);
        } else {
            int zone = zoneOf(span);
            if (zone < 0 || zone >= other.count()) {
                return false;
            }
            other.zoneRect(frame, zone, gap, fitted);
        }
        if (fitted.equals(bounds)) {
            return false;
        }
        bounds.set(fitted);
        return true;
    }
}
