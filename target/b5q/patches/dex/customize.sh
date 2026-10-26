for FILE in \
    system/priv-app/KnoxDesktopLauncher/KnoxDesktopLauncher.apk \
    system/priv-app/DesktopModeUiService/DesktopModeUiService.apk \
    system/priv-app/DesktopSystemUI/DesktopSystemUI.apk \
    system/etc/permissions/privapp-permissions-com.sec.android.app.desktoplauncher.xml \
    system/etc/permissions/privapp-permissions-com.sec.android.desktopmode.uiservice.xml \
    system/etc/permissions/privapp-permissions-com.sec.android.dexsystemui.xml; do
    if [ ! -s "$WORK_DIR/system/$FILE" ]; then
        ABORT "Missing Fold5 DeX component: $FILE"
    fi
done

SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_CONFIG_DEX_MODE" "dual,wireless"
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_SUPPORT_KNOX_DESKTOP" "TRUE"

# Reuse the display sysfs label that already permits init and system_server writes and Settings
# reads.
for PARAM in secdp_high_refresh secdp_prefer_high_refresh secdp_ddc_brightness; do
    DEX_LABEL="(genfscon sysfs \"/module/msm_drm/parameters/$PARAM\" (u object_r sysfs_ss_writable ((s0) (s0))))"
    if ! grep -qFx "$DEX_LABEL" "$WORK_DIR/vendor/etc/selinux/vendor_sepolicy.cil"; then
        printf '%s\n' "$DEX_LABEL" >> "$WORK_DIR/vendor/etc/selinux/vendor_sepolicy.cil"
    fi
done
# init hands secdp_ddc_brightness to system_server's uid (onigiri-dex-display.rc).
DEX_RULE='(allow init_33_0 sysfs_ss_writable (file (setattr)))'
if ! grep -qFx "$DEX_RULE" "$WORK_DIR/vendor/etc/selinux/vendor_sepolicy.cil"; then
    printf '%s\n' "$DEX_RULE" >> "$WORK_DIR/vendor/etc/selinux/vendor_sepolicy.cil"
fi

python3 "$MODPATH/native/patch_surfaceflinger.py" \
    "$WORK_DIR/system/system/bin/surfaceflinger" \
    "$SRC_DIR/external/kernel/kernel_platform/prebuilts/clang/host/linux-x86/clang-r614150/bin" || ABORT "Cannot patch the DeX compositor"
