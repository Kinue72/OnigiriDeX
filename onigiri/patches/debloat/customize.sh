# Dexpreopt
find "$WORK_DIR/product" -type d -name "oat" -print0 | xargs -0 -I "{}" -P "$(nproc)" \
    bash -c 'source "$SRC_DIR/scripts/utils/module_utils.sh"; DELETE_FROM_WORK_DIR "product" "${1//$WORK_DIR\/product\//}"' "bash" "{}"
find "$WORK_DIR/system" -type d -name "oat" -print0 | xargs -0 -I "{}" -P "$(nproc)" \
    bash -c 'source "$SRC_DIR/scripts/utils/module_utils.sh"; DELETE_FROM_WORK_DIR "system" "${1//$WORK_DIR\/system\//}"' "bash" "{}"
DELETE_FROM_WORK_DIR "system" "system/etc/boot-image.bprof"
DELETE_FROM_WORK_DIR "system" "system/etc/boot-image.prof"
DELETE_FROM_WORK_DIR "system" "system/framework/arm"
DELETE_FROM_WORK_DIR "system" "system/framework/arm64"
find "$WORK_DIR/system/system/framework" -type f -name "*.vdex" -print0 | xargs -0 -I "{}" -P "$(nproc)" \
    bash -c 'source "$SRC_DIR/scripts/utils/module_utils.sh"; DELETE_FROM_WORK_DIR "system" "${1//$WORK_DIR\/system\//}"' "bash" "{}"
if $TARGET_HAS_SYSTEM_EXT; then
    find "$WORK_DIR/system_ext" -type d -name "oat" -print0 | xargs -0 -I "{}" -P "$(nproc)" \
        bash -c 'source "$SRC_DIR/scripts/utils/module_utils.sh"; DELETE_FROM_WORK_DIR "system_ext" "${1//$WORK_DIR\/system_ext\//}"' "bash" "{}"
fi

# ROM & device-specific debloat list
[ -f "$SRC_DIR/onigiri/debloat.sh" ] && source "$SRC_DIR/onigiri/debloat.sh"
[ -f "$SRC_DIR/target/$TARGET_CODENAME/debloat.sh" ] && source "$SRC_DIR/target/$TARGET_CODENAME/debloat.sh"

ODM_DEBLOAT="$(sed "/^$/d" <<< "$ODM_DEBLOAT" | sort)"
PRODUCT_DEBLOAT="$(sed "/^$/d" <<< "$PRODUCT_DEBLOAT" | sort)"
SYSTEM_DEBLOAT="$(sed "/^$/d" <<< "$SYSTEM_DEBLOAT" | sort)"
SYSTEM_EXT_DEBLOAT="$(sed "/^$/d" <<< "$SYSTEM_EXT_DEBLOAT" | sort)"
VENDOR_DEBLOAT="$(sed "/^$/d" <<< "$VENDOR_DEBLOAT" | sort)"

[ "$ODM_DEBLOAT" ] && xargs -I "{}" -P "$(nproc)" \
    bash -c 'source "$SRC_DIR/scripts/utils/module_utils.sh"; DELETE_FROM_WORK_DIR "odm" "$1"' "bash" "{}" \
    <<< "$ODM_DEBLOAT"
[ "$PRODUCT_DEBLOAT" ] && xargs -I "{}" -P "$(nproc)" \
    bash -c 'source "$SRC_DIR/scripts/utils/module_utils.sh"; DELETE_FROM_WORK_DIR "product" "$1"' "bash" "{}" \
    <<< "$PRODUCT_DEBLOAT"
[ "$SYSTEM_DEBLOAT" ] && xargs -I "{}" -P "$(nproc)" \
    bash -c 'source "$SRC_DIR/scripts/utils/module_utils.sh"; DELETE_FROM_WORK_DIR "system" "$1"' "bash" "{}" \
    <<< "$SYSTEM_DEBLOAT"
[ "$SYSTEM_EXT_DEBLOAT" ] && xargs -I "{}" -P "$(nproc)" \
    bash -c 'source "$SRC_DIR/scripts/utils/module_utils.sh"; DELETE_FROM_WORK_DIR "system_ext" "$1"' "bash" "{}" \
    <<< "$SYSTEM_EXT_DEBLOAT"
[ "$VENDOR_DEBLOAT" ] && xargs -I "{}" -P "$(nproc)" \
    bash -c 'source "$SRC_DIR/scripts/utils/module_utils.sh"; DELETE_FROM_WORK_DIR "vendor" "$1"' "bash" "{}" \
    <<< "$VENDOR_DEBLOAT"

return 0
