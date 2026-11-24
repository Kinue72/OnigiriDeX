#!/usr/bin/env bash
# Writes out/config.sh, the values every build script shares: versions, the firmware pins from
# onigiri/configs/firmware.json and, once the model's firmware is extracted, its product name and
# super partition layout ("none" until then). buildenv.sh runs it, and make_rom.sh again after
# extracting.

set -e

if [ "$#" -ne 0 ] || [ -z "${TARGET_MODEL:-}" ]; then
    echo "Usage: TARGET_MODEL=<model> gen_config_file.sh (buildenv.sh sets it)" >&2
    exit 1
fi

source "$SRC_DIR/onigiri/configs/version.sh"
TARGET_CODENAME="b5q"

FIRMWARE_CONFIG="$(python3 -c '
import json, sys
specs = json.load(open(sys.argv[1]))
values = []
for spec in (specs["targets"][sys.argv[2]], specs["donor"]):
    values.extend((spec["model"] + "/" + spec["csc"], spec["version"]))
print(*values)
' "$SRC_DIR/onigiri/configs/firmware.json" "$TARGET_MODEL")"
read -r TARGET_FIRMWARE TARGET_FIRMWARE_VERSION SOURCE_FIRMWARE SOURCE_FIRMWARE_VERSION <<< "$FIRMWARE_CONFIG"

FIRMWARE_FOLDER="$FW_DIR/${TARGET_FIRMWARE/\//_}"
# Samsung's product name for this model (b5qxxx, b5qksx, b5qzhx), once its firmware is extracted.
TARGET_PRODUCT_NAME="$(sed -n 's/^ro.product.vendor.name=//p' "$FIRMWARE_FOLDER/vendor/build.prop" 2> /dev/null || true)"
TARGET_PRODUCT_NAME="${TARGET_PRODUCT_NAME:-none}"
ROM_BUILD_TIMESTAMP="$(date +%s)"
TARGET_OS_FILE_SYSTEM="none"
TARGET_SUPER_PARTITION_SIZE="none"
TARGET_SUPER_GROUP_NAME="none"
TARGET_SUPER_GROUP_SIZE="none"

METADATA="$FIRMWARE_FOLDER/os_partitions_metadata.txt"
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

mkdir -p "$OUT_DIR"
CONFIG="$(mktemp "$OUT_DIR/.config.XXXXXX")"
trap 'rm -f "$CONFIG"' EXIT

for VARIABLE in \
    ROM_VERSION ROM_CODENAME ROM_BUILD_TIMESTAMP KERNEL_RELEASE \
    SOURCE_FIRMWARE SOURCE_FIRMWARE_VERSION \
    TARGET_CODENAME TARGET_MODEL TARGET_PRODUCT_NAME TARGET_FIRMWARE TARGET_FIRMWARE_VERSION \
    TARGET_OS_FILE_SYSTEM TARGET_SUPER_PARTITION_SIZE TARGET_SUPER_GROUP_NAME TARGET_SUPER_GROUP_SIZE; do
    printf '%s=%q\n' "$VARIABLE" "${!VARIABLE}"
done > "$CONFIG"

mv -f "$CONFIG" "$OUT_DIR/config.sh"
