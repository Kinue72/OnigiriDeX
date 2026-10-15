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
