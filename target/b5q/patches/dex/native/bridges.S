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
