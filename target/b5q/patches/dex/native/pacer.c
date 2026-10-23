typedef unsigned long U64;
typedef unsigned char Byte;
_Static_assert(sizeof(void *) == 8 && sizeof(U64) == 8, "64-bit SurfaceFlinger ABI");

extern U64 native_display_id(void *display);
extern int native_property_bool(const char *name, int fallback);
extern void native_activate(void *sf, void *old_display, void *new_display);
extern void native_unregister(void *scheduler, U64 removed, U64 active);
extern void native_begin_frame(void *targeter, void *args, void *source, void *pending);
extern void *native_previous_present_fence(void *targeter);
extern int native_is_fence_pending(void *fence, int grace_ms);
extern void native_add_targeter(void *targeters, void *id, void **targeter);
extern U64 native_period(void *scheduler);
extern unsigned native_display_stack(void *display);
extern void *native_get_snapshot(void *builder, unsigned sequence);
extern int native_timeline(void *sf, void *flush);

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

static void *cover_on(void *sf) {
    Byte *end;
    for (Byte *p = map_start(sf, 0x700, 0x780, 0x18, &end); p != end; p += 0x18) {
        void *display = (void *)read64(p, 0x10);
        if (display && (native_display_id(display) & 0xff) == 0x84 &&
                read32(display, 0xa4) == 2) return display;
    }
    return 0;
}

/* Only a faster, separate desktop gets this policy; a mirrored cover still needs every buffer. */
static int fast_desktop(void *sf) {
    if (!native_property_bool("persist.sys.onigiri.dex_high_refresh", 0)) return 0;
    U64 active = read64(sf, 0xaa0);
    if (connection(sf, active) != 1) return 0;
    void *cover = cover_on(sf), *monitor = external_on(sf);
    if (!cover || !monitor || native_display_id(monitor) != active) return 0;
    unsigned cover_stack = native_display_stack(cover), desktop_stack = native_display_stack(monitor);
    if (cover_stack == ~0u || desktop_stack == ~0u || cover_stack == desktop_stack) return 0;
    U64 period = native_period((void *)read64(sf, 0x1248));
    return period > 0 && period < 16000000;
}

static void *cover_targeter(void *sf) {
    void *scheduler = (void *)read64(sf, 0x1248);
    Byte *end;
    for (Byte *p = map_start(scheduler, 0x578, 0x640, 0x40, &end); p != end; p += 0x40)
        if ((read64(p, 0) & 0xff) == 0x84) return (void *)read64(p, 0x30);
    return 0;
}

static int cover_pending(void *targeter) {
    return targeter && native_is_fence_pending(native_previous_present_fence(targeter), 0);
}

static void *snapshot(void *sf, unsigned sequence) {
    return native_get_snapshot((Byte *)sf + 0x15e0, sequence);
}

/* The lifecycle manager's snapshots own the effective stack; legacy Layer state stays at zero. */
static int cover_changed(void *sf, unsigned head, unsigned size) {
    U64 node = read64(sf, head), remaining = read64(sf, size);
    if (remaining > 4096) return 1;
    while (node && remaining) {
        void *layer = (void *)read64((void *)node, 0x10);
        if (!layer) return 1;
        void *state = snapshot(sf, read32(layer, 0x1d4));
        if (!state || read32(state, 0xc) == 0 || read32(state, 0xc) == ~0u) return 1;
        node = read64((void *)node, 0);
        --remaining;
    }
    return node != 0 || remaining != 0;
}

void onigiri_follower_frame(void *targeter, void *args, void *source, void *pending,
                            U64 id, void *sf) {
    native_begin_frame(targeter, args, source, pending);
    if ((id & 0xff) == 0x84 && fast_desktop(sf))
        *((Byte *)targeter + 0x20) = 0;
}

void onigiri_follower_composite(void *targeters, void *id, void **targeter, void *sf) {
    if ((read64(id, 0) & 0xff) == 0x84 && fast_desktop(sf) &&
            !*((Byte *)sf + 0x5f8) && !*((Byte *)sf + 0x417) &&
            !*((Byte *)sf + 0x568) && !*((Byte *)sf + 0x600) &&
            !cover_changed(sf, 0x618, 0x620) && !cover_changed(sf, 0x640, 0x648) &&
            cover_pending(*targeter)) return;
    native_add_targeter(targeters, id, targeter);
}

/* Hold the whole transaction before latch, so skipped cover frames never release a scanned buffer.
 * Geometry or already-latched cover changes still force normal composition above. */
int onigiri_transaction_ready(void *sf, void *flush) {
    if (fast_desktop(sf) && cover_pending(cover_targeter(sf))) {
        void *transaction = (void *)read64(flush, 0);
        U64 first = read64(transaction, 0x38), last = read64(transaction, 0x40);
        if (last >= first && (last - first) % 0x3b0 == 0 && last - first <= 4096 * 0x3b0) {
            for (Byte *p = (Byte *)first; p != (Byte *)last; p += 0x3b0) {
                void *state = snapshot(sf, read32(p, 0x3a0));
                if (state && read32(state, 0xc) == 0) return 1; /* TransactionReadiness::NotReady */
            }
        }
    }
    return native_timeline(sf, flush);
}
