#!/usr/bin/env bash

source "$SRC_DIR/scripts/utils/build_utils.sh" || exit 1
CHECK_BUILD_DEPENDENCIES || exit 1

FRAMEWORK_DIR="$TOOLS_DIR/apktool/framework"
FRAMEWORK_TAG="$(GET_PROP "system" "ro.build.version.incremental")"
# apktool keeps its temporary files in Java's temp folder, whatever TMPDIR says, and leaves
# them there: 2.6 GB over a day of builds, in a /tmp that is often RAM. They go next to the
# decoded files instead, where make_rom.sh removes them.
APKTOOL_TMP="$APKTOOL_DIR-tmp"
mkdir -p "$APKTOOL_TMP"

FORCE=false
PARTITION=""
FILE=""

INPUT_FILE=""
OUTPUT_PATH=""

BUILD()
{
    if [ ! -d "$OUTPUT_PATH" ]; then
        LOGE "Folder not found: ${OUTPUT_PATH//$SRC_DIR\//}"
        exit 1
    fi

    LOG "- Building ${INPUT_FILE//$WORK_DIR/}"

    mkdir -p "$OUTPUT_PATH/build/apk"
    cp -a "$OUTPUT_PATH/original/META-INF" "$OUTPUT_PATH/build/apk/META-INF"

    EVAL "apktool \"-JDjava.io.tmpdir=$APKTOOL_TMP\" b -j \"$(nproc)\" -p \"$FRAMEWORK_DIR\" -srp \"$OUTPUT_PATH\"" || exit 1

    local FILE_NAME
    FILE_NAME="$(basename "$INPUT_FILE")"

    if [[ "$INPUT_FILE" == *".apk" ]]; then
        LOG "- Signing ${INPUT_FILE//$WORK_DIR/}"
        EVAL "signapk \"$SRC_DIR/security/onigiri_platform.x509.pem\" \"$SRC_DIR/security/onigiri_platform.pk8\" \"$OUTPUT_PATH/dist/$FILE_NAME\" \"$OUTPUT_PATH/dist/temp.apk\"" || exit 1
        mv -f "$OUTPUT_PATH/dist/temp.apk" "$OUTPUT_PATH/dist/$FILE_NAME"
    else
        # apktool stamps every entry with the build time and adds the dex files in the order its
        # parallel assemblers finish (signapk resets the time and sorts the entries of APKs). A
        # fixed time and dex order keep an unchanged jar byte-identical across builds, and so out
        # of OTAs.
        python3 - "$OUTPUT_PATH/dist/$FILE_NAME" "$OUTPUT_PATH/dist/fixed" << 'PY' || exit 1
import re
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as source, zipfile.ZipFile(sys.argv[2], "w") as output:
    entries = source.infolist()
    dex = [entry for entry in entries if re.fullmatch(r"classes\d*\.dex", entry.filename)]
    ordered = iter(sorted(dex, key=lambda entry: int(entry.filename[7:-4] or 1)))
    for entry in entries:
        if entry in dex:
            entry = next(ordered)
        data = source.read(entry)
        entry.date_time = (2008, 1, 1, 0, 0, 0)
        output.writestr(entry, data)
PY
        mv -f "$OUTPUT_PATH/dist/fixed" "$OUTPUT_PATH/dist/$FILE_NAME"
        LOG "- Zipaligning ${INPUT_FILE//$WORK_DIR/}"
        EVAL "zipalign -p 4 \"$OUTPUT_PATH/dist/$FILE_NAME\" \"$OUTPUT_PATH/dist/temp\"" || exit 1
        mv -f "$OUTPUT_PATH/dist/temp" "$OUTPUT_PATH/dist/$FILE_NAME"
    fi

    mkdir -p "$(dirname "$INPUT_FILE")"
    mv -f "$OUTPUT_PATH/dist/$FILE_NAME" "$INPUT_FILE"
    rm -rf "$OUTPUT_PATH/build" && rm -rf "$OUTPUT_PATH/dist"

    if [ -d "${INPUT_FILE%/*}/oat" ]; then
        DELETE_FROM_WORK_DIR "$PARTITION" "${FILE%/*}/oat"
    fi
    if [ -f "${INPUT_FILE%/*}/$FILE_NAME.prof" ]; then
        DELETE_FROM_WORK_DIR "$PARTITION" "${FILE%/*}/$FILE_NAME.prof"
    fi
    if [ -f "${INPUT_FILE%/*}/$FILE_NAME.bprof" ]; then
        DELETE_FROM_WORK_DIR "$PARTITION" "${FILE%/*}/$FILE_NAME.bprof"
    fi
}

DECODE()
{
    if [ ! -f "$INPUT_FILE" ]; then
        LOGE "File not found: ${INPUT_FILE//$WORK_DIR/}"
        exit 1
    elif [ -d "$OUTPUT_PATH" ]; then
        if $FORCE; then
            rm -rf "$OUTPUT_PATH"
        else
            LOGE "Output directory already exists (${OUTPUT_PATH//$SRC_DIR\//}). Use --force flag if you want to overwrite it."
            exit 1
        fi
    fi

    if [[ "$(READ_BYTES_AT "$INPUT_FILE" "0" "4")" != "04034b50" ]]; then
        LOGE "File not valid: ${INPUT_FILE//$WORK_DIR/}"
        exit 1
    fi

    LOG "- Decoding ${INPUT_FILE//$WORK_DIR/}"

    EVAL "apktool \"-JDjava.io.tmpdir=$APKTOOL_TMP\" d --no-debug-info -j \"$(nproc)\" -o \"$OUTPUT_PATH\" -p \"$FRAMEWORK_DIR\" -t \"$FRAMEWORK_TAG\" \"$INPUT_FILE\"" || exit 1

    if [[ "$INPUT_FILE" == *"framework.jar" ]]; then
        if unzip -l "$INPUT_FILE" | grep -q "debian.mime.types"; then
            unzip -q "$INPUT_FILE" "res/*" -d "$OUTPUT_PATH/unknown"
        fi
    fi
}

PREPARE_SCRIPT()
{
    if [[ "$#" == 0 ]]; then
        PRINT_USAGE
        exit 1
    fi

    ACTION="$1"
    if [[ "$ACTION" != "decode" ]] && [[ "$ACTION" != "d" ]] && \
            [[ "$ACTION" != "build" ]] && [[ "$ACTION" != "b" ]]; then
        PRINT_USAGE
        exit 1
    fi

    shift

    if [[ "$1" == "--force" ]] || [[ "$1" == "-f" ]]; then
        FORCE=true
        shift
    fi

    PARTITION="$1"
    if [ ! "$PARTITION" ]; then
        PRINT_USAGE
        exit 1
    elif ! IS_VALID_PARTITION_NAME "$PARTITION"; then
        LOGE "\"$PARTITION\" is not a valid partition name"
        exit 1
    fi

    shift

    if [ ! "$1" ]; then
        PRINT_USAGE
        exit 1
    fi

    FILE="$1"
    while [[ "${FILE:0:1}" == "/" ]]; do
        FILE="${FILE:1}"
    done

    INPUT_FILE="$WORK_DIR/$PARTITION/$FILE"
    OUTPUT_PATH="$APKTOOL_DIR/$PARTITION/${FILE//system\//}"
}

PRINT_USAGE()
{
    echo "Usage: apktool d[ecode]/b[uild] [options] <partition> <file>" >&2
    echo " -f, --force : Force delete output directory" >&2
}

ACTION=""

PREPARE_SCRIPT "$@"

if [ ! "$FRAMEWORK_TAG" ]; then
    LOGE "Work dir needs to be set up before using this script"
    exit 1
elif [ ! -f "$FRAMEWORK_DIR/1-$FRAMEWORK_TAG.apk" ]; then
    LOGW "framework-res.apk for \"$FRAMEWORK_TAG\" not found, installing"
    EVAL "apktool \"-JDjava.io.tmpdir=$APKTOOL_TMP\" if -p \"$FRAMEWORK_DIR\" -t \"$FRAMEWORK_TAG\" \"$WORK_DIR/system/system/framework/framework-res.apk\"" || exit 1
fi

case "$ACTION" in
    "d" | "decode")
        DECODE
        ;;
    "b" | "build")
        BUILD
        ;;
esac

exit 0
