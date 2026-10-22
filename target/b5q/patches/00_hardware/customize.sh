TARGET_PATH="$FW_DIR/${TARGET_FIRMWARE/\//_}"

for FILE in \
    system/cameradata \
    system/etc/vintf/compatibility_matrix.device.xml \
    system/etc/init/digitalkey_init_ble_tss2.rc; do
    DELETE_FROM_WORK_DIR system "$FILE"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" system "$FILE"
done

for FILE in \
    system/priv-app/AirCommand \
    system/etc/init/digitalkey_init_uwb_tss2.rc \
    system/etc/init/init.system.uwb.rc \
    system/etc/permissions/com.sec.feature.spen_usp_level65.xml \
    system/etc/permissions/com.sec.feature.spen_usp_level75.xml; do
    DELETE_FROM_WORK_DIR system "$FILE"
done

for LIB_DIR in lib lib64; do
    while IFS= read -r FILE; do
        FILE="${FILE#"$WORK_DIR/system/"}"
        if [ ! -f "$TARGET_PATH/system/$FILE" ]; then
            DELETE_FROM_WORK_DIR system "$FILE"
        fi
    done < <(find "$WORK_DIR/system/system/$LIB_DIR" -maxdepth 1 -type f \
        \( -name '*.camera.samsung.so' -o -name '*.arcsoft.so' \) 2>/dev/null)

    while IFS= read -r FILE; do
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE" system "${FILE#"$TARGET_PATH/system/"}"
    done < <(find "$TARGET_PATH/system/system/$LIB_DIR" -maxdepth 1 -type f \
        \( -name '*.camera.samsung.so' -o -name '*.arcsoft.so' -o -name 'libaudio*.so' \
        -o -name '*_legacy.so' -o -name 'libsecaudioinfo.so' \) 2>/dev/null)
done

for FILE in public.libraries-camera.samsung.txt public.libraries-arcsoft.txt; do
    DELETE_FROM_WORK_DIR system "system/etc/$FILE"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" system "system/etc/$FILE"
done

DELETE_FROM_WORK_DIR product overlay/framework-res__q5qxxx__auto_generated_rro_product.apk
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" product overlay/framework-res__b5qxxx__auto_generated_rro_product.apk

FEATURES="$(python3 - "$TARGET_PATH" "$WORK_DIR" <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

relative = "system/system/etc/floating_feature.xml"
target = {e.tag: e.text or "" for e in ET.parse(Path(sys.argv[1]) / relative).getroot()}
current = {e.tag: e.text or "" for e in ET.parse(Path(sys.argv[2]) / relative).getroot()}
prefixes = tuple("SEC_FLOATING_FEATURE_" + name for name in (
    "AUDIO_", "CAMERA_", "BATTERY_", "BIOAUTH_", "LCD_", "NFC_", "SENSOR_",
    "VIBRATOR_", "SPAY_", "SYSTEM_", "SETTINGS_CONFIG_BRAND_NAME",
    "SETTINGS_CONFIG_FCC_ID", "FRAMEWORK_CONFIG_SPEN_", "FRAMEWORK_SUPPORT_TSP_",
    "COMMON_CONFIG_EMBEDDED_SIM_"))
for key in sorted(target.keys() | current.keys()):
    if key.startswith(prefixes) and target.get(key) != current.get(key):
        print(key + "=" + (target.get(key) or "--delete"))
PY
)" || return 1

while IFS='=' read -r KEY VALUE; do
    [ -z "$KEY" ] || SET_FLOATING_FEATURE_CONFIG "$KEY" "$VALUE"
done <<< "$FEATURES"

for PARTITION in system product system_ext; do
    FILE=etc/build.prop
    [ "$PARTITION" != system ] || FILE=system/build.prop

    while IFS='=' read -r KEY VALUE; do
        case "$KEY" in
            ro.product.*|ro.build.*|ro.system.build.*|ro.product.build.*|ro.system_ext.build.*)
                SET_PROP "$PARTITION" "$KEY" "$VALUE"
                ;;
        esac
    done < "$TARGET_PATH/$PARTITION/$FILE"
done

SET_PROP system ro.build.display.id "${TARGET_FIRMWARE_VERSION%%/*}-onigiri-$ROM_VERSION"
SET_PROP system ro.onigiri.version "$ROM_VERSION"
# Settings > Onigiri Software > Software update shows it until the first check. No words in it,
# so it reads the same in every language.
SET_PROP system ro.onigiri.build "$ROM_VERSION ($(date -u -d "@$ROM_BUILD_TIMESTAMP" '+%Y-%m-%d %H:%M UTC'))"
# PackageManager keys its parse cache on a digest of the partition fingerprints, which Onigiri
# keeps stock, and erofs stamps every file with the same time. Without a per-build value here an
# update keeps stale manifests (e.g. "Invalid fragment" crashes). No partition sets "oem" on the
# Flip5 and apps can't see it in Build.getFingerprintedPartitions().
SET_PROP system ro.oem.build.fingerprint "onigiri/b5q/$ROM_VERSION/$ROM_BUILD_TIMESTAMP"
