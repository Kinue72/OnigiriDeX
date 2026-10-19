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
# Kept on /data so a low-battery shutdown, crash or restart can still put things back.
DATA=/data/misc/onigiri-standby
STATE=$DATA/standby  # one marker per thing standby changed; leave() undoes only those
CC_LOCK=$DATA/cc-lock  # CTRLREG3 before replug_usb set its lock bit

log() { /system/bin/log -t onigiri-standby "$*"; }
mark() { touch "$STATE/$1"; }
marked() { [ -e "$STATE/$1" ]; }
unmark() { rm -f "$STATE/$1"; }
# change NAME COMMAND...: record NAME before running COMMAND, so a run killed in between still
# restores it (every restore only returns a setting to its pre-standby value); forget NAME if
# COMMAND fails, and skip COMMAND if NAME can't be recorded.
change() {
    name=$1
    shift
    mark $name && { "$@" || unmark $name; }
}
cpu_online() { echo $2 > /sys/devices/system/cpu/cpu$1/online; }

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
    [ "$(cat $HOST_BLOCK)" = ON_HOST_ONIGIRI ] || return 1
    sleep $MONITOR_BOOT
    powered && echo OFF > $HOST_BLOCK
}

# Apps given the zones of the current layout (Settings > Onigiri Software > Zones), if any.
zone_apps() {
    case "$(getprop persist.sys.onigiri.dex_zones)" in
        map_left | map_right) zones="0 1" ;;
        columns | priority) zones="0 1 2" ;;
        grid) zones="0 1 2 3" ;;
        *) return ;;
    esac
    for zone in $zones; do
        getprop persist.sys.onigiri.dex_zone_app.$zone
    done
}

# Once the DeX desktop is up, start the zone apps; the window manager opens each in its zone.
open_zone_apps() {
    [ -n "$(zone_apps)" ] || return
    desktop=
    for i in $(seq 30); do
        powered || return
        desktop=$(dumpsys display | sed -n 's/.*DisplayInfo{"Desktop", displayId \([0-9]*\).*/\1/p' | head -n 1)
        [ -n "$desktop" ] && break
        sleep 2
    done
    [ -n "$desktop" ] || return
    sleep 3  # let the DeX desktop settle
    apps=$(echo $(zone_apps))  # again: zones or apps may have changed meanwhile
    [ -n "$apps" ] && powered || return
    for app in $apps; do
        # The package's own launcher activity (resolve-activity can answer with the chooser).
        activity=$(cmd package query-activities --brief --components -a android.intent.action.MAIN \
            -c android.intent.category.LAUNCHER $app | grep / | head -n 1)
        # As a launcher does, so an open task comes to the front instead of getting a new activity.
        [ -n "$activity" ] && am start --display $desktop -a android.intent.action.MAIN \
            -c android.intent.category.LAUNCHER -n "$activity" >/dev/null 2>&1
    done
    log "opened zone apps: $apps"
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
    wait $!  # not a zone apps run started in the background
    [ $found = 0 ] && log "USB-C recheck: power is back"
    return $found
}

# Software replug: hold the CC lines open for a few seconds with the lock Samsung uses for an
# overheating connector (CTRLREG3 bit 1 + forced CC error, through the MAX77705 debug opcode
# node), so a docked monitor starts over as on a real replug.
# The original CTRLREG3 is saved first: if we die mid-replug, the next start restores it
# instead of leaving the port locked open (no USB and no wired charging).
MXIM=/sys/devices/virtual/mxim/debug0/opcode
restore_cc() {
    [ -f $CC_LOCK ] || return 0
    for i in 1 2 3 4 5; do
        echo 1d $(cat $CC_LOCK) > $MXIM && rm -f $CC_LOCK && return 0
        sleep 1
    done
    [ -n "$cc_failed" ] || log "could not restore CTRLREG3 from $CC_LOCK, retrying"
    cc_failed=1
    return 1
}
replug_usb() {
    [ -w $MXIM ] && [ ! -f $CC_LOCK ] || return  # never overwrite a saved original
    mkdir -p -m 0700 $DATA || return
    echo 1c > $MXIM && sleep 0.3
    set -- $(cat $MXIM)  # 0x1c CTRLREG3 ...
    [ "$1" = 0x1c ] || return
    printf '%x' $(($2)) > $CC_LOCK || return
    trap 'restore_cc; exit 1' TERM INT HUP
    echo 1d $(printf %x $(($2 | 2))) > $MXIM && sleep 0.3
    echo 0e 84 > $MXIM
    sleep 5
    restore_cc
    trap - TERM INT HUP
}

enter() {
    if ! mkdir -p -m 0700 $DATA || ! mkdir -p "$STATE"; then
        log "power lost, but $STATE can't be created: staying out of standby"
        return 1
    fi
    log "power lost: entering standby at $(capacity)%"

    input keyevent SLEEP

    if [ "$(cmd connectivity airplane-mode)" = disabled ]; then
        change airplane cmd connectivity airplane-mode enable
    fi
    # Airplane mode keeps radios the user re-enabled in it; switch those off too.
    if cmd wifi status 2>/dev/null | grep -q "Wifi is enabled"; then
        change wifi cmd wifi set-wifi-enabled disabled
    fi
    if [ "$(settings get global bluetooth_on)" = 1 ]; then
        change bluetooth cmd bluetooth_manager disable
    fi
    if [ "$(cmd location is-location-enabled)" = true ]; then
        change location cmd location set-location-enabled false
    fi
    # ISensorPrivacyManager 6 = isSensorPrivacyEnabled, 9 = setSensorPrivacy (developer "Sensors off").
    if service call sensor_privacy 6 | grep -q "00000000 00000000"; then
        change sensors service call sensor_privacy 9 i32 1
    fi
    if [ "$(settings get global low_power)" != 1 ]; then
        change saver cmd power set-mode 1
    fi

    # Close every background app: system ones get killed, user apps stay stopped until opened.
    am kill-all
    for pkg in $(pm list packages -3 | cut -d: -f2); do
        am force-stop "$pkg"
    done
    change idle dumpsys deviceidle force-idle deep

    # Park the big cores; the three little ones handle the odd maintenance wakeup.
    for cpu in $BIG_CPUS; do
        change cpu$cpu cpu_online $cpu 0 2>/dev/null
    done
    setprop sys.onigiri.standby 1
}

# Each marker goes only once its restore worked; the rest are retried on the next call.
leave() {
    [ -n "$leaving" ] || log "power back: leaving standby at $(capacity)%"
    for cpu in $BIG_CPUS; do
        marked cpu$cpu && echo 1 > /sys/devices/system/cpu/cpu$cpu/online && unmark cpu$cpu
    done
    marked idle && dumpsys deviceidle unforce >/dev/null && unmark idle
    marked saver && cmd power set-mode 0 >/dev/null && unmark saver
    # `service call` exits 0 even when the call fails: check the state before trusting it.
    marked sensors && service call sensor_privacy 9 i32 0 >/dev/null &&
        service call sensor_privacy 6 | grep -q "00000000 00000000" && unmark sensors
    marked location && cmd location set-location-enabled true && unmark location
    marked airplane && cmd connectivity airplane-mode disable && unmark airplane
    marked wifi && cmd wifi set-wifi-enabled enabled && unmark wifi
    marked bluetooth && cmd bluetooth_manager enable && unmark bluetooth
    if ! rmdir "$STATE" 2>/dev/null; then
        [ -n "$leaving" ] || log "restore failed, retrying: $(ls "$STATE" | tr '\n' ' ')"
        leaving=1
        return 1
    fi
    leaving=
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

if [ -f $CC_LOCK ]; then
    log "an interrupted replug left the USB-C port locked: restoring CTRLREG3"
    restore_cc
fi

# Started on power with something on USB-C (autoboot in the car), with car standby on or zone
# apps set: a powered monitor stays USB host after the boot, ignores data role swaps and DeX
# never starts, so replug it, then open the zone apps. Once per boot (sys.* props reset on
# reboot), not when the switch is toggled or the service restarts; booting on a computer's USB
# costs one 5 s disconnect. With neither set the flag stays unset, so switching car standby on
# later in the boot still checks.
if [ "$(getprop sys.onigiri.docked_boot)" != 1 ] && powered && [ -e $TYPEC-partner ] &&
    { [ "$(getprop persist.sys.onigiri.car_standby)" = true ] || [ -n "$(zone_apps)" ]; }; then
    sleep 10
    setprop sys.onigiri.docked_boot 1  # after the wait: a run killed during it checks again
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
    open_zone_apps
fi

# A leftover $STATE (shutdown or crash in standby) is restored on power or once standby is
# switched off, or standby is entered again after GRACE on battery.
since=
in_standby=0
while :; do
    restore_cc
    if [ "$(getprop persist.sys.onigiri.car_standby)" != true ]; then
        in_standby=0  # if it is switched back on, standby starts over from GRACE
        since=
        [ "$(cat $HOST_BLOCK 2>/dev/null)" = ON_HOST_ONIGIRI ] && echo OFF > $HOST_BLOCK
        echo onigiri-standby > /sys/power/wake_unlock 2>/dev/null
        if [ -d "$STATE" ] && ! leave || [ -f $CC_LOCK ]; then
            sleep 10
            continue
        fi
        # init restarts the service when it exits; onigiri-standby.rc starts it again once enabled,
        # including when that happened while this cleanup ran.
        [ "$(getprop persist.sys.onigiri.car_standby)" = true ] && continue
        setprop ctl.stop onigiri-standby
        exit 0
    elif powered; then
        [ -d "$STATE" ] && leave
        if unblock_host; then
            open_zone_apps &  # DisplayPort (and DeX) restarts now
        fi
        in_standby=0
        since=
    else
        if [ "$(cat $HOST_BLOCK)" = OFF ]; then
            block_host &  # DisplayPort teardown takes seconds: keep cutting VBUS meanwhile
            hold_power_off 6
            found=$?
            wait $!
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
    # onigiri-alarm-sleep releases this wakelock once its alarm is armed, wakes the phone from
    # suspend and holds the wakelock again until here.
    if [ -z "$since" ]; then
        echo onigiri-standby > /sys/power/wake_unlock 2>/dev/null
        sleep 3  # notice power loss quickly: the monitor flickers until hold_power_off
    elif [ $in_standby = 1 ]; then
        onigiri-alarm-sleep $(poll_interval $((now - since))) $POWER_KEY || sleep 10
    elif [ -e $TYPEC-partner ]; then
        # Stay awake and keep VBUS off through the grace period, until the monitor is dead.
        echo onigiri-standby > /sys/power/wake_lock
        hold_power_off 10
    else
        onigiri-alarm-sleep 10 || sleep 10
    fi
done
