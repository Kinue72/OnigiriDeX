
source "$SRC_DIR/scripts/utils/build_utils.sh" || return 1

EXTRACT_EROFS_PARTITION()
(
    local IMAGE="$1"
    local OUTPUT="$2"
    local PARTITION
    local STAGE

    PARTITION="$(basename "${IMAGE%.img}")"
    IS_VALID_PARTITION_NAME "$PARTITION" || exit 1
    if [ -e "$OUTPUT/$PARTITION" ] || [ -L "$OUTPUT/$PARTITION" ]; then
        LOGE "Partition output already exists: $OUTPUT/$PARTITION"
        exit 1
    fi

    STAGE="$(mktemp -d)" || exit 1
    trap 'rm -rf "$STAGE"' EXIT
    if ! extract.erofs -i "$IMAGE" -x -o "$STAGE" -T"$(nproc)"; then
        LOGE "Failed to extract EROFS partition: $PARTITION"
        exit 1
    fi

    local FS_CONFIG="$STAGE/config/${PARTITION}_fs_config"
    local FILE_CONTEXTS="$STAGE/config/${PARTITION}_file_contexts"
    if [ ! -s "$FS_CONFIG" ] || [ ! -s "$FILE_CONTEXTS" ]; then
        LOGE "EROFS extraction did not preserve Android metadata: $PARTITION"
        exit 1
    fi

    if [[ "$PARTITION" == "system" ]] && [ -d "$STAGE/system/system" ]; then
        sed -i -e 's|^system/||' -e 's|^/ | |' "$FS_CONFIG" || exit 1
        sed -i -e '/^\/system /d' -e 's|^/system/|/|' "$FILE_CONTEXTS" || exit 1
    fi
    sort -u -o "$FS_CONFIG" "$FS_CONFIG" || exit 1
    sort -u -o "$FILE_CONTEXTS" "$FILE_CONTEXTS" || exit 1

    mkdir -p "$OUTPUT" || exit 1
    mv -T "$STAGE/$PARTITION" "$OUTPUT/$PARTITION" || exit 1
    mv "$FS_CONFIG" "$OUTPUT/fs_config-$PARTITION" || exit 1
    mv "$FILE_CONTEXTS" "$OUTPUT/file_context-$PARTITION" || exit 1
)

EXTRACT_FILE_FROM_TAR()
{
    _CHECK_NON_EMPTY_PARAM "MODEL" "$MODEL" || return 1
    _CHECK_NON_EMPTY_PARAM "CSC" "$CSC" || return 1
    _CHECK_NON_EMPTY_PARAM "TAR" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "FILE" "$2" || return 1

    local TAR="$1"
    local FILE="$2"

    if [ ! -f "$TAR" ]; then
        LOGE "File not found: ${TAR//$SRC_DIR\//}"
        return 1
    fi

    [ -f "$FW_DIR/${MODEL}_${CSC}/$FILE" ] && rm -rf "$FW_DIR/${MODEL}_${CSC}/$FILE"
    [ -f "$FW_DIR/${MODEL}_${CSC}/$FILE.ext4" ] && rm -rf "$FW_DIR/${MODEL}_${CSC}/$FILE.ext4"
    [ -f "$FW_DIR/${MODEL}_${CSC}/$FILE.lz4" ] && rm -rf "$FW_DIR/${MODEL}_${CSC}/$FILE.lz4"

    if FILE_EXISTS_IN_TAR "$TAR" "$FILE"; then
        LOG "- Extracting $FILE..."
        EVAL "tar xf \"$TAR\" -C \"$FW_DIR/${MODEL}_${CSC}\" \"$FILE\"" || return 1
    elif FILE_EXISTS_IN_TAR "$TAR" "$FILE.ext4"; then
        LOG "- Extracting $FILE.ext4..."
        EVAL "tar xf \"$TAR\" -C \"$FW_DIR/${MODEL}_${CSC}\" \"$FILE.ext4\"" || return 1
        EVAL "mv -f \"$FW_DIR/${MODEL}_${CSC}/$FILE.ext4\" \"$FW_DIR/${MODEL}_${CSC}/$FILE\"" || return 1
    elif FILE_EXISTS_IN_TAR "$TAR" "$FILE.lz4"; then
        LOG "- Extracting $FILE.lz4..."
        EVAL "tar xf \"$TAR\" -C \"$FW_DIR/${MODEL}_${CSC}\" \"$FILE.lz4\"" || return 1
        LOG "- Decompressing $FILE.lz4..."
        EVAL "lz4 -d --rm \"$FW_DIR/${MODEL}_${CSC}/$FILE.lz4\" \"$FW_DIR/${MODEL}_${CSC}/$FILE\"" || return 1
    fi

    return 0
}

FILE_EXISTS_IN_TAR()
{
    _CHECK_NON_EMPTY_PARAM "TAR" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "FILE" "$2" || return 1

    tar tf "$1" "$2" &> /dev/null
    return $?
}

GET_REQUIRED_FIRMWARE()
{
    python3 -c '
import json, sys
specs = json.load(open(sys.argv[1]))
for spec in specs.values():
    if (spec["model"], spec["csc"]) == (sys.argv[2], sys.argv[3]):
        print(spec["version"])
        break
else:
    sys.exit("Unsupported firmware model/CSC")
' "$SRC_DIR/onigiri/configs/firmware.json" "$1" "$2"
}

PARSE_FIRMWARE_STRING()
{
    if ! [[ "${1:-}" =~ ^(SM-F731B|SM-F946B)/XXV$ ]]; then
        LOGE "Use SM-F731B/XXV or the SM-F946B/XXV donor."
        return 1
    fi

    IFS=/ read -r MODEL CSC <<< "$1"
    GET_REQUIRED_FIRMWARE "$MODEL" "$CSC" > /dev/null
}

UNSPARSE_IMAGE()
{
    _CHECK_NON_EMPTY_PARAM "FILE" "$1" || exit 1

    local FILE="$1"
    local OUTPUT_PATH="$2"
    local REPLACE=false

    if [ ! -f "$FILE" ]; then
        LOGE "File not found: ${FILE//$SRC_DIR\//}"
        return 1
    fi

    if ! IS_SPARSE_IMAGE "$FILE"; then
        LOGW "Not a Android sparse image: ${FILE//$SRC_DIR\//}"
        return 0
    fi

    if [ ! "$OUTPUT_PATH" ]; then
        OUTPUT_PATH="$(dirname "$FILE")/unsparse_$(basename "$FILE")"
        REPLACE=true
    fi

    LOG "- Unsparsing $(basename "$FILE")..."

    EVAL "simg2img \"$FILE\" \"$OUTPUT_PATH\"" || return 1
    if $REPLACE; then
        mv -f "$OUTPUT_PATH" "$FILE"
    fi

    return 0
}
