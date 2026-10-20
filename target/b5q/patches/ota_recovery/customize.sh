# Stock recovery only installs packages signed with a key in its otacerts.zip. Swap Samsung's
# keys for the Onigiri OTA key, so it installs Onigiri OTAs (scripts/make_ota.sh) and nothing else.
# Also turn a full CSC flash into a factory reset (see recovery/onigiri-csc-wipe.sh).
RECOVERY="$WORK_DIR/kernel/recovery.img"
if [ ! -f "$RECOVERY" ]; then
    LOGE "Stock recovery.img is missing: re-extract the target firmware with \"extract_fw --force\""
    exit 1
fi

mkdir -p "$TMP_DIR"
STAGE="$(mktemp -d "$TMP_DIR/recovery.XXXXXX")"
cp "$SRC_DIR/security/onigiri_ota.x509.pem" "$STAGE/"
EVAL "cd \"$STAGE\" && magiskboot unpack \"$RECOVERY\" && zip -q -X otacerts.zip onigiri_ota.x509.pem && \
    magiskboot cpio ramdisk.cpio \"add 0644 system/etc/security/otacerts.zip otacerts.zip\" \
        \"add 0644 system/etc/init/onigiri-csc-wipe.rc $MODPATH/recovery/onigiri-csc-wipe.rc\" \
        \"add 0755 system/bin/onigiri-csc-wipe.sh $MODPATH/recovery/onigiri-csc-wipe.sh\" && \
    magiskboot repack \"$RECOVERY\" recovery.img" || exit 1
mv -f "$STAGE/recovery.img" "$RECOVERY"
rm -rf "$STAGE"
