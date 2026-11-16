if [ ! -f "$SRC_DIR/security/onigiri_platform.x509.pem" ]; then
    ABORT "File not found: security/onigiri_platform.x509.pem"
fi

APPLY_PATCH "system" "system/framework/services.jar" "$SRC_DIR/onigiri/patches/signature/services.jar/0001-Allow-custom-platform-signature.patch"

CERT_SIGNATURE="$(sed "/CERTIFICATE/d" "$SRC_DIR/security/onigiri_platform.x509.pem" | tr -d "\n" | base64 -d | xxd -p -c 0)"
EVAL "sed -i \"s/CONFIG_CUSTOM_PLATFORM_SIGNATURE/$CERT_SIGNATURE/g\" \"$APKTOOL_DIR/system/framework/services.jar/smali_classes2/com/android/server/pm/InstallPackageHelper.smali\""

unset CERT_SIGNATURE
