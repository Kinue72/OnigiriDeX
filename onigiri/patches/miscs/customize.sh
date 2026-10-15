TARGET_FIRMWARE_PATH="$FW_DIR/${TARGET_FIRMWARE//\//_}"


# Fix portrait mode
if [[ -f "$TARGET_FIRMWARE_PATH/vendor/lib64/libDualCamBokehCapture.camera.samsung.so" ]]; then
    if grep -q "ro.build.flavor" "$TARGET_FIRMWARE_PATH/vendor/lib64/libDualCamBokehCapture.camera.samsung.so"; then
        SET_PROP "system" "ro.build.flavor" "$(GET_PROP "$TARGET_FIRMWARE_PATH/system/system/build.prop" "ro.build.flavor")"
    elif grep -qF "ro.product.name" "$TARGET_FIRMWARE_PATH/vendor/lib64/libDualCamBokehCapture.camera.samsung.so"; then
        CAMERA_PROPERTY="ro.onigiri.name"
        [ "${#CAMERA_PROPERTY}" -eq 15 ] || return 1
        for LIB_DIR in lib lib64; do
            for LIB in libDualCamBokehCapture.camera.samsung.so liblivefocus_capture_engine.so liblivefocus_preview_engine.so; do
                LC_ALL=C sed -i "s/ro\\.product\\.name\\x00/${CAMERA_PROPERTY}\\x00/g" "$WORK_DIR/vendor/$LIB_DIR/$LIB" || return 1
            done
        done
        echo -e "\n$CAMERA_PROPERTY u:object_r:build_prop:s0 exact string" >> "$WORK_DIR/system/system/etc/selinux/plat_property_contexts"
        SET_PROP "system" "$CAMERA_PROPERTY" "$(GET_PROP "$TARGET_FIRMWARE_PATH/system/system/build.prop" "ro.product.system.name")"
    fi
fi

# Enable camera cutout protection
if [[ "$SOURCE_SUPPORT_CUTOUT_PROTECTION" != "$TARGET_SUPPORT_CUTOUT_PROTECTION" ]]; then
    DECODE_APK "system_ext" "priv-app/SystemUI/SystemUI.apk"

    FTP="$APKTOOL_DIR/system_ext/priv-app/SystemUI/SystemUI.apk/res/values/bools.xml"
    R="\ \ \ \ <bool name=\"config_enableDisplayCutoutProtection\">$TARGET_SUPPORT_CUTOUT_PROTECTION</bool>"

    sed -i "$(sed -n "/config_enableDisplayCutoutProtection/=" "$FTP") c$R" "$FTP"
fi
