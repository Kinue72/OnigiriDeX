#!/usr/bin/env bash
# Usage: extract_fw [-f|--force]
#
# Extracts the pinned Fold5 (source) and Flip5 model (target) firmware that scripts/import_fw.py
# put in out/odin into out/fw/<model>_<csc>: the kernel images, the partitions of super.img with
# their fs_config and file_context, a patched vbmeta and, for the target, Samsung's OTA tools.

source "$SRC_DIR/scripts/utils/firmware_utils.sh" || exit 1

FORCE=false
case "$*" in
    "") ;;
    -f|--force) FORCE=true ;;
    *)
        echo "Usage: extract_fw [-f|--force]" >&2
        exit 1
        ;;
esac

MODEL=""
CSC=""
BL_TAR=""
AP_TAR=""

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

EXTRACT_AVB_BINARIES()
{
    LOG_STEP_IN "- Extracting AVB binaries"

    mkdir -p "$FW_DIR/${MODEL}_${CSC}/avb"

    EXTRACT_FILE_FROM_TAR "$BL_TAR" "vbmeta.img" || exit 1
    mv -f "$FW_DIR/${MODEL}_${CSC}/vbmeta.img" "$FW_DIR/${MODEL}_${CSC}/avb/vbmeta.img" || exit 1

    # Flags 3 turn off verity and verification, which the modified partitions would fail.
    LOG "- Creating vbmeta_patched.img..."
    EVAL "cp -a \"$FW_DIR/${MODEL}_${CSC}/avb/vbmeta.img\" \"$FW_DIR/${MODEL}_${CSC}/avb/vbmeta_patched.img\"" || exit 1
    EVAL "printf \"\x03\" | dd of=\"$FW_DIR/${MODEL}_${CSC}/avb/vbmeta_patched.img\" bs=1 seek=123 count=1 conv=notrunc" || exit 1

    LOG_STEP_OUT
}

EXTRACT_KERNEL_BINARIES()
{
    LOG_STEP_IN "- Extracting kernel binaries"

    mkdir -p "$FW_DIR/${MODEL}_${CSC}/kernel"
    for f in boot.img dtbo.img init_boot.img vendor_boot.img recovery.img; do
        EXTRACT_FILE_FROM_TAR "$AP_TAR" "$f" || exit 1
        # The Fold5 AP has no recovery.img; the build only takes kernel images from the target.
        [ -f "$FW_DIR/${MODEL}_${CSC}/$f" ] || continue
        mv -f "$FW_DIR/${MODEL}_${CSC}/$f" "$FW_DIR/${MODEL}_${CSC}/kernel/$f" || exit 1
    done

    LOG_STEP_OUT
}

# The target AP ships Samsung's OTA generator (ota_from_target_files, updater and target-files
# metadata); scripts/make_ota.sh runs it.
EXTRACT_OTA_TOOLS()
{
    [ "$MODEL/$CSC" = "$TARGET_FIRMWARE" ] || return 0

    LOG "- Extracting OTA tools..."
    EVAL "tar xf \"$AP_TAR\" -C \"$TMP_DIR\" meta-data/fota.zip" || exit 1
    EVAL "unzip -q \"$TMP_DIR/meta-data/fota.zip\" \"OTA/*\" META/misc_info.txt META/dynamic_partitions_info.txt RECOVERY/RAMDISK/system/etc/recovery.fstab -d \"$FW_DIR/${MODEL}_${CSC}/fota\"" || exit 1
    rm -rf "$TMP_DIR/meta-data"
}

EXTRACT_OS_PARTITIONS()
{
    local SUPER="$FW_DIR/${MODEL}_${CSC}/super.img"
    local METADATA="$FW_DIR/${MODEL}_${CSC}/os_partitions_metadata.txt"
    local LPDUMP
    local GROUP_NAME
    local IMAGE

    LOG_STEP_IN "- Extracting OS partitions"

    EXTRACT_FILE_FROM_TAR "$AP_TAR" "super.img" || exit 1
    UNSPARSE_IMAGE "$SUPER" || exit 1

    LOG "- Unpacking super.img..."

    if ! LPDUMP="$(lpdump "$SUPER" 2>&1)"; then
        LOGE "Cannot read the super partition layout:\n$LPDUMP"
        exit 1
    fi
    GROUP_NAME="$(grep -F "Group: " <<< "$LPDUMP" | tr -d " " | cut -d ":" -f 2 | sort -u)"
    {
        echo "use_dynamic_partitions=true"
        echo "super_partition_size=$(wc -c "$SUPER" | cut -d " " -f 1)"
        echo "super_partition_group=$GROUP_NAME"
        echo -n "super_${GROUP_NAME}_group_size="
        grep -F "Maximum size: " <<< "$LPDUMP" | tr -d " " | cut -d ":" -f 2 | sed "s/bytes//" | sort -n -r | head -n 1
        echo -n "super_${GROUP_NAME}_partition_list="
        grep -F "Name: " <<< "$LPDUMP" | tr -d " " | cut -d ":" -f 2 | sed -e "/default/d" -e "/$GROUP_NAME/d" | awk '!visited[$0]++' | tr "\n" " " | xargs
    } > "$METADATA"

    for PARTITION in system vendor product system_ext odm vendor_dlkm system_dlkm; do
        IMAGE="$FW_DIR/${MODEL}_${CSC}/$PARTITION.img"
        EVAL "lpunpack -p \"$PARTITION\" \"$SUPER\" \"$FW_DIR/${MODEL}_${CSC}\"" || exit 1
        if [[ "$(READ_BYTES_AT "$IMAGE" "1024" "4")" != "e0f5e1e2" ]]; then
            LOGE "$PARTITION.img is not an EROFS image"
            exit 1
        fi
        echo "${PARTITION}_file_system=erofs" >> "$METADATA"
        EXTRACT_EROFS_PARTITION "$IMAGE" "$FW_DIR/${MODEL}_${CSC}" || exit 1
        rm -f "$IMAGE"
    done

    rm -f "$SUPER"

    LOG_STEP_OUT
}

for FIRMWARE in "$SOURCE_FIRMWARE:$SOURCE_FIRMWARE_VERSION" "$TARGET_FIRMWARE:$TARGET_FIRMWARE_VERSION"; do
    REQUIRED_FIRMWARE="${FIRMWARE#*:}"
    IFS=/ read -r MODEL CSC <<< "${FIRMWARE%%:*}"

    LOG_STEP_IN "- Processing $MODEL firmware with $CSC CSC"
    LOG "- Required firmware: $REQUIRED_FIRMWARE"
    LOG_STEP_IN

    if [ -f "$FW_DIR/${MODEL}_${CSC}/.extracted" ]; then
        if [[ "$(cat "$FW_DIR/${MODEL}_${CSC}/.extracted")" != "$REQUIRED_FIRMWARE" ]]; then
            LOGE "Extracted firmware differs from the pinned version. Preserve or move it before extracting."
            exit 1
        fi
        if ! $FORCE; then
            python3 "$SRC_DIR/scripts/verify_fw.py" "$MODEL/$CSC" "$FW_DIR/${MODEL}_${CSC}" || exit 1
            LOG "This pinned firmware has already been extracted"
            LOG_STEP_OUT
            LOG_STEP_OUT
            continue
        fi
    fi

    if [ ! -f "$ODIN_DIR/${MODEL}_${CSC}/.downloaded" ] || \
            [[ "$(cat "$ODIN_DIR/${MODEL}_${CSC}/.downloaded")" != "$REQUIRED_FIRMWARE" ]]; then
        LOGE "Import the pinned $MODEL / $CSC archive with scripts/import_fw.py before extracting."
        exit 1
    fi

    [ -f "$FW_DIR/${MODEL}_${CSC}/.extracted" ] && rm -rf "$FW_DIR/${MODEL}_${CSC}"
    mkdir -p "$FW_DIR/${MODEL}_${CSC}"

    BL_TAR="$(find "$ODIN_DIR/${MODEL}_${CSC}" -name "BL_${REQUIRED_FIRMWARE%%/*}*.md5" | sort -r | head -n 1)"
    AP_TAR="$(find "$ODIN_DIR/${MODEL}_${CSC}" -name "AP_${REQUIRED_FIRMWARE%%/*}*.md5" | sort -r | head -n 1)"

    if [ ! "$BL_TAR" ]; then
        LOGE "No BL tar found"
        exit 1
    elif [ ! "$AP_TAR" ]; then
        LOGE "No AP tar found"
        exit 1
    fi

    EXTRACT_KERNEL_BINARIES
    EXTRACT_OTA_TOOLS
    EXTRACT_OS_PARTITIONS
    EXTRACT_AVB_BINARIES

    python3 "$SRC_DIR/scripts/verify_fw.py" "$MODEL/$CSC" "$FW_DIR/${MODEL}_${CSC}" || exit 1
    echo -n "$REQUIRED_FIRMWARE" > "$FW_DIR/${MODEL}_${CSC}/.extracted"

    LOG_STEP_OUT; LOG_STEP_OUT
done

exit 0
