.text
.global onigiri_power_bridge
.type onigiri_power_bridge, %function
onigiri_power_bridge:
    mov x0, x21
    ldr x1, [x20]
    ldur x2, [x29, #-0x10]
    mov w3, w24
    bl onigiri_power_on
    b power_continue
.size onigiri_power_bridge, .-onigiri_power_bridge

/* Replay setPowerModeInternal's vsync restore for an already-on lead. */
.global native_acquire
.type native_acquire, %function
native_acquire:
    paciasp
    stp x29, x30, [sp, #-0x40]!
    mov x29, sp
    stp x20, x19, [sp, #0x10]
    str x21, [sp, #0x20]
    mov x19, x0
    mov x20, x1
    ldr x21, [x0, #0x1248]
    add x8, sp, #0x30
    mov x0, x21
    mov w2, #1
    bl native_vsync_schedule
    ldr x8, [sp, #0x30]
    ldr w8, [x8, #0x34]
    cmp w8, #0
    mov x0, x19
    mov x1, x20
    cset w2, eq
    bl native_request_vsync
    ldr x0, [sp, #0x38]
    bl .Lrelease_shared
    mov x0, x21
    mov w1, wzr
    bl native_synthetic_vsync
    add x0, x21, #0x548
    bl native_lock
    stp xzr, xzr, [sp, #0x30]
    mov x0, x21
    mov x1, x20
    mov w2, #1
    add x3, sp, #0x30
    bl native_resync
    ldr x0, [sp, #0x38]
    bl .Lrelease_shared
    add x0, x21, #0x548
    bl native_unlock
    ldr x21, [sp, #0x20]
    ldp x20, x19, [sp, #0x10]
    ldp x29, x30, [sp], #0x40
    autiasp
    ret
.size native_acquire, .-native_acquire

.type .Lrelease_shared, %function
.Lrelease_shared:
    cbz x0, .Lrelease_done
    paciasp
    stp x29, x30, [sp, #-0x20]!
    mov x29, sp
    str x19, [sp, #0x10]
    mov x19, x0
    add x1, x0, #8
    mov x0, #-1
    bl native_fetch_add
    cbnz x0, .Lrelease_return
    ldr x8, [x19]
    mov x0, x19
    ldr x8, [x8, #0x10]
    blr x8
    mov x0, x19
    bl native_release_weak
.Lrelease_return:
    ldr x19, [sp, #0x10]
    ldp x29, x30, [sp], #0x20
    autiasp
.Lrelease_done:
    ret
.size .Lrelease_shared, .-.Lrelease_shared

.global onigiri_unregister_bridge
.type onigiri_unregister_bridge, %function
onigiri_unregister_bridge:
    mov x3, x19
    b onigiri_unregister
.size onigiri_unregister_bridge, .-onigiri_unregister_bridge

.global onigiri_frame_bridge
.type onigiri_frame_bridge, %function
onigiri_frame_bridge:
    ldr x4, [x22]
    sub x5, x19, #0x38
    b onigiri_follower_frame
.size onigiri_frame_bridge, .-onigiri_frame_bridge

.global onigiri_composite_bridge
.type onigiri_composite_bridge, %function
onigiri_composite_bridge:
    sub x3, x19, #0x38
    b onigiri_follower_composite
.size onigiri_composite_bridge, .-onigiri_composite_bridge

.global native_timeline
.type native_timeline, %function
native_timeline:
    paciasp
    sub sp, sp, #0x90
    b timeline_continue
.size native_timeline, .-native_timeline
