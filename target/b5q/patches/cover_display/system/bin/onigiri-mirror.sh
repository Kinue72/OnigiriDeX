#!/system/bin/sh
# Mirroring fit, like the SecondScreen app: while a wired monitor mirrors the phone (DeX off),
# give the cover the monitor's shape at 240 dpi, so the mirror fills the monitor instead of a
# square in the middle. The cover goes back to its own size and density as soon as the monitor
# goes away or DeX starts. Each time DeX starts, it also opens the zone apps (Settings > Onigiri
# Software > Zones). Started by onigiri-mirror.rc.

DP=/sys/class/drm/card0-DP-1/status
DPI=240
MAX_WIDTH=2560  # a wider monitor gets the same shape, rendered smaller and scaled up
STEADY=5        # polls (2 s apart) mirroring must hold before resizing
DATA=/data/misc/onigiri-mirror
# The cover's size and density from before; present while ours apply, so a restart or reboot
# in between still puts them back.
SAVED=$DATA/saved

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
while :; do
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
