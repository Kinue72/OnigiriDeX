
source "$SRC_DIR/scripts/utils/common_utils.sh"

_GET_PROP_LOCATION()
{
    local FILES
    FILES="$(_GET_PROP_FILES_PATH "$1")"

    if IS_VALID_PARTITION_NAME "$1"; then
        shift
    fi

    _CHECK_NON_EMPTY_PARAM "PROP" "$1" || return 1

    local PROP="$1"
    local MATCHES=()
    while IFS= read -r f; do
        if grep -q "^$PROP=" "$f" 2> /dev/null; then
            MATCHES+=("$f")
        fi
    done <<< "$FILES"

    printf '%s\n' "${MATCHES[@]}"
}

ABORT()
{
    if [ "$1" ]; then
        LOGE "$1"
    fi
    return 1
}

APPLY_PATCH()
{
    _CHECK_NON_EMPTY_PARAM "PARTITION" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "FILE" "$2" || return 1
    _CHECK_NON_EMPTY_PARAM "PATCH" "$3" || return 1

    local PARTITION="$1"
    local FILE="$2"
    local PATCH="$3"

    if ! IS_VALID_PARTITION_NAME "$PARTITION"; then
        LOGE "\"$PARTITION\" is not a valid partition name"
        return 1
    fi

    if [ ! -f "$PATCH" ]; then
        LOGE "File not found: ${PATCH//$SRC_DIR\//}"
        return 1
    fi

    while [[ "${FILE:0:1}" == "/" ]]; do
        FILE="${FILE:1}"
    done

    DECODE_APK "$PARTITION" "$FILE" || return 1

    LOG "- Applying \"$(grep "^Subject:" "$PATCH" | sed "s/.*PATCH] //")\" to /$PARTITION/$FILE"
    EVAL "LC_ALL=C git apply --directory=\"$APKTOOL_DIR/$PARTITION/${FILE//system\//}\" --verbose --unsafe-paths \"$PATCH\"" || return 1
}

DECODE_APK()
{
    _CHECK_NON_EMPTY_PARAM "PARTITION" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "FILE" "$2" || return 1

    local DECODED="$APKTOOL_DIR/$1/${2//system\/}"

    # make_rom.sh decoded this one ahead of the modules: only good if none changed the file since.
    if [ -f "$DECODED.predecoded" ]; then
        sha256sum --status -c "$DECODED.predecoded" || rm -rf "$DECODED"
        rm -f "$DECODED.predecoded"
    fi

    if [ ! -d "$DECODED" ]; then
        "$SRC_DIR/scripts/apktool.sh" d "$1" "$2"
        return $?
    fi

    return 0
}

SET_FLOATING_FEATURE_CONFIG()
{
    _CHECK_NON_EMPTY_PARAM "CONFIG" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "VALUE" "$2" || return 1

    local CONFIG="$1"
    local VALUE="$2"
    local FILE="$WORK_DIR/system/system/etc/floating_feature.xml"

    if [ ! -f "$FILE" ]; then
        LOGE "File not found: ${FILE//$WORK_DIR/}"
        return 1
    fi

    if grep -q "$CONFIG" "$FILE"; then
        if [[ "$VALUE" == "-d" ]] || [[ "$VALUE" == "--delete" ]]; then
            LOG "- Deleting \"$CONFIG\" config in /system/system/etc/floating_feature.xml"
            sed -i "/<$CONFIG>/d" "$FILE"
        else
            LOG "- Replacing \"$CONFIG\" config with \"$VALUE\" in /system/system/etc/floating_feature.xml"
            sed -i "$(sed -n "/<${CONFIG}>/=" "$FILE") c\ \ \ \ <${CONFIG}>${VALUE}</${CONFIG}>" "$FILE"
        fi
    elif [[ "$VALUE" != "-d" ]] && [[ "$VALUE" != "--delete" ]]; then
        LOG "- Adding \"$CONFIG\" config with \"$VALUE\" in /system/system/etc/floating_feature.xml"
        sed -i "/<\/SecFloatingFeatureSet>/d" "$FILE"
        echo "    <${CONFIG}>${VALUE}</${CONFIG}>" >> "$FILE"
        echo "</SecFloatingFeatureSet>" >> "$FILE"
    fi

    return 0
}

SET_PROP()
{
    _CHECK_NON_EMPTY_PARAM "PARTITION" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "PROP" "$2" || return 1

    local PARTITION="$1"
    local PROP="$2"
    local VALUE="$3"

    if ! IS_VALID_PARTITION_NAME "$PARTITION"; then
        LOGE "\"$PARTITION\" is not a valid partition name"
        return 1
    fi

    if [ "$(GET_PROP "$PARTITION" "$PROP")" ]; then
        local FILES
        FILES="$(_GET_PROP_LOCATION "$PARTITION" "$PROP")"

        while IFS= read -r f; do
            if [[ "$VALUE" == "-d" ]] || [[ "$VALUE" == "--delete" ]]; then
                LOG "- Deleting \"$PROP\" prop in ${f//$WORK_DIR/}"
                sed -i "/^$PROP/d" "$f"
            else
                LOG "- Replacing \"$PROP\" prop with \"$VALUE\" in ${f//$WORK_DIR/}"

                local LINES
                LINES="$(sed -n "/^${PROP}\b/=" "$f")"
                for l in $LINES; do
                    sed -i "$l c${PROP}=${VALUE}" "$f"
                done
            fi
        done <<< "$FILES"
    elif [[ "$VALUE" != "-d" ]] && [[ "$VALUE" != "--delete" ]]; then
        local FILE

        case "$PARTITION" in
            "system")
                FILE="$WORK_DIR/system/system/build.prop"
                ;;
            "system_ext")
                FILE="$WORK_DIR/system_ext/etc/build.prop"
                ;;
            "system_dlkm")
                FILE="$WORK_DIR/system_dlkm/etc/build.prop"
                ;;
            "vendor")
                FILE="$WORK_DIR/vendor/build.prop"
                ;;
            "vendor_dlkm")
                FILE="$WORK_DIR/vendor_dlkm/etc/build.prop"
                ;;
            "odm_dlkm")
                FILE="$WORK_DIR/vendor/odm_dlkm/etc/build.prop"
                ;;
            "odm")
                FILE="$WORK_DIR/odm/etc/build.prop"
                ;;
            "product")
                FILE="$WORK_DIR/product/etc/build.prop"
                ;;
        esac

        if [ ! -f "$FILE" ]; then
            LOGW "File not found: ${FILE//$WORK_DIR/}"
            return 0
        fi

        LOG "- Adding \"$PROP\" prop with \"$VALUE\" in ${FILE//$WORK_DIR/}"
        echo "$PROP=$VALUE" >> "$FILE"
    fi

    return 0
}
