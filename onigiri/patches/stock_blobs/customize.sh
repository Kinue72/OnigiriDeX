SOURCE_FIRMWARE_PATH="$FW_DIR/${SOURCE_FIRMWARE//\//_}"
TARGET_FIRMWARE_PATH="$FW_DIR/${TARGET_FIRMWARE//\//_}"

ADD_TO_WORK_DIR "$TARGET_FIRMWARE_PATH" "system" "system/bin/lpm" \
    0 2000 755 "u:object_r:lpm_exec:s0"

echo "Replacing boot animation blobs with stock"
for blob in \
    system/media/bootsamsung.qmg \
    system/media/bootsamsungloop.qmg \
    system/media/shutdown.qmg \
    system/media/sub_bootsamsung.qmg \
    system/media/sub_bootsamsungloop.qmg \
    system/media/sub_shutdown.qmg \
    system/media/lcd_density.txt \
    system/media/sub_lcd_density.txt; do
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE_PATH" "system" "$blob" 0 0 644 "u:object_r:system_file:s0"
done

while IFS= read -r blob; do
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE_PATH" "system" "${blob#"$TARGET_FIRMWARE_PATH/system/"}" \
        0 0 644 "u:object_r:system_file:s0"
done < <(find "$TARGET_FIRMWARE_PATH/system/system/media" -maxdepth 1 -type f -name '*.spi' | sort)

echo "Replacing saiv blobs with stock"
if [ -d "$TARGET_FIRMWARE_PATH/system/system/etc/saiv" ]; then
    BLOBS_LIST="
    system/etc/saiv/image_understanding/db/aic_classifier/aic_classifier_cnn.info
    system/etc/saiv/image_understanding/db/aic_detector/aic_detector_cnn.info
    "
    for blob in $BLOBS_LIST
    do
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE_PATH" "system" "$blob" 0 0 644 "u:object_r:system_file:s0"
    done
else
    DELETE_FROM_WORK_DIR "system" "system/etc/saiv"
fi
DELETE_FROM_WORK_DIR "system" "system/saiv"
ADD_TO_WORK_DIR "$TARGET_FIRMWARE_PATH" "system" "system/saiv" 0 0 755 "u:object_r:system_file:s0"
DELETE_FROM_WORK_DIR "system" "system/saiv/textrecognition"
ADD_TO_WORK_DIR "$SOURCE_FIRMWARE_PATH" "system" "system/saiv/textrecognition" 0 0 755 "u:object_r:system_file:s0"

echo "Replacing cameradata blobs with stock"
DELETE_FROM_WORK_DIR "system" "system/cameradata"
ADD_TO_WORK_DIR "$TARGET_FIRMWARE_PATH" "system" "system/cameradata" 0 0 755 "u:object_r:system_file:s0"

if [ -f "$TARGET_FIRMWARE_PATH/system/system/usr/share/alsa/alsa.conf" ]; then
    echo "Add stock alsa.conf"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE_PATH" "system" "system/usr/share/alsa/alsa.conf" 0 0 644 "u:object_r:system_file:s0"
else
    DELETE_FROM_WORK_DIR "system" "system/usr/share/alsa"
fi
