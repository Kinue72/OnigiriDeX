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
