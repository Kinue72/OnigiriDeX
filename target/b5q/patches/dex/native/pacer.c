typedef unsigned long U64;
typedef unsigned char Byte;
_Static_assert(sizeof(void *) == 8 && sizeof(U64) == 8, "64-bit SurfaceFlinger ABI");

extern U64 native_display_id(void *display);
extern int native_property_bool(const char *name, int fallback);
extern void native_activate(void *sf, void *old_display, void *new_display);
extern void native_unregister(void *scheduler, U64 removed, U64 active);

static U64 read64(void *p, unsigned offset) { return *(U64 *)((Byte *)p + offset); }
static unsigned read32(void *p, unsigned offset) { return *(unsigned *)((Byte *)p + offset); }

/* Samsung's ftl::SmallMap has inline and heap storage in this exact firmware. */
static Byte *map_start(void *sf, unsigned offset, unsigned tag, unsigned stride, Byte **end) {
    U64 first = read64(sf, offset), last = read64(sf, offset + 8);
    if (read32(sf, tag) == 0 && first <= (tag - offset - 8) / stride) {
        Byte *start = (Byte *)sf + offset + 8;
        *end = start + first * stride;
        return start;
    }
    if (read32(sf, tag) == 1 && last >= first && (last - first) % stride == 0 &&
            last - first <= 128 * stride) {
        *end = (Byte *)last;
        return (Byte *)first;
    }
    *end = 0;
    return 0;
}

static int connection(void *sf, U64 id) {
    Byte *end;
    for (Byte *p = map_start(sf, 0x790, 0xa98, 0x100, &end); p != end; p += 0x100)
        if (read64(p, 0) == id) return (int)read32(p, 0x18);
    return -1;
}

/* hal::PowerMode::OFF is 0. */
static int on(void *display) { return read32(display, 0xa4) != 0; }

/* The Flip5's inner panel: port 131, the low byte of its physical display id. It only turns on
 * for "Mirroring high refresh rate"; every other layout keeps it off. */
static int inner(void *display) { return (native_display_id(display) & 0xff) == 0x83; }

static void *external_on(void *sf) {
    Byte *end;
    for (Byte *p = map_start(sf, 0x700, 0x780, 0x18, &end); p != end; p += 0x18) {
        void *display = (void *)read64(p, 0x10);
        if (display && on(display) && connection(sf, native_display_id(display)) == 1) return display;
    }
    return 0;
}

/* Runs as a display turns on and picks the pacesetter: the 120 Hz inner panel while it shows,
 * else the monitor with DeX high refresh on, else stock (an internal panel replacing one that is
 * off). Leaving the inner panel hands the lead back to the monitor. */
void onigiri_power_on(void *sf, void *display, void *active, int internal) {
    void *lead = 0;
    if (internal && inner(display))
        lead = display;
    else if (active && on(active) && inner(active))
        lead = 0;
    else if (native_property_bool("persist.sys.onigiri.dex_high_refresh", 0) && (lead = external_on(sf)))
        ;
    else if (internal && (!active || !on(active)))
        lead = display;
    if (lead && lead != active)
        native_activate(sf, active, lead);
}

void onigiri_unregister(void *scheduler, U64 removed, U64 active, void *sf) {
    if (removed == active) {
        Byte *end;
        void *fallback = 0, *old = 0;
        for (Byte *p = map_start(sf, 0x700, 0x780, 0x18, &end); p != end; p += 0x18) {
            void *display = (void *)read64(p, 0x10);
            if (!display) continue;
            U64 id = native_display_id(display);
            if (id == removed) old = display;
            else if (connection(sf, id) == 0 &&
                    (!fallback || read32(display, 0xa4) == 2))
                fallback = display;
        }
        if (fallback) {
            native_activate(sf, old, fallback);
            active = read64(sf, 0xaa0);
        }
    }
    native_unregister(scheduler, removed, active);
}
