#!/system/bin/sh
# Adapted from magisk-autoboot by Anas Fanani for Samsung's native charger mode.
# Copyright (c) 2012-2023 Anas Fanani and the author.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Charger mode has no logcat; /dev/kmsg ends up in /proc/last_kmsg after the next boot.
log() { echo "onigiri-autoboot: $*" > /dev/kmsg; }

marker=$(cat /cache/onigiri/autoboot 2>&1)
ps=/sys/class/power_supply
misc=/dev/block/by-name/misc
clear_cookie() { dd if=/dev/zero of=$misc bs=32 count=1 conv=notrunc,fsync 2>/dev/null; }

# Normal boot (started by onigiri-autoboot.rc): keep Qualcomm's factory-mode cookie at the start
# of misc. Samsung's abl then skips the unlocked-bootloader warning, which otherwise waits for
# every key to be released, so the phone boots about 9 s sooner and also with the power key held
# (a power-on board in a battery-less build). "qmmi" boots full Android: Samsung's init has no
# factory mode, so only ro.bootmode changes. The field is also the recovery command, which
# recovery clears; the next boot writes it again.
if [ "$(getprop ro.bootmode)" != charger ]; then
    command=$(dd if=$misc bs=32 count=1 2>/dev/null | tr -d '\0')
    if grep -qE 'sec_qc_user_reset\.boot_mode="?charger' /proc/cmdline; then
        # Plugged in while off: the cookie turned charger mode into this boot, but abl still set
        # the kernel up for charging (lpcharge=1: USB PD, DisplayPort, battery). With autoboot,
        # restart clean. Without it, or under 5% (see below), drop the cookie and shut down:
        # Samsung powers back on into charger mode while a cable is in.
        capacity=$(cat $ps/battery/capacity 2>/dev/null)
        if [ "$marker" = true ] && { [ -z "$capacity" ] || [ "$capacity" -ge 5 ]; }; then
            log "charger boot at ${capacity:-?}%, rebooting"
            setprop sys.powerctl reboot
        else
            log "charger boot at ${capacity:-?}%, autoboot=$marker, back to charger mode"
            clear_cookie
            setprop sys.powerctl shutdown
        fi
    elif [ -z "$command" ]; then
        # Never overwrite a pending recovery command.
        log "writing the qmmi cookie"
        printf qmmi | dd of=$misc bs=32 count=1 conv=sync,notrunc,fsync 2>/dev/null
    fi
    exit 0
fi

log "started, autoboot=$marker"
[ "$marker" = true ] || exit 0
log "ac=$(cat $ps/ac/online) usb=$(cat $ps/usb/online) wireless=$(cat $ps/wireless/online) battery=$(cat $ps/battery/capacity)%"

while :; do
    for supply in ac usb wireless; do
        if [ "$(cat /sys/class/power_supply/$supply/online 2>/dev/null)" = 1 ]; then
            # Charge to 5% first: below that, booting on a weak supply ends in a low-battery
            # shutdown loop. Car standby powers off under 10%, so the thresholds never meet.
            capacity=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)
            if [ -z "$capacity" ] || [ "$capacity" -ge 5 ]; then
                log "$supply power at ${capacity:-?}%, rebooting"
                setprop sys.powerctl reboot
                exit $?
            fi
        fi
    done
    sleep 10
done
