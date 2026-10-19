#!/system/bin/sh
# Car standby: when external power goes away (car off), cut the phone down to the bare
# minimum, and put everything back as soon as power returns. Started by onigiri-standby.rc.
#
#   persist.sys.onigiri.car_standby   true|false   (Settings > Onigiri Software, off by default)
#   onigiri-standby.sh enter|leave                  run one transition by hand (testing)
#
# On battery: stop powering USB-C at once, standby after GRACE seconds, then recheck the USB-C
# link every 30 s, backing off to 2 min on a long park (each recheck keeps the phone awake
# ~11 s: sec-battery holds a 10 s wakelock per cable event); the power key rechecks at once.
# Power off below LOW_PCT % or after MAX_HOURS.
# Autoboot only starts the phone again at 5% or more, so the two never loop.

GRACE=60
MONITOR_BOOT=8
LOW_PCT=10
MAX_HOURS=96
BIG_CPUS="3 4 5 6 7"
STATE=/dev/onigiri-standby  # tmpfs: one marker per thing we changed, so leave() undoes only those

log() { /system/bin/log -t onigiri-standby "$*"; }
mark() { touch "$STATE/$1"; }
marked() { [ -e "$STATE/$1" ]; }

powered() {
    for supply in ac usb wireless pogo; do
        [ "$(cat /sys/class/power_supply/$supply/online 2>/dev/null)" = 1 ] && return 0
    done
    return 1
}

capacity() { cat /sys/class/power_supply/battery/capacity 2>/dev/null; }

# Seconds between USB-C rechecks after $1 seconds on battery: quick stops come back fast, a
# night in the car costs less.
poll_interval() {
    if [ $1 -lt 900 ]; then echo 30
    elif [ $1 -lt 7200 ]; then echo 60
    else echo 120
    fi
}

for event in /sys/class/input/event*; do
    [ "$(cat $event/device/name 2>/dev/null)" = pmic_pwrkey ] && POWER_KEY=/dev/input/${event##*/}
done

# An unpowered monitor pulls VBUS from the phone: for a while after losing power its controller
# keeps dropping off and re-attaching about once a second, and the driver turns VBUS back on at
# every attach, which keeps it going. Cut it with shell built-ins (no fork) so it is gone within
# about a millisecond: the monitor then dies and stays attached and quiet. The MAX77705
# firmware has no sink-only mode, and Samsung's host block doesn't stop VBUS in this kernel.
# Holds for $1 seconds (or until the first cut with "once"); returns 0 early once the port has
# power again.
TYPEC=/sys/class/typec/port0
OTG=/sys/class/power_supply/otg/online
hold_power_off() {
    end=$(($(date +%s) + $1))
    while [ $(date +%s) -lt $end ]; do
        i=0
        while [ $i -lt 200 ]; do
            read on < $OTG
            if [ "$on" = 1 ]; then
                echo 0 > $OTG
                [ "$2" = once ] && return 1
            fi
            i=$((i+1))
        done
        powered && return 0
    done
    return 1
}

# Samsung's host block keeps USB host and DisplayPort down. Hold it while on battery, so the
# rechecks below don't start DisplayPort on a dead monitor, and lift it only once a re-powered
# monitor has booted: DisplayPort on a booting monitor times out and the DP driver resets the
# phone. Lifting it restarts DisplayPort (DeX).
HOST_BLOCK=/sys/class/usb_notify/usb_control/disable
block_host() {
    [ "$(cat $HOST_BLOCK)" = OFF ] && echo ON_HOST_ONIGIRI > $HOST_BLOCK &&
        log "stopped powering the USB-C device"
}
unblock_host() {
    [ "$(cat $HOST_BLOCK)" = ON_HOST_ONIGIRI ] || return
    sleep $MONITOR_BOOT
    powered && echo OFF > $HOST_BLOCK
}

# With VBUS cut, a monitor that gets car power back just waits for VBUS, and nothing makes
# either side look again. Writing port_type swaps the CC terminations and both sides
# re-detect: a powered monitor then charges the phone. Alternate writes land on both roles.
# A dead monitor re-attaches as a sink and takes VBUS about a second later: one cut settles it.
recheck_usb() {
    [ -e $TYPEC-partner ] || return 1
    case "$(cat $TYPEC/port_type)" in *"[source]"*) role=sink ;; *) role=source ;; esac
    echo $role > $TYPEC/port_type &
    hold_power_off 4 once
    found=$?
    wait
    [ $found = 0 ] && log "USB-C recheck: power is back"
    return $found
}

# Software replug: hold the CC lines open for a few seconds with the lock Samsung uses for an
# overheating connector (CTRLREG3 bit 1 + forced CC error, through the MAX77705 debug opcode
# node), so a docked monitor starts over as on a real replug.
MXIM=/sys/devices/virtual/mxim/debug0/opcode
replug_usb() {
    [ -w $MXIM ] || return
    echo 1c > $MXIM && sleep 0.3
    set -- $(cat $MXIM)  # 0x1c CTRLREG3 ...
    [ "$1" = 0x1c ] || return
    echo 1d $(printf %x $(($2 | 2))) > $MXIM && sleep 0.3
    echo 0e 84 > $MXIM
    sleep 5
    echo 1d $(printf %x $(($2))) > $MXIM
}

enter() {
    mkdir -p "$STATE"
    log "power lost: entering standby at $(capacity)%"

    input keyevent SLEEP

    if [ "$(cmd connectivity airplane-mode)" = disabled ]; then
        cmd connectivity airplane-mode enable && mark airplane
    fi
    # Airplane mode keeps radios the user re-enabled in it; switch those off too.
    if cmd wifi status 2>/dev/null | grep -q "Wifi is enabled"; then
        cmd wifi set-wifi-enabled disabled && mark wifi
    fi
    if [ "$(settings get global bluetooth_on)" = 1 ]; then
        cmd bluetooth_manager disable && mark bluetooth
    fi
    if [ "$(cmd location is-location-enabled)" = true ]; then
        cmd location set-location-enabled false && mark location
    fi
    # ISensorPrivacyManager 6 = isSensorPrivacyEnabled, 9 = setSensorPrivacy (developer "Sensors off").
    if service call sensor_privacy 6 | grep -q "00000000 00000000"; then
        service call sensor_privacy 9 i32 1 >/dev/null && mark sensors
    fi
    if [ "$(settings get global low_power)" != 1 ]; then
        cmd power set-mode 1 >/dev/null && mark saver
    fi

    # Close every background app: system ones get killed, user apps stay stopped until opened.
    am kill-all
    for pkg in $(pm list packages -3 | cut -d: -f2); do
        am force-stop "$pkg"
    done
    dumpsys deviceidle force-idle deep >/dev/null && mark idle

    # Park the big cores; the three little ones handle the odd maintenance wakeup.
    for cpu in $BIG_CPUS; do
        echo 0 > /sys/devices/system/cpu/cpu$cpu/online 2>/dev/null && mark cpu$cpu
    done
    setprop sys.onigiri.standby 1
}

leave() {
    log "power back: leaving standby at $(capacity)%"
    for cpu in $BIG_CPUS; do
        marked cpu$cpu && echo 1 > /sys/devices/system/cpu/cpu$cpu/online
    done
    marked idle && dumpsys deviceidle unforce >/dev/null
    marked saver && cmd power set-mode 0 >/dev/null
    marked sensors && service call sensor_privacy 9 i32 0 >/dev/null
    marked location && cmd location set-location-enabled true
    marked airplane && cmd connectivity airplane-mode disable
    marked wifi && cmd wifi set-wifi-enabled enabled
    marked bluetooth && cmd bluetooth_manager enable
    rm -rf "$STATE"
    setprop sys.onigiri.standby 0
    input keyevent WAKEUP
}

power_off() {
    log "$1: shutting down at $(capacity)%"
    svc power shutdown
    exit 0
}

case "$1" in
    enter) enter; exit ;;
    leave) leave; exit ;;
esac

# Booted on a powered monitor (autoboot in the car), the monitor stays USB host, ignores data role
# swaps, and DeX never starts: replug it once the boot has settled.
if [ "$(getprop persist.sys.onigiri.car_standby)" = true ] && powered && [ -e $TYPEC-partner ]; then
    sleep 10
    case "$(cat $TYPEC/data_role)" in
        *"[device]"*)
            log "docked as a USB device after boot: replugging"
            replug_usb
            for i in 1 2 3 4 5 6 7 8 9 10; do
                powered && break
                sleep 1
            done
            ;;
    esac
fi

since=
in_standby=0
[ -d "$STATE" ] && in_standby=1  # restarted mid-standby
while :; do
    if [ "$(getprop persist.sys.onigiri.car_standby)" != true ]; then
        [ $in_standby = 1 ] && leave
        [ "$(cat $HOST_BLOCK)" = ON_HOST_ONIGIRI ] && echo OFF > $HOST_BLOCK
        echo onigiri-standby > /sys/power/wake_unlock 2>/dev/null
        exit 0  # onigiri-standby.rc starts it again once enabled
    elif powered; then
        [ $in_standby = 1 ] && leave
        unblock_host
        in_standby=0
        since=
    else
        if [ "$(cat $HOST_BLOCK)" = OFF ]; then
            block_host &  # DisplayPort teardown takes seconds: keep cutting VBUS meanwhile
            hold_power_off 6
            found=$?
            wait
            [ $found = 0 ] && continue
        fi
        recheck_usb && continue
        now=$(date +%s)
        [ -n "$since" ] || since=$now
        if [ $((now - since)) -ge $GRACE ]; then
            [ $in_standby = 1 ] || { enter; in_standby=1; }
            cap=$(capacity)
            [ -n "$cap" ] && [ "$cap" -lt $LOW_PCT ] && power_off "battery below $LOW_PCT%"
            [ $((now - since)) -ge $((MAX_HOURS * 3600)) ] && power_off "no power for $MAX_HOURS hours"
        fi
    fi
    # onigiri-alarm-sleep wakes the phone from suspend and holds this wakelock until here.
    if [ -z "$since" ]; then
        echo onigiri-standby > /sys/power/wake_unlock 2>/dev/null
        sleep 3  # notice power loss quickly: the monitor flickers until hold_power_off
    elif [ $in_standby = 1 ]; then
        echo onigiri-standby > /sys/power/wake_unlock 2>/dev/null
        onigiri-alarm-sleep $(poll_interval $((now - since))) $POWER_KEY
    elif [ -e $TYPEC-partner ]; then
        # Stay awake and keep VBUS off through the grace period, until the monitor is dead.
        echo onigiri-standby > /sys/power/wake_lock
        hold_power_off 10
    else
        echo onigiri-standby > /sys/power/wake_unlock 2>/dev/null
        onigiri-alarm-sleep 10
    fi
done
