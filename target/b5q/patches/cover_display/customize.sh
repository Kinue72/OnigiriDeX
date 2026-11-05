SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_FRAMEWORK_SUPPORT_FOLDABLE_TYPE_FOLD" "TRUE"
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_FRAMEWORK_SUPPORT_FOLDABLE_TYPE_FLIP" --delete
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_FRAMEWORK_SUPPORT_LARGE_COVER_SCREEN" --delete
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_CONFIG_HFR_MODE" "0"
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_CONFIG_HFR_DEFAULT_REFRESH_RATE" "60"
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE" "60"
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_CONFIG_SUB_HFR_MODE" "0"
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_CONFIG_SUB_HFR_SUPPORTED_REFRESH_RATE" "60"

# Quick Shot launches on display 1, which is the disabled inner panel in this ROM.
sed -i '/name="SUPPORT_QUICK_SHOT"/s/value="true"/value="false"/' \
    "$WORK_DIR/system/system/cameradata/camera-feature.xml"

python3 "$MODPATH/native/patch_camera_hal.py" \
    "$WORK_DIR/vendor/lib64/hw/camera.qcom.so" || ABORT "Cannot patch the camera HAL orientation"

# The cover's resource overlay is named after the model's product (b5qxxx, b5qksx).
for PATCH in "$MODPATH"/product_overlay/*.patch; do
    APPLY_PATCH "product" "overlay/framework-res__${TARGET_PRODUCT_NAME}__auto_generated_rro_product.apk" "$PATCH" || \
        ABORT "Cannot patch the cover resource overlay"
done
