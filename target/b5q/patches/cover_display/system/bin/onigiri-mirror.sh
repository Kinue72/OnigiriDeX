#!/system/bin/sh
# Mirroring fit, like the SecondScreen app: while a wired monitor mirrors the phone (DeX off),
# give the cover the monitor's shape at 240 dpi, so the mirror fills the monitor instead of a
# square in the middle. The cover goes back to its own size and density as soon as the monitor
# goes away or DeX starts. With "Mirroring high refresh rate" on, opening the phone while it
# mirrors shows the 120 Hz inner panel instead (device state 5), fitted the same way, so the
# mirror is no longer held to the cover's 60 Hz. Each time DeX starts, it also opens the zone apps (Settings > Onigiri
# Software > Zones). It also keeps power saving, which holds every screen to 60 Hz, off while
# the phone charges. Started by onigiri-mirror.rc.

DP=/sys/class/drm/card0-DP-1/status
DPI=240
MAX_WIDTH=2560  # a wider monitor gets the same shape, rendered smaller and scaled up
STEADY=5        # polls (2 s apart) mirroring must hold before resizing
INNER=5         # device state that shows the inner panel while LAYOUT is set (DeviceStateToLayoutMap)
LAYOUT=sys.onigiri.inner_layout  # set before requesting INNER, cleared once the cover is back
DATA=/data/misc/onigiri-mirror
# The cover's size and density from before; present while ours apply, so a restart or reboot
# in between still puts them back.
SAVED=$DATA/saved
# The cover's own size and density while the inner panel shows: switching panels leaves a stray
# size override on the cover (840x808, 1080x2244 seen), so they are put back afterwards.
OWN=$DATA/own
# min_refresh_rate from before the inner panel showed ("null" if unset; Force peak refresh rate
# sets it). Held at 120 meanwhile: the adaptive policy otherwise idles the panel at 60.
MIN_RATE=$DATA/min-refresh-rate
# Power saving was on when charging started; it goes back on once charging stops.
SAVER=$DATA/power-saving
UNPLUGGED=3  # polls without charging before that: USB mode changes drop the charger for ~1 s

log() { /system/bin/log -t onigiri-mirror "$*"; }

# WxH to give the cover, "dex ID" while DeX owns the monitor (ID: the desktop's display), "hold"
# while the monitor sleeps (the screen is off in either mode), or nothing without a monitor.
mirror_size() {
    read status 2>/dev/null < $DP
    [ "$status" = connected ] || return
    # `cmd display get-displays` leaves out the DeX desktop. It stays listed here after DeX
    # exits, but off. Only the system's own one: an app can name a display "Desktop" too.
    displays=$(dumpsys display | grep 'DisplayInfo{') || return
    desktop=$(echo "$displays" | grep -F 'uniqueId "virtual:android,1000,Desktop,' |
        sed -n 's/.*DisplayInfo{"Desktop", displayId \([0-9]*\),.*, state ON,.*/\1/p' | head -n 1)
    [ -n "$desktop" ] && { echo dex $desktop; return; }
    external=$(echo "$displays" | grep -m 1 'type EXTERNAL')
    [ -n "$external" ] || return
    case $external in *', state ON,'*) ;; *) echo hold; return ;; esac
    set -- $(echo "$external" | sed -n 's/.*real \([0-9]*\) x \([0-9]*\),.*/\1 \2/p')
    [ -n "$2" ] || return
    if [ $1 -gt $MAX_WIDTH ]; then
        echo ${MAX_WIDTH}x$(($2 * MAX_WIDTH / $1))
    else
        echo ${1}x$2
    fi
}

# The cover's current "size" or "density": its override (with "override"), else the physical
# value. Never restore with `wm size reset`: Samsung's reset forces a resolution of its own
# (840x808 on the cover), while setting the physical value clears the override.
current() {
    value=$(wm $1 -d 0)
    [ "$2" = override ] && echo "$value" | sed -n "s/^Override $1: //p" | grep . ||
        echo "$value" | sed -n "s/^Physical $1: //p"
}

# Whether "$1" is a "WxH DENSITY" pair worth handing to wm.
valid() {
    echo "$1" | grep -qxE '[1-9][0-9]*x[1-9][0-9]* [1-9][0-9]*'
}

# Give the cover the monitor's shape $1. The cover's own values are saved first (through a temp
# file, so a crash never leaves a half-written one), and not resized unless they could be.
fit() {
    if [ ! -e $SAVED ]; then
        own="$(current size override) $(current density override)"
        valid "$own" && echo "$own" > $SAVED.tmp && mv $SAVED.tmp $SAVED || return 1
    fi
    wm size $1 -d 0 && wm density $DPI -d 0
}

# Put the saved values back, or the physical ones if the saved file is unusable. The file is
# kept until both are set, so a failure is retried.
restore() {
    [ -e $SAVED ] || return 0
    read own < $SAVED
    valid "$own" || own="$(current size) $(current density)"
    valid "$own" || return 1
    set -- $own
    wm size $1 -d 0 && wm density $2 -d 0 && rm -f $SAVED
}

# The committed device state.
state() {
    cmd device_state print-state 2>/dev/null
}

# Whether the inner panel should show the mirror: the switch is on and the hinge is half or fully
# open (base states 2 and 3).
inner_wanted() {
    [ "$(getprop persist.sys.onigiri.mirror_high_refresh)" = true ] || return 1
    case $(dumpsys device_state | sed -n 's/.*mBaseState=.*identifier=\([0-9]*\).*/\1/p' |
        head -n 1) in
        2 | 3) return 0 ;;
    esac
    return 1
}

charging() {
    for supply in ac usb wireless pogo; do
        read online 2>/dev/null < /sys/class/power_supply/$supply/online && [ "$online" = 1 ] &&
            return 0
    done
    return 1
}

# Power saving off while charging, back on afterwards if it was on. Car standby turns it on by
# itself when the car goes off, after this has already put it back.
power_saving() {
    if charging; then
        unplugged=0
        [ "$(settings get global low_power)" = 1 ] || return 0
        touch $SAVER && { settings put global low_power 0 || rm -f $SAVER; } &&
            log "power saving off while charging"
    elif [ -e $SAVER ]; then
        unplugged=$((unplugged + 1))
        [ $unplugged -ge $UNPLUGGED ] || return 0
        settings put global low_power 1 && rm -f $SAVER && log "power saving back on"
    fi
}

# Apps given the zones of the current layout, if any.
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

# Start the zone apps on the DeX desktop $1; the window manager opens each in its zone.
open_zone_apps() {
    apps=$(echo $(zone_apps))
    [ -n "$apps" ] || return
    for app in $apps; do
        # The package's own launcher activity (resolve-activity can answer with the chooser).
        activity=$(cmd package query-activities --brief --components -a android.intent.action.MAIN \
            -c android.intent.category.LAUNCHER $app | grep / | head -n 1)
        # As a launcher does, so an open task comes to the front instead of getting a new activity.
        [ -n "$activity" ] && am start --display $1 -a android.intent.action.MAIN \
            -c android.intent.category.LAUNCHER -n "$activity" >/dev/null 2>&1
    done
    log "opened zone apps: $apps"
}

mkdir -p $DATA
applied=
[ -e $SAVED ] && applied=unknown  # left applied by an earlier run: recheck at once
seen=
count=0
had_dex=  # DeX ran on this monitor
inner=    # state 5 requested; left from before a restart if it is still the committed state
unplugged=0
[ "$(state)" = $INNER ] && inner=1
while :; do
    power_saving
    now=$(mirror_size)
    [ "$now" = hold ] && { sleep 2; continue; }
    if [ "$now" = "$seen" ]; then
        count=$((count + 1))
    else
        seen=$now
        count=0
    fi
    case $now in
        dex*)
            had_dex=1
            # On the second poll, once the desktop has settled: once per DeX start. In the
            # background, so a slow launch never holds up the cover.
            [ $count = 1 ] && { open_zone_apps ${now#dex } & }
            now=
            ;;
        '') had_dex= ;;
    esac
    # Plugging in a monitor often starts DeX a few seconds later: wait for mirroring to hold, so
    # docking doesn't relayout the cover twice. Turning DeX off is the user's choice, and putting
    # the cover back never waits.
    want=$applied
    if [ -z "$now" ]; then
        want=
    elif [ -n "$had_dex" ] || [ $count -ge $STEADY ]; then
        want=$now
    fi
    # The inner panel takes over display 0, and with it display 0's size and density overrides:
    # the cover's own values are saved (kept if already saved: display 0 may hold a fit by now),
    # display 0 goes to physical ones before the switch, and the inner panel gets the fit once it
    # shows (again whenever the switch's leftovers replace it). Entering waits like a fit does;
    # staying only needs mirroring. Folding cancels state 5 by itself; resetting then is harmless.
    if [ -n "$now" ] && { [ -n "$inner" ] || [ -n "$want" ]; } && inner_wanted; then
        if [ -z "$inner" ] || [ "$(state)" != $INNER ]; then
            restore && applied= && {
                [ -e $OWN ] || {
                    own="$(current size override) $(current density override)"
                    valid "$own" && echo "$own" > $OWN
                }
            } && wm size $(current size) -d 0 && wm density $(current density) -d 0 &&
                { [ -e $MIN_RATE ] || settings get system min_refresh_rate > $MIN_RATE; } &&
                settings put system min_refresh_rate 120 && setprop $LAYOUT 1 &&
                cmd device_state state $INNER >/dev/null 2>&1 && inner=1 &&
                log "inner screen shows the mirror"
        elif [ "$(current size override)" != "$now" ]; then
            wm size $now -d 0 && wm density $DPI -d 0 && log "inner screen fit to the monitor: $now"
        fi
        sleep 2
        continue
    elif [ -n "$inner" ]; then
        cmd device_state state reset >/dev/null 2>&1
        inner=
        log "cover shows the mirror again"
        sleep 2
        continue
    elif { [ -e $OWN ] || [ -e $MIN_RATE ] || [ -n "$(getprop $LAYOUT)" ]; } &&
            [ "$(state)" != $INNER ]; then
        setprop $LAYOUT ""
        if [ -e $OWN ]; then
            read own < $OWN
            set -- $own
            wm size $1 -d 0 && wm density $2 -d 0 && rm -f $OWN
        fi
        if [ -e $MIN_RATE ]; then
            read rate < $MIN_RATE
            if [ "$rate" = null ]; then
                settings delete system min_refresh_rate >/dev/null
            else
                settings put system min_refresh_rate $rate
            fi && rm -f $MIN_RATE
        fi
    fi
    # Only a change that went through counts as applied: a failed one is retried next poll. A
    # saved file means the cover may be off its own size (even after a half-done fit), so it is
    # put back whenever no fit is wanted.
    if [ -n "$want" ]; then
        [ "$want" != "$applied" ] && fit $want && applied=$want && log "cover fit to the monitor: $want"
    elif [ -e $SAVED ]; then
        restore && applied= && log "cover restored"
    fi
    sleep 2
done
