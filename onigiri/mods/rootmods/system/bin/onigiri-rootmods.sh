#!/system/bin/sh
# Installs the KernelSU modules Onigiri ships in /system/etc/onigiri-rootmods (NeoZygisk,
# HMA-OSS, TEESimulator, Tricky Addon, BRENE, Hybrid Mount) with Onigiri's defaults for HMA-OSS
# and BRENE. onigiri-rootmods.rc starts it at every boot: KernelSU only installs modules once the
# phone has started, and they turn on at the next restart.
#
# Each module is installed once. Removing one in the KernelSU app sticks, and that app updates
# them from then on. A phone that already had its own modules when this first ran is left alone,
# since some of these disable or delete the modules they replace; deleting $STATE/skip opts in.

SRC=/system/etc/onigiri-rootmods
# A file per module id handled, ID.pending while one installs, plus install.log
STATE=/data/adb/onigiri/rootmods
KSUD=/data/adb/ksud

set -o pipefail  # ksud's exit status through the install log pipe
log() { /system/bin/log -t onigiri-rootmods "$*"; }

# Onigiri's default settings for a module, put in place before it installs. Never over settings
# that already exist. Each appears in one step once complete, so a cut-short run never leaves
# half of them to be taken for the user's own.
seed() {
    case $1 in
    hma_oss_zygisk)
        # Its service runs in system_server and adopts any /data/misc/hide_my_applist_* dir.
        ls -d /data/misc/hide_my_applist_* > /dev/null 2>&1 && return
        DIR=/data/misc/hide_my_applist_$(tr -dc a-z < /dev/urandom | head -c 16)  # random like its own
        NEW=/data/misc/onigiri-hma.new  # outside that name until complete
        rm -rf $NEW && mkdir -m 700 $NEW && cp $SRC/hma-oss.json $NEW/config.json &&
            chmod 600 $NEW/config.json && chown -R system:system $NEW && mv $NEW $DIR && restorecon -R $DIR
        ;;
    brene)
        # Hide Custom ROM Paths and Hide /system/addon.d Path on; its installer adds the rest.
        # Its defaults also turn off developer options and USB and wireless debugging at every
        # boot; left empty, it leaves them to the user.
        [ -e /data/adb/brene/config.sh ] && return
        mkdir -p /data/adb/brene && printf '%s\n' config_hide_custom_rom_paths=1 config_hide_addon_d=1 \
            config_developer_options= config_usb_debugging= config_wireless_debugging= \
            > /data/adb/brene/config.sh.new && mv /data/adb/brene/config.sh.new /data/adb/brene/config.sh
        ;;
    esac || { log "Setting up the $1 defaults failed"; return 1; }
}

# Decided on the first run and recorded in one step, so a cut-short run decides again.
if [ ! -d $STATE ]; then
    rm -rf $STATE.new && mkdir -p $STATE.new || exit 1
    if [ -n "$(ls /data/adb/modules 2> /dev/null)" ]; then
        touch $STATE.new/skip || exit 1
        log "Kept the modules already installed"
    fi
    mv $STATE.new $STATE || exit 1
fi
[ -e $STATE/skip ] && exit 0

# The KernelSU app installs ksud the first time it opens; do the same, so this works before that.
# Also over one that doesn't run, like a copy cut short.
if ! $KSUD --version > /dev/null 2>&1 && ! $SRC/ksud install; then
    log "Installing ksud failed"
    exit 1
fi

# The NN- prefix sets the order: Zygisk before the modules that need it, and the metamodule
# last, because KernelSU refuses other modules while one is waiting for a restart.
for ZIP in $SRC/*.zip; do
    ID=${ZIP##*/}
    ID=${ID#*-}
    ID=${ID%.zip}
    [ -e $STATE/$ID ] && continue
    # Already installed by hand before Onigiri shipped it: keep that one. Ours, if its install was
    # cut short (KernelSU still turns on what it got of it), installs again, unless it has been
    # turned off or removed in the KernelSU app since: reinstalling would undo that.
    MOD=/data/adb/modules/$ID
    if [ ! -d $MOD ] || { [ -e $STATE/$ID.pending ] && [ ! -e $MOD/disable ] && [ ! -e $MOD/remove ]; }; then
        seed $ID || continue
        touch $STATE/$ID.pending || { log "Couldn't mark $ID as installing"; continue; }
        # Through a pipe: pm, am and settings in the installers hand their output to
        # system_server, which fails ("Failed transaction") on a file in /data/adb.
        if ! $KSUD module install "$ZIP" 2>&1 | cat >> $STATE/install.log; then
            log "Installing $ID failed, see $STATE/install.log"
            continue
        fi
    fi
    touch $STATE/$ID && rm -f $STATE/$ID.pending
done
