#!/system/bin/sh
# Mirroring fit, like the SecondScreen app: while a wired monitor mirrors the phone (DeX off),
# give the cover the monitor's shape at 240 dpi, so the mirror fills the monitor instead of a
# square in the middle. The cover goes back to its own size and density as soon as the monitor
# goes away or DeX starts. Started by onigiri-mirror.rc.

DP=/sys/class/drm/card0-DP-1/status
DPI=240
MAX_WIDTH=2560  # a wider monitor gets the same shape, rendered smaller and scaled up
STEADY=5        # polls (2 s apart) mirroring must hold before resizing
DATA=/data/misc/onigiri-mirror
# The cover's size and density from before; present while ours apply, so a restart or reboot
# in between still puts them back.
SAVED=$DATA/saved

log() { /system/bin/log -t onigiri-mirror "$*"; }

# WxH to give the cover, "dex" while DeX owns the monitor, "hold" while the monitor sleeps (the
# screen is off in either mode), or nothing without a monitor.
mirror_size() {
    read status 2>/dev/null < $DP
    [ "$status" = connected ] || return
    # `cmd display get-displays` leaves out the DeX desktop. It stays listed here after DeX
    # exits, but off.
    displays=$(dumpsys display | grep 'DisplayInfo{') || return
    echo "$displays" | grep -q 'DisplayInfo{"Desktop", .*, state ON,' && { echo dex; return; }
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

# The cover's current "size" or "density": its override, else the physical value. Never restore
# with `wm size reset`: Samsung's reset forces a resolution of its own (840x808 on the cover),
# while setting the physical value clears the override.
current() {
    value=$(wm $1 -d 0)
    echo "$value" | sed -n "s/^Override $1: //p" | grep . || echo "$value" | sed -n "s/^Physical $1: //p"
}

mkdir -p $DATA
applied=
[ -e $SAVED ] && applied=unknown  # left applied by an earlier run: recheck at once
seen=
count=0
had_dex=  # DeX ran on this monitor
while :; do
    now=$(mirror_size)
    case $now in
        hold) sleep 2; continue ;;
        dex) had_dex=1; now= ;;
        '') had_dex= ;;
    esac
    if [ "$now" = "$seen" ]; then
        count=$((count + 1))
    else
        seen=$now
        count=0
    fi
    # Plugging in a monitor often starts DeX a few seconds later: wait for mirroring to hold, so
    # docking doesn't relayout the cover twice. Turning DeX off is the user's choice, and putting
    # the cover back never waits.
    want=$applied
    if [ -z "$now" ]; then
        want=
    elif [ -n "$had_dex" ] || [ $count -ge $STEADY ]; then
        want=$now
    fi
    if [ "$want" != "$applied" ]; then
        if [ -n "$want" ]; then
            [ -e $SAVED ] || echo "$(current size) $(current density)" > $SAVED
            wm size $want -d 0 && wm density $DPI -d 0 && log "cover fit to the monitor: $want"
        elif [ -e $SAVED ]; then
            read size density < $SAVED
            wm size $size -d 0 && wm density $density -d 0 && rm -f $SAVED && log "cover restored"
        fi
        applied=$want
    fi
    sleep 2
done
