#!/usr/bin/env bash
# Usage: make_ota <installed AP .tar.md5> <new AP .tar.md5> <output .zip>
#        make_ota --unpack <AP .tar.md5>
#
# Builds a signed incremental OTA between two Onigiri Odin packages of one Flip5 model with the
# generator Samsung ships in that model's firmware (extract_fw puts it in out/fw/<model>_<csc>/fota).
# The model comes from the new AP's name (Onigiri_AP_<model>_...) and both APs' vendor must be that
# model's. Phones only fetch the package named for their own build; recovery also checks every
# block the package reads against that build before it writes anything (blocks it doesn't read go
# unchecked). Needs ~60 GB free under out/tmp.
#
# Unpacking an AP's super takes minutes and 9 GB, so out/images/<AP file name> may hold its
# partition images ready: build_odin.sh leaves those of the AP it built, and --unpack makes them
# for another one (scripts/release.sh --previous, while the new AP is still building). They are
# used once, and only for the AP whose checksum they were saved with.

set -eo pipefail

PARTITIONS=(system vendor product system_ext odm vendor_dlkm system_dlkm)

# UNPACK_SUPER <AP> <dir>: the partition images in an Odin AP's super.
UNPACK_SUPER()
{
    local PARTITION
    tar -xOf "$1" super.img.lz4 | lz4 -dcq > "$2/super.img"
    simg2img "$2/super.img" "$2/super.raw"
    rm "$2/super.img"
    for PARTITION in "${PARTITIONS[@]}"; do
        lpunpack -p "$PARTITION" "$2/super.raw" "$2" > /dev/null
    done
    rm "$2/super.raw"
}

# PACKAGE_MD5 <AP>: the checksum line Odin packages end with.
PACKAGE_MD5()
{
    tail -c 4096 "$1" | tr -d '\0' | tail -n 1
}

if [ "${1:-}" = --unpack ] && [ "$#" -eq 2 ]; then
    AP="$(realpath "$2")"
    IMAGES="$OUT_DIR/images/$(basename "$AP")"
    rm -rf "$IMAGES"
    mkdir -p "$IMAGES"
    UNPACK_SUPER "$AP" "$IMAGES"
    # Last, so a half-unpacked AP is never taken for a whole one.
    PACKAGE_MD5 "$AP" > "$IMAGES/package.md5"
    exit 0
fi

[ "$#" -eq 3 ] || { sed -n '2,3s/^# //p' "$0" >&2; exit 1; }
SOURCE="$(realpath "$1")"
TARGET="$(realpath "$2")"
OUTPUT="$(realpath "$3")"
MODEL="$(basename "$TARGET" | sed -n 's/^Onigiri_AP_\(SM-[A-Z0-9]*\)_.*/\1/p')"
CSC="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["targets"][sys.argv[2]]["csc"])' \
    "$SRC_DIR/onigiri/configs/firmware.json" "$MODEL")" || {
    echo "$(basename "$TARGET") isn't named Onigiri_AP_<model>_... for a model in firmware.json" >&2
    exit 1
}
FOTA="$FW_DIR/${MODEL}_$CSC/fota"
if [ ! -x "$FOTA/OTA/tools/ota_from_target_files" ]; then
    echo "Samsung's OTA tools are missing: re-extract the target firmware with \"extract_fw --force\"" >&2
    exit 1
fi

mkdir -p "$OUT_DIR/tmp"
WORK="$(mktemp -d "$OUT_DIR/tmp/ota.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# TARGET_FILES <AP> <dir>: the target-files layout ota_from_target_files reads, from an Odin AP.
TARGET_FILES()
{
    local TF="$2"
    local READY="$OUT_DIR/images/$(basename "$1")"
    local PARTITION
    mkdir -p "$TF/IMAGES" "$TF/META" "$TF/OTA/bin" "$TF/RECOVERY/RAMDISK/system/etc"
    tar -xf "$1" -C "$TF/IMAGES" --exclude=super.img.lz4
    for IMAGE in "$TF"/IMAGES/*.lz4; do
        lz4 -dq --rm "$IMAGE" "${IMAGE%.lz4}"
    done
    # Recovery is only ever flashed with Odin.
    rm -f "$TF/IMAGES/recovery.img"
    if [ -f "$READY/package.md5" ] && [ "$(PACKAGE_MD5 "$1")" = "$(cat "$READY/package.md5")" ]; then
        for PARTITION in "${PARTITIONS[@]}"; do
            mv "$READY/$PARTITION.img" "$TF/IMAGES/"
        done
        rm -rf "$READY"
    else
        UNPACK_SUPER "$1" "$TF/IMAGES"
    fi
    for PARTITION in "${PARTITIONS[@]}"; do
        mkdir "$TF/${PARTITION^^}"
        case "$PARTITION" in
            system) PROP=/system/build.prop ;;
            vendor) PROP=/build.prop ;;
            *) PROP=/etc/build.prop ;;
        esac
        dump.erofs --cat --path="$PROP" "$TF/IMAGES/$PARTITION.img" > "$TF/${PARTITION^^}/build.prop"
    done
    cp "$FOTA/META/misc_info.txt" "$FOTA/META/dynamic_partitions_info.txt" "$TF/META/"
    cp "$FOTA/RECOVERY/RAMDISK/system/etc/recovery.fstab" "$TF/RECOVERY/RAMDISK/system/etc/"
    cp "$FOTA/OTA/bin/updater" "$TF/OTA/bin/"
}

echo "- Unpacking $(basename "$SOURCE")"
TARGET_FILES "$SOURCE" "$WORK/source"
echo "- Unpacking $(basename "$TARGET")"
TARGET_FILES "$TARGET" "$WORK/target"
for TF in source target; do
    FOUND="$(sed -n 's/^ro.product.vendor.model=//p' "$WORK/$TF/VENDOR/build.prop")"
    [ "$FOUND" = "$MODEL" ] || { echo "The $TF AP is a $FOUND build, not $MODEL" >&2; exit 1; }
done

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
