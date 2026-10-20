#!/system/bin/sh
# Over-the-air updates (Settings > Onigiri Software > Software update). Started by
# onigiri-update.rc when Settings sets sys.onigiri.update:
#
#   check     look at the latest GitHub release; sets sys.onigiri.update.ready to its tag when
#             it carries an update from this build
#   install   download that update to /cache and reboot; recovery installs it
#
# Progress goes to sys.onigiri.update.status (92 bytes at most), which Settings shows. Each
# release carries version.txt ("<ro.onigiri.version> <tag>") and
# Onigiri_OTA_<from ro.onigiri.version>.zip, an incremental package that recovery only accepts
# when it is signed with the Onigiri OTA key and the phone holds exactly the build it was made
# from. Anything else needs the full package.
# ONIGIRI_UPDATE_RELEASES points it elsewhere by hand (testing).

RELEASES="${ONIGIRI_UPDATE_RELEASES:-https://github.com/Kinue72/OnigiriDeX/releases}"
CURRENT="$(getprop ro.onigiri.version)"
PACKAGE=/cache/update.zip

status() { setprop sys.onigiri.update.status "$1"; }
fetch() { curl -fsSL --connect-timeout 20 "$@"; }
trap 'setprop sys.onigiri.update ""' EXIT
set -f  # version.txt is split into words below; never expand them as file names

case "$(getprop sys.onigiri.update)" in
check)
    setprop sys.onigiri.update.ready ""
    status "Checking for updates…"
    LATEST="$(fetch --max-time 60 "$RELEASES/latest/download/version.txt")" || {
        # curl exits 22 when GitHub answers with an error, e.g. no release yet.
        if [ $? = 22 ]; then
            status "No Onigiri release with updates on GitHub yet."
        else
            status "Couldn't reach GitHub. Tap to try again."
        fi
        exit 1
    }
    set -- $LATEST
    if [ "$1" = "$CURRENT" ]; then
        status "Onigiri is up to date ($2)"
    elif SIZE="$(fetch --max-time 60 -I -o /dev/null -w '%header{content-length}' "$RELEASES/download/$2/Onigiri_OTA_$CURRENT.zip")"; then
        setprop sys.onigiri.update.ready "$2"
        status "Onigiri $2 is available ($((${SIZE:-0} / 1048576 + 1)) MB). Tap to install."
    else
        status "Onigiri $2 is out, but needs a full flash with Odin."
    fi
    ;;
install)
    TAG="$(getprop sys.onigiri.update.ready)"
    [ "$TAG" ] || exit 1
    status "Downloading Onigiri $TAG…"
    rm -f "$PACKAGE"
    # From the release the check found, even if a newer one came out since.
    fetch --max-time 3600 -o "$PACKAGE" "$RELEASES/download/$TAG/Onigiri_OTA_$CURRENT.zip" || {
        rm -f "$PACKAGE"
        setprop sys.onigiri.update.ready ""
        status "Download failed. Tap to check again."
        exit 1
    }
    status "Restarting to install Onigiri $TAG…"
    echo "--update_package=$PACKAGE" > /cache/recovery/command && sync && reboot recovery
    ;;
esac
