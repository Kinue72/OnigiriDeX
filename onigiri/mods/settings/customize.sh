SET_PROP "system" "ro.onigiri.version" "$ROM_VERSION"
SET_PROP "system" "ro.onigiri.codename" "$ROM_CODENAME"

DECODE_APK "system" "system/priv-app/SecSettings/SecSettings.apk"

# Run the charger hook with Samsung's existing battery/cache/reboot permissions.
AUTOBOOT_LABEL='(allow lpm_33_0 shell_exec_33_0 (file (entrypoint)))'
if ! grep -qFx "$AUTOBOOT_LABEL" "$WORK_DIR/vendor/etc/selinux/vendor_sepolicy.cil"; then
    printf '%s\n' "$AUTOBOOT_LABEL" >> "$WORK_DIR/vendor/etc/selinux/vendor_sepolicy.cil"
fi
