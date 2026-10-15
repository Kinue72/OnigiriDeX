
source "$SRC_DIR/scripts/utils/common_utils.sh"

GET_DISK_USAGE()
{
    _CHECK_NON_EMPTY_PARAM "FILE" "$1" || return 1

    local FILE="$1"

    if [ ! -e "$FILE" ]; then
        LOGE "File not found: ${FILE//$SRC_DIR\//}"
        return 1
    fi

    local SIZE
    SIZE="$(du -b -k -s "$FILE" | cut -f 1)"

    bc -l <<< "$SIZE * 1024"
}

GET_IMAGE_SIZE()
{
    _CHECK_NON_EMPTY_PARAM "FILE" "$1" || return 1

    local FILE="$1"

    if [ ! -f "$FILE" ]; then
        LOGE "File not found: ${FILE//$SRC_DIR\//}"
        return 1
    fi

    if IS_SPARSE_IMAGE "$FILE"; then
        local BLOCK_SIZE
        local BLOCKS
        BLOCK_SIZE="$(printf "%d" "0x$(READ_BYTES_AT "$FILE" "12" "4")")"
        BLOCKS="$(printf "%d" "0x$(READ_BYTES_AT "$FILE" "16" "4")")"

        bc -l <<< "$BLOCKS * $BLOCK_SIZE"
    else
        GET_DISK_USAGE "$FILE"
    fi
}

READ_BYTES_AT()
{
    _CHECK_NON_EMPTY_PARAM "FILE" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "OFFSET" "$2" || return 1
    _CHECK_NON_EMPTY_PARAM "BYTES" "$3" || return 1

    local FILE="$1"
    local OFFSET="$2"
    local BYTES="$3"

    if [ ! -f "$FILE" ]; then
        LOGE "File not found: ${FILE//$SRC_DIR\//}"
        return 1
    fi

    local FILE_SIZE
    FILE_SIZE="$(wc -c "$FILE" | cut -d " " -f 1)"
    if ! [[ "$OFFSET" =~ ^[+-]?[0-9]+$ ]] || [[ "$OFFSET" -gt "$FILE_SIZE" ]]; then
        LOGE "Offset value not valid: $OFFSET"
        return 1
    fi
    if ! [[ "$BYTES" =~ ^[+-]?[0-9]+$ ]] || [[ "$BYTES" -gt "$((FILE_SIZE - OFFSET))" ]]; then
        LOGE "Bytes value not valid: $BYTES"
        return 1
    fi

    local READ
    local LENGTH
    READ="$(xxd -p -l "$BYTES" --skip "$OFFSET" "$FILE")"
    LENGTH="${#READ}"

    while [[ "$LENGTH" -gt 0 ]]; do
        echo -n "${READ:$LENGTH-2:2}"
        LENGTH="$((LENGTH - 2))"
    done
    echo ""
}

CHECK_BUILD_DEPENDENCIES()
{
    local DEPENDENCIES=(
        "awk" "basename" "bc" "brotli" "cat" "clang" "cmake"
        "cp" "curl" "cut" "dd" "debugfs" "dirname" "du"
        "file" "fmt" "getfattr" "git" "grep" "head" "java" "ln"
        "lz4" "make" "md5sum" "mkdir" "mount" "mv" "pcre2test"
        "perl" "protoc" "python3" "rm" "sed" "sha1sum" "sort"
        "stat" "tail" "tar" "touch" "tr" "truncate" "umount"
        "unzip" "wc" "whoami" "xargs" "xxd" "zip" "zstd"
    )
    local MISSING=()
    for d in "${DEPENDENCIES[@]}"; do
        if ! type "$d" &> /dev/null; then
            MISSING+=("$d")
        fi
    done
    if [ "${#MISSING[@]}" -ne 0 ]; then
        echo -e '\033[1;31m'"The following dependencies are missing from your system:"'\033[0;31m' >&2
        printf '%s ' "${MISSING[@]}" >&2
        echo -e '\033[0m' >&2
        return 1
    fi
    unset DEPENDENCIES MISSING

    if ! "$SRC_DIR/external/make.sh" --check-tools; then
        LOG_STEP_IN true "Building required tools..."
        "$SRC_DIR/external/make.sh" || return 1
        LOG_STEP_OUT
    fi
}
