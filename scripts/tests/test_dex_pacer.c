/* Host policy check: cc -Wall -Wextra -Werror scripts/tests/test_dex_pacer.c -o /tmp/test-dex-pacer */
#include <assert.h>
#include <string.h>
#include "../../target/b5q/patches/dex/native/pacer.c"

static int enabled = 1, pending = 1, composites;
static U64 period = 11111111;
static Byte snapshots[3][0x20];
U64 native_display_id(void *d) { return read64(d, 0); }
unsigned native_display_stack(void *d) { return read32(d, 8); }
int native_property_bool(const char *name, int fallback) { (void)name; (void)fallback; return enabled; }
void native_activate(void *sf, void *old, void *next) { (void)sf; (void)old; (void)next; }
void native_unregister(void *s, U64 removed, U64 active) { (void)s; (void)removed; (void)active; }
void native_begin_frame(void *t, void *a, void *s, void *f) {
    (void)a; (void)s; (void)f; *((Byte *)t + 0x20) = 1;
}
void *native_previous_present_fence(void *t) { return t; }
int native_is_fence_pending(void *f, int grace) { (void)f; (void)grace; return pending; }
void native_add_targeter(void *m, void *id, void **t) { (void)m; (void)id; (void)t; ++composites; }
U64 native_period(void *s) { (void)s; return period; }
void *native_get_snapshot(void *b, unsigned id) { (void)b; return id && id < 3 ? snapshots[id] : 0; }
int native_timeline(void *sf, void *flush) { (void)sf; (void)flush; return 0; }

static void put64(void *p, unsigned o, U64 value) { memcpy((Byte *)p + o, &value, sizeof(value)); }
static void put32(void *p, unsigned o, unsigned value) { memcpy((Byte *)p + o, &value, sizeof(value)); }

int main(void) {
    Byte sf[0x2000] = {0}, scheduler[0x700] = {0}, cover[0xb0] = {0}, monitor[0xb0] = {0};
    Byte tx[0x60] = {0}, states[2 * 0x3b0] = {0}, layer[0x200] = {0}, target[0x230] = {0};
    U64 cover_id = 0x40446decf32d4f84, node[3] = {0};
    void *flush = tx, *targeter = target;
    put64(sf, 0x1248, (U64)scheduler); put64(sf, 0xaa0, 5);
    put64(sf, 0x790, 1); put64(sf, 0x798, 5); put32(sf, 0x7b0, 1);
    put64(sf, 0x700, 2); put64(sf, 0x718, (U64)cover); put64(sf, 0x730, (U64)monitor);
    put64(cover, 0, cover_id); put32(cover, 0xa4, 2);
    put64(monitor, 0, 5); put32(monitor, 8, 2); put32(monitor, 0xa4, 2);
    put64(scheduler, 0x578, 1); put64(scheduler, 0x580, cover_id);
    put64(scheduler, 0x5b0, (U64)target);
    put64(tx, 0x38, (U64)states); put64(tx, 0x40, (U64)(states + 0x3b0));
    put32(snapshots[2], 0xc, 2);

    put32(states, 0x3a0, 1); /* A busy cover must keep its transaction queued before latch. */
    assert(onigiri_transaction_ready(sf, &flush) == 1);
    put32(states, 0x3a0, 2);
    assert(onigiri_transaction_ready(sf, &flush) == 0);
    put32(states, 0x3b0 + 0x3a0, 1); put64(tx, 0x40, (U64)(states + sizeof(states)));
    assert(onigiri_transaction_ready(sf, &flush) == 1); /* Mixed transactions remain atomic. */
    pending = 0; assert(onigiri_transaction_ready(sf, &flush) == 0); pending = 1;

    onigiri_follower_composite(0, &cover_id, &targeter, sf); assert(composites == 0);
    sf[0x5f8] = 1; onigiri_follower_composite(0, &cover_id, &targeter, sf);
    assert(composites == 1); sf[0x5f8] = 0;
    put64(sf, 0x618, (U64)node); put64(sf, 0x620, 1); node[2] = (U64)layer;
    put32(layer, 0x1d4, 1); onigiri_follower_composite(0, &cover_id, &targeter, sf);
    assert(composites == 2); /* Already-latched cover buffers require real release fences. */
    put32(layer, 0x1d4, 2); onigiri_follower_composite(0, &cover_id, &targeter, sf);
    assert(composites == 2);
    put32(layer, 0x1d4, 0); onigiri_follower_composite(0, &cover_id, &targeter, sf);
    assert(composites == 3); /* Unknown snapshots fail closed. */

    onigiri_follower_frame(target, 0, 0, 0, cover_id, sf); assert(target[0x20] == 0);
    onigiri_follower_frame(target, 0, 0, 0, 5, sf); assert(target[0x20] == 1);
    period = 16666667; assert(onigiri_transaction_ready(sf, &flush) == 0); period = 11111111;
    put32(monitor, 8, 0); assert(onigiri_transaction_ready(sf, &flush) == 0); put32(monitor, 8, 2);
    put32(monitor, 0xa4, 0); assert(onigiri_transaction_ready(sf, &flush) == 0); put32(monitor, 0xa4, 2);
    put32(cover, 0xa4, 0); assert(onigiri_transaction_ready(sf, &flush) == 0); put32(cover, 0xa4, 2);
    enabled = 0; assert(onigiri_transaction_ready(sf, &flush) == 0);
    return 0;
}
