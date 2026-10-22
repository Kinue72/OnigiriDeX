#!/system/bin/sh
# Installs the KernelSU modules Onigiri ships in /system/etc/onigiri-rootmods (NeoZygisk, Vector,
# HMA-OSS, TEESimulator, Tricky Addon, BRENE, Hybrid Mount) with Onigiri's defaults for HMA-OSS
# and BRENE. onigiri-rootmods.rc starts it at every boot: KernelSU only installs modules once the
# phone has started, and they turn on at the next restart.
#
# Each module is installed once. Removing one in the KernelSU app sticks, and that app updates
# them from then on. A phone that already had its own modules when this first ran is left alone,
# since some of these disable or delete the modules they replace; deleting $STATE/skip opts in.

SRC=/system/etc/onigiri-rootmods
STATE=/data/adb/onigiri/rootmods  # a file per module id handled, plus install.log
KSUD=/data/adb/ksud

set -o pipefail  # ksud's exit status through the install log pipe
log() { /system/bin/log -t onigiri-rootmods "$*"; }

# Onigiri's default settings for a module, put in place before it installs. Never over settings
# that already exist.
seed() {
    case $1 in
    hma_oss_zygisk)
        # Its service runs in system_server and adopts any /data/misc/hide_my_applist_* dir.
        ls -d /data/misc/hide_my_applist_* > /dev/null 2>&1 && return
        DIR=/data/misc/hide_my_applist_$(tr -dc a-z < /dev/urandom | head -c 16)  # random like its own
        mkdir -m 700 $DIR && cp $SRC/hma-oss.json $DIR/config.json && chmod 600 $DIR/config.json &&
            chown -R system:system $DIR && restorecon -R $DIR
        ;;
    brene)
        # Hide Custom ROM Paths and Hide /system/addon.d Path on; its installer adds the rest.
        [ -e /data/adb/brene/config.sh ] && return
        mkdir -p /data/adb/brene &&
            printf '%s\n' config_hide_custom_rom_paths=1 config_hide_addon_d=1 > /data/adb/brene/config.sh
        ;;
    esac || log "Setting up the $1 defaults failed"
}

if [ ! -d $STATE ]; then
    mkdir -p $STATE || exit 1
    if [ -n "$(ls /data/adb/modules 2> /dev/null)" ]; then
        touch $STATE/skip
        log "Kept the modules already installed"
    fi
fi
[ -e $STATE/skip ] && exit 0

# The KernelSU app installs ksud the first time it opens; do the same, so this works before that.
if [ ! -x $KSUD ] && ! $SRC/ksud install; then
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
    # Already installed by hand before Onigiri shipped it: keep that one.
    if [ ! -d /data/adb/modules/$ID ]; then
        seed $ID
        # Through a pipe: pm, am and settings in the installers hand their output to
        # system_server, which fails ("Failed transaction") on a file in /data/adb.
        if ! $KSUD module install "$ZIP" 2>&1 | cat >> $STATE/install.log; then
            log "Installing $ID failed, see $STATE/install.log"
            continue
        fi
    fi
    touch $STATE/$ID
done
