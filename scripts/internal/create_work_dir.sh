#!/usr/bin/env bash
# Fills the work dir: system, product and system_ext from the Fold5 firmware, the hardware
# partitions, kernel images and patched vbmeta from the Flip5 model's own.

source "$SRC_DIR/scripts/utils/build_utils.sh" || exit 1
CHECK_BUILD_DEPENDENCIES || exit 1

python3 "$SRC_DIR/scripts/verify_fw.py" "$SOURCE_FIRMWARE" "$FW_DIR/${SOURCE_FIRMWARE/\//_}" || exit 1
python3 "$SRC_DIR/scripts/verify_fw.py" "$TARGET_FIRMWARE" "$FW_DIR/${TARGET_FIRMWARE/\//_}" || exit 1

SOURCE_FIRMWARE_PATH="${SOURCE_FIRMWARE/\//_}"
TARGET_FIRMWARE_PATH="${TARGET_FIRMWARE/\//_}"

COPY_SOURCE_FIRMWARE()
{
    for f in product system; do
        LOG "- Copying /$f from source firmware"
        EVAL "rsync -a --mkpath --delete --exclude=\"*system_ext*\" \"$FW_DIR/$SOURCE_FIRMWARE_PATH/$f\" \"$WORK_DIR\"" || exit 1
        sed "/system_ext/d" "$FW_DIR/$SOURCE_FIRMWARE_PATH/file_context-$f" > "$WORK_DIR/configs/file_context-$f"
        sed "/system_ext/d" "$FW_DIR/$SOURCE_FIRMWARE_PATH/fs_config-$f" > "$WORK_DIR/configs/fs_config-$f"
    done

    LOG_STEP_IN "- Copying /system_ext from source firmware"

    [ -L "$WORK_DIR/system/system_ext" ] && rm -f "$WORK_DIR/system/system_ext"
    [ -d "$WORK_DIR/system/system/system_ext" ] && rm -rf "$WORK_DIR/system/system/system_ext"

    EVAL "rsync -a --mkpath --delete \"$FW_DIR/$SOURCE_FIRMWARE_PATH/system_ext\" \"$WORK_DIR\"" || exit 1
    mkdir -p "$WORK_DIR/system/system_ext"
    EVAL "ln -sf \"/system_ext\" \"$WORK_DIR/system/system/system_ext\"" || exit 1
    SET_METADATA "system" "system_ext" 0 0 755 "u:object_r:system_file:s0"
    SET_METADATA "system" "system/system_ext" 0 0 644 "u:object_r:system_file:s0"
    EVAL "cp -a \"$FW_DIR/$SOURCE_FIRMWARE_PATH/file_context-system_ext\" \"$WORK_DIR/configs/file_context-system_ext\"" || exit 1
    EVAL "cp -a \"$FW_DIR/$SOURCE_FIRMWARE_PATH/fs_config-system_ext\" \"$WORK_DIR/configs/fs_config-system_ext\"" || exit 1

    LOG_STEP_OUT
}

COPY_TARGET_FIRMWARE()
{
    # vendor_dlkm and system_dlkm come from the Onigiri kernel instead (prepare_kernel.sh).
    for f in odm vendor; do
        LOG "- Copying /$f from target firmware"
        EVAL "rsync -a --mkpath --delete \"$FW_DIR/$TARGET_FIRMWARE_PATH/$f\" \"$WORK_DIR\"" || exit 1
        EVAL "cp -a \"$FW_DIR/$TARGET_FIRMWARE_PATH/file_context-$f\" \"$WORK_DIR/configs/file_context-$f\"" || exit 1
        EVAL "cp -a \"$FW_DIR/$TARGET_FIRMWARE_PATH/fs_config-$f\" \"$WORK_DIR/configs/fs_config-$f\"" || exit 1
    done
}

COPY_TARGET_KERNEL()
{
    LOG "- Copying target firmware kernel images"
    EVAL "rsync -a --mkpath --delete \"$FW_DIR/$TARGET_FIRMWARE_PATH/kernel\" \"$WORK_DIR\"" || exit 1
    LOG "- Copying vbmeta.img from target firmware"
    EVAL "cp -a \"$FW_DIR/$TARGET_FIRMWARE_PATH/avb/vbmeta_patched.img\" \"$WORK_DIR/kernel/vbmeta.img\"" || exit 1
}

mkdir -p "$WORK_DIR/configs"
COPY_SOURCE_FIRMWARE
COPY_TARGET_FIRMWARE
COPY_TARGET_KERNEL

exit 0
