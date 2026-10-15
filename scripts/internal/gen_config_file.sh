#!/usr/bin/env bash

set -e

if [ "$#" -ne 1 ] || [[ "$1" != "b5q" ]]; then
    echo "Onigiri supports only SM-F731B (b5q)." >&2
    exit 1
fi

source "$SRC_DIR/onigiri/configs/version.sh"
source "$SRC_DIR/target/b5q/config.sh"

FIRMWARE_CONFIG="$(python3 -c '
import json, sys
specs = json.load(open(sys.argv[1]))
values = []
for role in ("target", "donor"):
    spec = specs[role]
    values.extend((spec["model"] + "/" + spec["csc"], spec["version"]))
print(*values)
' "$SRC_DIR/onigiri/configs/firmware.json")"
read -r TARGET_FIRMWARE TARGET_FIRMWARE_VERSION SOURCE_FIRMWARE SOURCE_FIRMWARE_VERSION <<< "$FIRMWARE_CONFIG"
source "$SRC_DIR/onigiri/configs/$TARGET_SINGLE_SYSTEM_IMAGE.sh"

TARGET_ASSERT_MODEL="${TARGET_ASSERT_MODEL[*]}"
TARGET_EXTRA_FIRMWARES=""
SOURCE_EXTRA_FIRMWARES=""
ROM_BUILD_TIMESTAMP="$(date +%s)"
TARGET_OS_FILE_SYSTEM="none"
TARGET_SUPER_PARTITION_SIZE="none"
TARGET_SUPER_GROUP_NAME="none"
TARGET_SUPER_GROUP_SIZE="none"

METADATA="$FW_DIR/SM-F731B_XXV/os_partitions_metadata.txt"
if [ -f "$METADATA" ]; then
    TARGET_SUPER_PARTITION_SIZE="$(sed -n 's/^super_partition_size=//p' "$METADATA")"
    TARGET_SUPER_GROUP_NAME="$(sed -n 's/^super_partition_group=//p' "$METADATA")"
    if ! [[ "$TARGET_SUPER_PARTITION_SIZE" =~ ^[0-9]+$ && "$TARGET_SUPER_GROUP_NAME" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo "Invalid Flip5 super partition metadata." >&2
        exit 1
    fi
    TARGET_SUPER_GROUP_SIZE="$(sed -n "s/^super_${TARGET_SUPER_GROUP_NAME}_group_size=//p" "$METADATA")"
    if ! [[ "$TARGET_SUPER_GROUP_SIZE" =~ ^[0-9]+$ ]] || \
            (( TARGET_SUPER_GROUP_SIZE <= 0 || TARGET_SUPER_GROUP_SIZE >= TARGET_SUPER_PARTITION_SIZE )); then
        echo "Invalid Flip5 super group size." >&2
        exit 1
    fi
    TARGET_OS_FILE_SYSTEM="$(sed -n 's/^system_file_system=//p' "$METADATA")"
    case "$TARGET_OS_FILE_SYSTEM" in
        erofs|ext4|f2fs) ;;
        *)
            echo "Unsupported or missing Flip5 system filesystem metadata." >&2
            exit 1
            ;;
    esac
fi

for PARTITION in BOOT DTBO INIT_BOOT VENDOR_BOOT; do
    SIZE="none"
    METADATA="$FW_DIR/SM-F731B_XXV/${PARTITION,,}.img_metadata.txt"
    if [ -f "$METADATA" ]; then
        SIZE="$(sed -n 's/^partition_size=//p' "$METADATA")"
        if ! [[ "$SIZE" =~ ^[0-9]+$ ]]; then
            echo "Invalid $PARTITION partition size." >&2
            exit 1
        fi
    fi
    printf -v "TARGET_${PARTITION}_PARTITION_SIZE" '%s' "$SIZE"
done

mkdir -p "$OUT_DIR"
CONFIG="$(mktemp "$OUT_DIR/.config.XXXXXX")"
trap 'rm -f "$CONFIG"' EXIT

for VARIABLE in \
    ROM_VERSION ROM_CODENAME ROM_IS_OFFICIAL ROM_BUILD_TIMESTAMP KERNEL_RELEASE \
    SOURCE_FIRMWARE SOURCE_FIRMWARE_VERSION SOURCE_EXTRA_FIRMWARES \
    SOURCE_API_LEVEL SOURCE_PRODUCT_FIRST_API_LEVEL SOURCE_VENDOR_API_LEVEL \
    SOURCE_HAS_SYSTEM_EXT \
    TARGET_NAME TARGET_CODENAME TARGET_ASSERT_MODEL TARGET_FIRMWARE \
    TARGET_FIRMWARE_VERSION TARGET_EXTRA_FIRMWARES TARGET_API_LEVEL \
    TARGET_PRODUCT_FIRST_API_LEVEL TARGET_VENDOR_API_LEVEL \
    TARGET_SINGLE_SYSTEM_IMAGE TARGET_OS_FILE_SYSTEM TARGET_HAS_SYSTEM_EXT \
    TARGET_BOOT_DEVICE_PATH TARGET_KEEP_ORIGINAL_SIGN TARGET_DISABLE_AVB_SIGNING \
    TARGET_INCLUDE_PATCHED_VBMETA TARGET_BOOT_PARTITION_SIZE TARGET_DTBO_PARTITION_SIZE \
    TARGET_INIT_BOOT_PARTITION_SIZE TARGET_VENDOR_BOOT_PARTITION_SIZE \
    TARGET_SUPER_PARTITION_SIZE TARGET_SUPER_GROUP_NAME TARGET_SUPER_GROUP_SIZE \
    $(compgen -A variable | sort | sed -n "/^SOURCE_/p; /^TARGET_/p"); do
    printf '%s=%q\n' "$VARIABLE" "${!VARIABLE}"
done > "$CONFIG"

mv -f "$CONFIG" "$OUT_DIR/config.sh"
