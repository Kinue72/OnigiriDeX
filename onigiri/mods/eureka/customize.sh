EAD_SOURCE="$FW_DIR/SM-S921B_XXV/software"
python3 - "$SRC_DIR/scripts" "$EAD_SOURCE" <<'PY' || return 1
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[1])
from extract_adaptive_display import verify_imported_software

verify_imported_software(Path(sys.argv[2]))
PY

DELETE_FROM_WORK_DIR "system" "system/media/audio/ringtones/SoundTheme/Calm/ACH_The_Voyage.ogg"
DELETE_FROM_WORK_DIR "system" "system/media/audio/ringtones/SoundTheme/Calm/ACH_The_Voyage_acoustic.ogg"
DELETE_FROM_WORK_DIR "system" "system/media/audio/ringtones/SoundTheme/Calm/ACH_The_Voyage_epic.ogg"
DELETE_FROM_WORK_DIR "system" "system/media/audio/ringtones/SoundTheme/Fun/ACH_The_Voyage_EDM.ogg"
DELETE_FROM_WORK_DIR "system" "system/media/audio/ringtones/SoundTheme/Fun/ACH_The_Voyage_RnB.ogg"
DELETE_FROM_WORK_DIR "system" "system/media/audio/ringtones/SoundTheme/Fun/ACH_The_Voyage_jazz_piano.ogg"
DELETE_FROM_WORK_DIR "system" "system/media/audio/ringtones/SoundTheme/Galaxy/ACH_Over_the_Horizon.ogg"
DELETE_FROM_WORK_DIR "system" "system/media/audio/ringtones/SoundTheme/Retro/ACH_The_Voyage_pop_remix.ogg"
DELETE_FROM_WORK_DIR "system" "system/media/audio/ringtones/SoundTheme/Retro/ACH_The_Voyage_smooth_remix.ogg"

ADD_TO_WORK_DIR "$EAD_SOURCE" "system" \
    "system/etc/permissions/privapp-permissions-com.samsung.android.sead.xml" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "e1qzcx" "system" \
    "system/etc/permissions/privapp-permissions-com.samsung.android.wallpaper.live.xml" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "e1qzcx" "system" "system/etc/ringtones_count_list.txt" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "e1qzcx" "system" \
    "system/hidden/INTERNAL_SDCARD/Music/Samsung/Over_the_Horizon.m4a" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "e1qzcx" "system" "system/media/audio" 0 0 755 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "$EAD_SOURCE" "system" "system/priv-app/EnvironmentAdaptiveDisplay" 0 0 755 "u:object_r:system_file:s0"
DECODE_APK "system" "system/priv-app/EnvironmentAdaptiveDisplay/EnvironmentAdaptiveDisplay.apk"
printf '\n/sys/devices/virtual/mdnie/mdnie1 eadRGB 0660 system media_rw\n' >> "$WORK_DIR/vendor/etc/ueventd.rc"
python3 - "$WORK_DIR/vendor/etc/init/hw/init.samsung.display.rc" <<'PY' || return 1
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
anchor = "\tchmod 0660 /sys/class/mdnie/mdnie1/whiteRGB\n"
assert text.count(anchor) == 1
text = text.replace(anchor, anchor +
    "\tchown system media_rw /sys/class/mdnie/mdnie1/eadRGB\n" +
    "\tchmod 0660 /sys/class/mdnie/mdnie1/eadRGB\n")
path.write_text(text)
PY
ADD_TO_WORK_DIR "e1qzcx" "system" "system/priv-app/SpriteWallpaper" 0 0 755 "u:object_r:system_file:s0"
