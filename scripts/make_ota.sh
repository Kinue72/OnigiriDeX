#!/usr/bin/env bash
# Usage: make_ota <installed AP .tar.md5> <new AP .tar.md5> <output .zip>
#
# Builds a signed incremental OTA between two Onigiri Odin packages with the generator Samsung
# ships in the target firmware (extract_fw puts it in out/fw/SM-F731B_XXV/fota). Phones only
# fetch the package named for their own build; recovery also checks every block the package reads
# against that build before it writes anything (blocks it doesn't read go unchecked). Needs
# ~60 GB free under out/tmp.

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
PARTITIONS=(system vendor product system_ext odm vendor_dlkm system_dlkm)

# TARGET_FILES <AP> <dir>: the target-files layout ota_from_target_files reads, from an Odin AP.
TARGET_FILES()
{
    local TF="$2"
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
    for PARTITION in "${PARTITIONS[@]}"; do
        lpunpack -p "$PARTITION" "$TF/IMAGES/super.raw" "$TF/IMAGES" > /dev/null
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
}

echo "- Unpacking $(basename "$SOURCE")"
TARGET_FILES "$SOURCE" "$WORK/source"
echo "- Unpacking $(basename "$TARGET")"
TARGET_FILES "$TARGET" "$WORK/target"

# Without block maps the generator diffs each image block by block at the same offsets, so data
# that only moved (behind a new or grown file) would ship again in full. The maps name the
# unchanged runs, and it only reads the maps of sparse images.
for PARTITION in "${PARTITIONS[@]}"; do
    printf -- "- Matching %s: " "$PARTITION"
    python3 "$SRC_DIR/scripts/ota_blockmap.py" \
        "$WORK"/{source,target}/IMAGES/"$PARTITION".img "$WORK"/{source,target}/IMAGES/"$PARTITION".map
    for TF in source target; do
        img2simg "$WORK/$TF/IMAGES/$PARTITION.img" "$WORK/$TF/IMAGES/$PARTITION.simg"
        mv "$WORK/$TF/IMAGES/$PARTITION.simg" "$WORK/$TF/IMAGES/$PARTITION.img"
    done
done
for TF in source target; do
    (cd "$WORK/$TF" && zip -q -0 -r "$WORK/$TF.zip" .)
    rm -rf "${WORK:?}/$TF"
done

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
