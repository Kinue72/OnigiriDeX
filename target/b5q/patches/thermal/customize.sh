DECODE_APK system system/priv-app/SamsungDeviceHealthManagerService/SamsungDeviceHealthManagerService.apk

python3 "$SRC_DIR/scripts/prepare_cooler_policy.py" \
    "$APKTOOL_DIR/system/priv-app/SamsungDeviceHealthManagerService/SamsungDeviceHealthManagerService.apk/res/raw" \
    "$APKTOOL_DIR/system/priv-app/SamsungDeviceHealthManagerService/SamsungDeviceHealthManagerService.apk/assets/onigiri-cooler.xml" \
    || ABORT "Cannot build the High performance thermal profile"
