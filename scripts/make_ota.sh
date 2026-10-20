#!/usr/bin/env bash
# Usage: make_ota <installed AP .tar.md5> <new AP .tar.md5> <output .zip>
#
# Builds a signed incremental OTA between two Onigiri Odin packages with the generator Samsung
# ships in the target firmware (extract_fw puts it in out/fw/SM-F731B_XXV/fota). Recovery checks
# every block it reads against the installed build first, so the package only installs on a
# phone that holds exactly that build. Needs ~60 GB free under out/tmp.

set -eo pipefail

[ "$#" -eq 3 ] || { echo "Usage: make_ota <installed AP .tar.md5> <new AP .tar.md5> <output .zip>" >&2; exit 1; }
SOURCE="$(realpath "$1")"
TARGET="$(realpath "$2")"
OUTPUT="$(realpath "$3")"
FOTA="$FW_DIR/SM-F731B_XXV/fota"
if [ ! -x "$FOTA/OTA/tools/ota_from_target_files" ]; then
    echo "Samsung's OTA tools are missing: re-extract the target firmware with \"extract_fw --force\"" >&2
    exit 1
fi

mkdir -p "$OUT_DIR/tmp"
WORK="$(mktemp -d "$OUT_DIR/tmp/ota.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# TARGET_FILES <AP> <zip>: the target-files layout ota_from_target_files reads, from an Odin AP.
TARGET_FILES()
{
    local TF="$WORK/tf"
    mkdir -p "$TF/IMAGES" "$TF/META" "$TF/OTA/bin" "$TF/RECOVERY/RAMDISK/system/etc"
    tar -xf "$1" -C "$TF/IMAGES"
    for IMAGE in "$TF"/IMAGES/*.lz4; do
        lz4 -dq --rm "$IMAGE" "${IMAGE%.lz4}"
    done
    # Recovery is only ever flashed with Odin.
    rm -f "$TF/IMAGES/recovery.img"
    simg2img "$TF/IMAGES/super.img" "$TF/IMAGES/super.raw"
    rm "$TF/IMAGES/super.img"
    local PARTITION
    for PARTITION in system vendor product system_ext odm vendor_dlkm system_dlkm; do
        lpunpack -p "$PARTITION" "$TF/IMAGES/super.raw" "$TF/IMAGES" > /dev/null
        # erofs images are not sparse, so the generator diffs them whole and needs no block map.
        : > "$TF/IMAGES/$PARTITION.map"
        mkdir "$TF/${PARTITION^^}"
        case "$PARTITION" in
            system) PROP=/system/build.prop ;;
            vendor) PROP=/build.prop ;;
            *) PROP=/etc/build.prop ;;
        esac
        dump.erofs --cat --path="$PROP" "$TF/IMAGES/$PARTITION.img" > "$TF/${PARTITION^^}/build.prop"
    done
    rm "$TF/IMAGES/super.raw"
    cp "$FOTA/META/misc_info.txt" "$FOTA/META/dynamic_partitions_info.txt" "$TF/META/"
    cp "$FOTA/RECOVERY/RAMDISK/system/etc/recovery.fstab" "$TF/RECOVERY/RAMDISK/system/etc/"
    cp "$FOTA/OTA/bin/updater" "$TF/OTA/bin/"
    (cd "$TF" && zip -q -0 -r "$2" .)
    rm -rf "$TF"
}

echo "- Unpacking $(basename "$SOURCE")"
TARGET_FILES "$SOURCE" "$WORK/source.zip"
echo "- Unpacking $(basename "$TARGET")"
TARGET_FILES "$TARGET" "$WORK/target.zip"

# The generator expects an AOSP host-tools layout.
mkdir -p "$WORK/host/framework"
ln -s "$FOTA/OTA/tools" "$WORK/host/bin"
ln -s "$FOTA/OTA/tools" "$WORK/host/lib64"
ln -s "$FOTA/OTA/tools/signapk.jar" "$WORK/host/framework/signapk.jar"

echo "- Generating $(basename "$OUTPUT")"
# No VINTF metadata in these target-files; both builds share Samsung's vendor anyway.
PATH="$FOTA/OTA/tools:$PATH" LD_LIBRARY_PATH="$FOTA/OTA/tools" TMPDIR="$WORK" \
    ota_from_target_files --skip_compatibility_check -p "$WORK/host" \
    -s "$SRC_DIR/scripts/ota_releasetools.py" -k "$SRC_DIR/security/onigiri_ota" \
    -i "$WORK/source.zip" "$WORK/target.zip" "$OUTPUT" > "$WORK/ota.log" 2>&1 || {
        tail -n 40 "$WORK/ota.log" >&2
        exit 1
    }
echo "- OTA package created: $OUTPUT ($(du -h "$OUTPUT" | cut -f 1))"
