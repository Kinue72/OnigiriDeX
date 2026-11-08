#!/system/bin/sh
# Installs an over-the-air update for Software update (Settings > Onigiri Software), which checks
# update.json itself (moe.foss.onigiri.update.Updates in SecSettings). When the user confirms, it
# sets sys.onigiri.update.ready (the release tag) and sys.onigiri.update.sha256 (the package's,
# from update.json), then sys.onigiri.update=install, and onigiri-update.rc runs this as root. It
# downloads the package for this build to /cache, checks it and restarts to recovery, which
# installs it. Install from storage sets sys.onigiri.update.file (a package Settings copied into
# its own files) instead of the tag, and that file is taken instead of downloading. Progress: sys.onigiri.update.state (downloading, verifying, restarting or failed)
# and sys.onigiri.update.progress (bytes so far); sys.onigiri.update=cancel stops it.
#
# Each release carries per model Onigiri_OTA_<from ro.onigiri.version>.zip (SM-F731B, the name
# older builds look for) or Onigiri_OTA_<model>_<from ro.onigiri.version>.zip (other models): a
# package recovery only accepts when it is signed with the Onigiri OTA key and the phone holds
# exactly the build it was made from, possibly several updates chained (scripts/ota_chain.py).
# sys.onigiri.update.releases points it and Settings elsewhere (testing).

RELEASES="$(getprop sys.onigiri.update.releases)"
RELEASES="${RELEASES:-https://github.com/Kinue72/OnigiriDeX/releases}"
CURRENT="$(getprop ro.onigiri.version)"
# The installed build's model (its vendor), not the bootloader's.
MODEL="$(getprop ro.product.vendor.model)"
OTA="Onigiri_OTA_$CURRENT.zip"
[ "$MODEL" = SM-F731B ] || OTA="Onigiri_OTA_${MODEL}_$CURRENT.zip"
PACKAGE=/cache/update.zip
MISC=/dev/block/bootdevice/by-name/misc

state() { setprop sys.onigiri.update.state "$1"; }
fail() { rm -f "$PACKAGE"; state failed; exit 1; }
trap 'setprop sys.onigiri.update ""' EXIT

[ "$(getprop sys.onigiri.update)" = install ] || exit 0
TAG="$(getprop sys.onigiri.update.ready)"
LOCAL="$(getprop sys.onigiri.update.file)"
SHA256="$(getprop sys.onigiri.update.sha256)"
{ [ "$TAG" ] || [ "$LOCAL" ]; } && [ "${#SHA256}" = 64 ] || fail

rm -f "$PACKAGE"
setprop sys.onigiri.update.progress 0
if [ "$LOCAL" ]; then
    state verifying
    cp "$LOCAL" "$PACKAGE" || fail
    rm -f "$LOCAL"
else
    state downloading
    # From the release the check found, even if a newer one came out since.
    curl -fsSL --connect-timeout 20 --max-time 3600 -o "$PACKAGE" "$RELEASES/download/$TAG/$OTA" &
    CURL=$!
    while kill -0 "$CURL" 2> /dev/null; do
        setprop sys.onigiri.update.progress "$(stat -c %s "$PACKAGE" 2> /dev/null || echo 0)"
        sleep 1
    done
    wait "$CURL" || fail
fi

state verifying
[ "$(sha256sum "$PACKAGE" | cut -d " " -f 1)" = "$SHA256" ] || fail

state restarting
# A chained package keeps the updates it finished in misc's stage field (offset 832, 32 bytes) and
# skips them when the install starts again; clear what an install that never ended left there.
dd if=/dev/zero of="$MISC" bs=32 seek=26 count=1 conv=notrunc 2> /dev/null
echo "--update_package=$PACKAGE" > /cache/recovery/command && sync && reboot recovery
