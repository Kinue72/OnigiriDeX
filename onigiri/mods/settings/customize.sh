SET_PROP "system" "ro.onigiri.version" "$ROM_VERSION"
SET_PROP "system" "ro.onigiri.codename" "$ROM_CODENAME"

DECODE_APK "system" "system/priv-app/SecSettings/SecSettings.apk"

# Run the charger hook in Samsung's lpm domain, which can already read the /cache marker and
# battery nodes, run toybox and set sys.powerctl. It still needs sh as an entrypoint and
# /dev/kmsg for the hook's log. Types must exist: init compiles this at boot.
for AUTOBOOT_RULE in \
    '(allow lpm_33_0 shell_exec_33_0 (file (entrypoint)))' \
    '(allow lpm_33_0 kmsg_device_33_0 (chr_file (getattr open write)))'; do
    if ! grep -qFx "$AUTOBOOT_RULE" "$WORK_DIR/vendor/etc/selinux/vendor_sepolicy.cil"; then
        printf '%s\n' "$AUTOBOOT_RULE" >> "$WORK_DIR/vendor/etc/selinux/vendor_sepolicy.cil"
    fi
done
