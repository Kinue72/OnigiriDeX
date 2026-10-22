#!/usr/bin/env bash

if [ ! -f "$SRC_DIR/target/b5q/patches/cover_display/customize.sh" ] || \
        [ ! -f "$SRC_DIR/target/b5q/patches/dex/customize.sh" ]; then
    echo "Cover display and DeX patches still require firmware inspection and implementation." >&2
    exit 1
fi

source "$SRC_DIR/scripts/utils/build_utils.sh" || exit 1
CHECK_BUILD_DEPENDENCIES || exit 1
"$SRC_DIR/scripts/prepare_signing_keys.sh" || exit 1

FORCE=false
BUILD_ROM=false

START_TIME="$(date +%s)"

SOURCE_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$SOURCE_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$SOURCE_FIRMWARE")"
TARGET_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")"

GET_WORK_DIR_HASH()
{
    {
        find "$SRC_DIR/onigiri" "$SRC_DIR/prebuilts" "$SRC_DIR/target/$TARGET_CODENAME" -type f -print0
        find "$SRC_DIR/scripts" -type f \( -name '*.sh' -o -name '*.py' \) -print0
        printf '%s\0' "$SRC_DIR/security/onigiri_platform.x509.pem" "$SRC_DIR/security/onigiri_ota.x509.pem"
        if [ -f "$OUT_DIR/target/b5q/kernel/artifacts.json" ]; then
            printf '%s\0' "$OUT_DIR/target/b5q/kernel/artifacts.json"
        fi
        if [ -f "$FW_DIR/SM-S921B_XXV/software/manifest.json" ]; then
            printf '%s\0' "$FW_DIR/SM-S921B_XXV/software/manifest.json"
        fi
    } | \
        sort -z | xargs -0 sha1sum | sha1sum | cut -d " " -f 1
}

PREPARE_SCRIPT()
{
    while [ "$#" != 0 ]; do
        if [[ "$1" == "--force" ]] || [[ "$1" == "-f" ]]; then
            FORCE=true
        else
            if [[ "$1" == "-"* ]]; then
                LOGE "Unknown option: $1"
            fi
            PRINT_USAGE
            exit 1
        fi

        shift
    done
}

PRINT_BUILD_OUTCOME()
{
    local EXIT_CODE="$?"
    local END_TIME
    local ESTIMATED

    END_TIME="$(date +%s)"
    ESTIMATED="$((END_TIME - START_TIME))"

    if [ "$EXIT_CODE" != "0" ]; then
        echo -n -e '\n\033[1;31m'"Build failed "
    else
        echo -n -e '\n\033[1;32m'"Build completed "
    fi
    echo -e "in $((ESTIMATED / 3600))hrs $(((ESTIMATED / 60) % 60))min $((ESTIMATED % 60))sec."'\033[0m\n'
}

PRINT_USAGE()
{
    echo "Usage: make_rom [options]" >&2
    echo " -f, --force : Force ROM build" >&2
}

PREPARE_SCRIPT "$@"

if $FORCE; then
    BUILD_ROM=true
else
    if [ -f "$WORK_DIR/.completed" ]; then
        if [[ "$(cat "$WORK_DIR/.completed")" == "$(GET_WORK_DIR_HASH)" ]]; then
            LOGW "No changes have been detected in the build environment"
            BUILD_ROM=false
        else
            LOGW "Changes detected in the build environment"
            BUILD_ROM=true
        fi
    else
        BUILD_ROM=true
    fi
fi

trap 'PRINT_BUILD_OUTCOME' EXIT
trap 'echo' INT
trap 'exit 143' TERM

if $BUILD_ROM; then
    [ -d "$APKTOOL_DIR" ] && rm -rf "$APKTOOL_DIR"
    [ -f "$WORK_DIR/.completed" ] && rm -f "$WORK_DIR/.completed"

    if [ ! -f "$FW_DIR/$SOURCE_FIRMWARE_PATH/.extracted" ] || [ ! -f "$FW_DIR/$TARGET_FIRMWARE_PATH/.extracted" ]; then
        if [ ! -f "$FW_DIR/$SOURCE_FIRMWARE_PATH/.extracted" ] && [ ! -f "$ODIN_DIR/$SOURCE_FIRMWARE_PATH/.downloaded" ]; then
            LOG_STEP_IN true "Downloading required firmwares"
            "$SRC_DIR/scripts/download_fw.sh" donor || exit 1
            LOG_STEP_OUT
        fi
        if [ ! -f "$FW_DIR/$TARGET_FIRMWARE_PATH/.extracted" ] && [ ! -f "$ODIN_DIR/$TARGET_FIRMWARE_PATH/.downloaded" ]; then
            LOG_STEP_IN true "Downloading required firmwares"
            "$SRC_DIR/scripts/download_fw.sh" target || exit 1
            LOG_STEP_OUT
        fi
        LOG_STEP_IN true "Extracting required firmwares"
        "$SRC_DIR/scripts/extract_fw.sh" || exit 1
        LOG_STEP_OUT
    fi

    "$SRC_DIR/scripts/internal/gen_config_file.sh" b5q || exit 1
    set -o allexport
    source "$OUT_DIR/config.sh"
    set +o allexport
    if [[ "$TARGET_SUPER_PARTITION_SIZE" == "none" || "$TARGET_OS_FILE_SYSTEM" == "none" ]]; then
        LOGE "Flip5 partition metadata is required before building."
        exit 1
    fi

    LOG_STEP_IN true "Creating work dir"
    "$SRC_DIR/scripts/internal/create_work_dir.sh" || exit 1
    LOG_STEP_OUT

    "$SRC_DIR/scripts/prepare_kernel.sh" || exit 1

    if [ -d "$SRC_DIR/onigiri/patches" ]; then
        LOG_STEP_IN true "Applying ROM patches"
        "$SRC_DIR/scripts/internal/apply_modules.sh" "$SRC_DIR/onigiri/patches" || exit 1
        LOG_STEP_OUT
    fi
    if [ -d "$SRC_DIR/target/$TARGET_CODENAME/patches" ]; then
        LOG_STEP_IN true "Applying device patches"
        "$SRC_DIR/scripts/internal/apply_modules.sh" "$SRC_DIR/target/$TARGET_CODENAME/patches" || exit 1
        LOG_STEP_OUT
    fi

    if [ -d "$SRC_DIR/onigiri/mods" ]; then
        LOG_STEP_IN true "Applying ROM mods"
        "$SRC_DIR/scripts/internal/apply_modules.sh" "$SRC_DIR/onigiri/mods" || exit 1
        LOG_STEP_OUT
    fi

    if [ -d "$APKTOOL_DIR" ]; then
        LOG_STEP_IN true "Building APKs/JARs"
        APK_BUILD_PIDS=()

        while IFS= read -r f; do
            f="${f/$APKTOOL_DIR\//}"
            PARTITION="$(cut -d "/" -f 1 -s <<< "$f")"
            if [[ "$PARTITION" == "system" ]]; then
                "$SRC_DIR/scripts/apktool.sh" b "system" "$f" &
            else
                "$SRC_DIR/scripts/apktool.sh" b "$PARTITION" "$(cut -d "/" -f 2- -s <<< "$f")" &
            fi
            APK_BUILD_PIDS+=("$!")
        done < <(find "$APKTOOL_DIR" -type d \( -name "*.apk" -o -name "*.jar" \))

        APK_BUILD_STATUS=0
        for PID in "${APK_BUILD_PIDS[@]}"; do
            wait "$PID" || APK_BUILD_STATUS=1
        done
        [ "$APK_BUILD_STATUS" = 0 ] || exit 1

        LOG_STEP_OUT
    fi

    echo -n "$(GET_WORK_DIR_HASH)" > "$WORK_DIR/.completed"
fi

exit 0
