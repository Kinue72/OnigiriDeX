#!/bin/bash


BUILD()
(
    local PDR
    PDR="$(pwd)"

    local NAME="$1"; shift
    local DIR="$1"; shift
    local CMDS=("$@")

    LOG "- Building $NAME..."

    cd "$DIR" || exit 1
    source "$SRC_DIR/scripts/utils/source_patches.sh" || exit 1
    local GENERATED_BUILD_DIR=""
    trap 'status=$?; restore_source_patches || status=1;
        if [[ -n "$GENERATED_BUILD_DIR" ]]; then rm -rf -- "$GENERATED_BUILD_DIR" || status=1; fi
        exit "$status"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    require_clean_source "$DIR" || exit 1
    case "$NAME" in
        android-tools)
            local folder patches vendor
            for folder in "$DIR"/patches/*; do
                vendor="${folder##*/}"
                patches=("$folder"/*.patch)
                case "$vendor" in
                    libbase) patches+=("$SRC_DIR/external/patches/android-tools/0007-Include-fixed-width-integer-types.patch") ;;
                    libziparchive) patches+=("$SRC_DIR/external/patches/android-tools/0002-Include-fixed-width-types-in-zip-writer.patch") ;;
                esac
                apply_source_patches "$DIR/vendor/$vendor" "${patches[@]}" || exit 1
            done
            ;;
        apktool)
            apply_source_patches "$DIR" "$SRC_DIR"/external/patches/apktool/*.patch || exit 1
            ;;
        samloader)
            if [[ -e "$DIR/build" || -L "$DIR/build" ]]; then
                echo "Existing samloader build directory; preserve it before rebuilding: $DIR/build" >&2
                exit 1
            fi
            apply_source_patches "$DIR" "$SRC_DIR"/external/patches/samloader/*.patch || exit 1
            GENERATED_BUILD_DIR="$DIR/build"
            ;;
    esac
    for CMD in "${CMDS[@]}"; do
        local OUT
        OUT="$(eval "$CMD" 2>&1)"
        if [ $? -ne 0 ]; then
            echo -e    '\033[1;31m'"BUILD FAILED!"'\033[0m\n' >&2
            echo -e    '\033[0;31m'"$CMD"'\033[0m\n' >&2
            echo -n -e '\033[0;33m' >&2
            echo -n    "$OUT" >&2
            echo -e    '\033[0m' >&2
            exit 1
        fi
    done
    cd "$PDR"

    return 0
)

CHECK_TOOLS()
{
    local EXECUTABLES=("$@")

    local EXISTS=true
    for i in "${EXECUTABLES[@]}"; do
        [ ! -f "$TOOLS_DIR/bin/$i" ] && EXISTS=false
    done

    $EXISTS
}

GET_CMAKE_FLAGS()
{
    local FLAGS

    FLAGS+="-DCMAKE_SYSTEM_NAME=\"$(uname -s)\" "
    FLAGS+="-DCMAKE_SYSTEM_PROCESSOR=\"$(uname -m)\" "
    FLAGS+="-DCMAKE_BUILD_TYPE=\"Release\" "
    if type ccache &> /dev/null; then
        FLAGS+="-DCMAKE_C_COMPILER_LAUNCHER=\"ccache\" "
        FLAGS+="-DCMAKE_CXX_COMPILER_LAUNCHER=\"ccache\" "
    fi
    FLAGS+="-DCMAKE_C_COMPILER=\"clang\" "
    FLAGS+="-DCMAKE_CXX_COMPILER=\"clang++\""

    echo "$FLAGS"
}

GET_SRC_DIR()
{
    local TOPFILE="onigiri/configs/version.sh"
    if [ -n "$SRC_DIR" ] && [ -f "$SRC_DIR/$TOPFILE" ]; then
        (cd "$SRC_DIR"; PWD= /bin/pwd)
    else
        if [ -f "$TOPFILE" ]; then
            PWD= /bin/pwd
        else
            local HERE="$PWD"
            local T=
            while [ \( ! \( -f "$TOPFILE" \) \) ] && [ \( "$PWD" != "/" \) ]; do
                \cd ..
                T="$(PWD= /bin/pwd -P)"
            done
            \cd "$HERE"
            if [ -f "$T/$TOPFILE" ]; then
                echo "$T"
            fi
        fi
    fi
}

IS_WSL()
{
    if [ -e "/proc/sys/fs/binfmt_misc/WSLInterop" ] || [ -e "/run/WSL" ]; then
        echo "ON"
    else
        echo "OFF"
    fi
}

SRC_DIR="$(GET_SRC_DIR)"
if [ ! "$SRC_DIR" ]; then
    echo "Couldn't locate the top of the tree. Try setting SRC_DIR." >&2
    exit 1
else
    source "$SRC_DIR/scripts/utils/log_utils.sh" || exit 1
fi
OUT_DIR="$SRC_DIR/out"
TOOLS_DIR="$OUT_DIR/tools"

mkdir -p "$TOOLS_DIR/bin"

ANDROID_TOOLS=true
APKTOOL=true
EROFS_UTILS=true
SAMLOADER=true
SIGNAPK=true
MAGISK_TOOLS=true

ANDROID_TOOLS_EXEC=(
    "adb" "append2simg" "avbtool" "e2fsdroid"
    "ext2simg" "fastboot" "fec" "gki/generate_gki_certificate.py"
    "img2simg" "lpadd" "lpdump" "lpflash" "lpmake"
    "lpunpack" "make_f2fs" "mkbootfs" "mkbootimg" "mkdtboimg" "mke2fs"
    "mke2fs.android" "mke2fs.conf" "mkf2fsuserimg" "mkuserimg_mke2fs"
    "repack_bootimg" "simg2img" "sload_f2fs" "unpack_bootimg" "zipalign"
)
CHECK_TOOLS "${ANDROID_TOOLS_EXEC[@]}" && ANDROID_TOOLS=false
APKTOOL_EXEC=(
    "apktool" "apktool.jar"
)
CHECK_TOOLS "${APKTOOL_EXEC[@]}" && APKTOOL=false
EROFS_UTILS_EXEC=(
    "dump.erofs" "extract.erofs" "fsck.erofs" "fuse.erofs" "mkfs.erofs"
)
CHECK_TOOLS "${EROFS_UTILS_EXEC[@]}" && EROFS_UTILS=false
SAMLOADER_EXEC=(
    "../venv/bin/samloader"
)
CHECK_TOOLS "${SAMLOADER_EXEC[@]}" && SAMLOADER=false
SIGNAPK_EXEC=(
    "signapk" "signapk.jar"
)
CHECK_TOOLS "${SIGNAPK_EXEC[@]}" && SIGNAPK=false
CHECK_TOOLS magiskboot busybox && MAGISK_TOOLS=false

if [[ "$1" == "--check-tools" ]]; then
    if ! $ANDROID_TOOLS && \
            ! $APKTOOL && \
            ! $EROFS_UTILS && \
            ! $SAMLOADER && \
            ! $SIGNAPK && \
            ! $MAGISK_TOOLS; then
        exit 0
    else
        exit 1
    fi
elif [ "$1" ]; then
    echo "Usage: $(basename "$0" | sed 's/build_dependencies.sh/build_dependencies/')" >&2
    echo "This script does not accept any arguments." >&2
    exit 1
fi

if $MAGISK_TOOLS; then
    python3 - "$TOOLS_DIR" <<'PY'
import hashlib
import io
import sys
import urllib.request
import zipfile
from pathlib import Path

root = Path(sys.argv[1])
url = "https://github.com/topjohnwu/Magisk/releases/download/v30.7/Magisk-v30.7.apk"
data = urllib.request.urlopen(url, timeout=60).read()
assert hashlib.sha256(data).hexdigest() == "e0d32d2123532860f97123d927b1bb86c4e08e6fd8a48bfc6b5bee0afae9ebd5"
with zipfile.ZipFile(io.BytesIO(data)) as archive:
    for name in ("magiskboot", "busybox"):
        path = root / "bin" / name
        path.write_bytes(archive.read("lib/x86_64/lib" + name + ".so"))
        path.chmod(0o755)
PY
    [ "$?" = 0 ] || exit 1
fi

if $ANDROID_TOOLS; then
    ANDROID_TOOLS_CMDS=(
        "cmake -B \"build\" $(GET_CMAKE_FLAGS) -DANDROID_TOOLS_PATCH_VENDOR=OFF -DANDROID_TOOLS_USE_BUNDLED_LIBUSB=ON"
        "make -C \"build\" -j\"$(nproc)\""
        "find \"build/vendor\" -maxdepth 1 -type f -exec test -x {} \; -exec cp -a {} \"$TOOLS_DIR/bin\" \;"
        "cp -a \"vendor/avb/avbtool.py\" \"$TOOLS_DIR/bin/avbtool\""
        "cp -a \"vendor/mkbootimg/mkbootimg.py\" \"$TOOLS_DIR/bin/mkbootimg\""
        "cp -a \"vendor/mkbootimg/repack_bootimg.py\" \"$TOOLS_DIR/bin/repack_bootimg\""
        "cp -a \"vendor/mkbootimg/unpack_bootimg.py\" \"$TOOLS_DIR/bin/unpack_bootimg\""
        "cp -a \"vendor/libufdt/utils/src/mkdtboimg.py\" \"$TOOLS_DIR/bin/mkdtboimg\""
        "mkdir -p \"$TOOLS_DIR/bin/gki\""
        "cp -a \"vendor/mkbootimg/gki/generate_gki_certificate.py\" \"$TOOLS_DIR/bin/gki/generate_gki_certificate.py\""
        "ln -sf \"$TOOLS_DIR/bin/mke2fs.android\" \"$TOOLS_DIR/bin/mke2fs\""
        "cp -a \"../ext4_utils/mkuserimg_mke2fs.py\" \"$TOOLS_DIR/bin/mkuserimg_mke2fs.py\""
        "ln -sf \"$TOOLS_DIR/bin/mkuserimg_mke2fs.py\" \"$TOOLS_DIR/bin/mkuserimg_mke2fs\""
        "cp -a \"../ext4_utils/mke2fs.conf\" \"$TOOLS_DIR/bin/mke2fs.conf\""
        "cp -a \"../f2fs_utils/mkf2fsuserimg.sh\" \"$TOOLS_DIR/bin/mkf2fsuserimg\""
    )

    BUILD "android-tools" "$SRC_DIR/external/android-tools" "${ANDROID_TOOLS_CMDS[@]}" || exit 1
fi
if $APKTOOL; then
    APKTOOL_CMDS=(
        "./gradlew build shadowJar"
        "cp -a \"scripts/linux/apktool\" \"$TOOLS_DIR/bin\""
        "cp -a \"brut.apktool/apktool-cli/build/libs/apktool-cli.jar\" \"$TOOLS_DIR/bin/apktool.jar\""
    )

    BUILD "apktool" "$SRC_DIR/external/apktool" "${APKTOOL_CMDS[@]}" || exit 1
fi
if $EROFS_UTILS; then
    EROFS_UTILS_CMDS=(
        "cmake -S \"build/cmake\" -B \"out\" $(GET_CMAKE_FLAGS) -DRUN_ON_WSL=\"$(IS_WSL)\" -DENABLE_FULL_LTO=\"ON\" -DMAX_BLOCK_SIZE=\"4096\""
        "make -C \"out\" -j\"$(nproc)\""
        "find \"out/erofs-tools\" -maxdepth 1 -type f -exec test -x {} \; -exec cp -a {} \"$TOOLS_DIR/bin\" \;"
    )

    BUILD "erofs-utils" "$SRC_DIR/external/erofs-utils" "${EROFS_UTILS_CMDS[@]}" || exit 1
fi
if $SAMLOADER; then
    SAMLOADER_CMDS=(
        "python3 -m venv \"$TOOLS_DIR/venv\""
        "source \"$TOOLS_DIR/venv/bin/activate\"; pip3 install ."
    )

    BUILD "samloader" "$SRC_DIR/external/samloader" "${SAMLOADER_CMDS[@]}" || exit 1
fi
if $SIGNAPK; then
    SIGNAPK_CMDS=(
        "./gradlew build"
        "cp -a \"scripts/linux/signapk\" \"$TOOLS_DIR/bin\""
        "cp -a \"signapk/build/libs/signapk-all.jar\" \"$TOOLS_DIR/bin/signapk.jar\""
    )

    BUILD "signapk" "$SRC_DIR/external/signapk" "${SIGNAPK_CMDS[@]}" || exit 1
fi

exit 0
