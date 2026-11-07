if [ -z "${BASH_VERSION:-}" ]; then
    echo "Use Bash to source buildenv.sh." >&2
    return 1
fi

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
export SRC_DIR
export DEBUG=false

if [[ "${1:-}" == "--debug" ]]; then
    export DEBUG=true
    shift
fi

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: source buildenv.sh [--debug] [SM-F731B|SM-F731N|b5q]"
    return 0
fi

# One build per Flip5 model: each takes vendor, odm, dtbo and recovery from its own stock
# firmware (onigiri/configs/firmware.json); b5q means the SM-F731B.
TARGET_MODEL="${1:-SM-F731B}"
[ "$TARGET_MODEL" = b5q ] && TARGET_MODEL=SM-F731B
if [ "$#" -gt 1 ] || ! python3 -c 'import json, sys; sys.exit(sys.argv[2] not in json.load(open(sys.argv[1]))["targets"])' \
        "$SRC_DIR/onigiri/configs/firmware.json" "$TARGET_MODEL"; then
    echo "Onigiri supports SM-F731B and SM-F731N (b5q)." >&2
    return 1
fi
export TARGET_MODEL

export OUT_DIR="$SRC_DIR/out"
export TMP_DIR="$OUT_DIR/tmp"
export ODIN_DIR="$OUT_DIR/odin"
export FW_DIR="$OUT_DIR/fw"
export TOOLS_DIR="$OUT_DIR/tools"
export APKTOOL_DIR="$OUT_DIR/target/b5q/$TARGET_MODEL/apktool"
export WORK_DIR="$OUT_DIR/target/b5q/$TARGET_MODEL/work_dir"

if [[ ":$PATH:" != *":$TOOLS_DIR/bin:"* ]]; then
    export PATH="$TOOLS_DIR/bin:$PATH"
fi

mkdir -p "$OUT_DIR/target/b5q"
"$SRC_DIR/scripts/internal/gen_config_file.sh" b5q || return 1
set -o allexport
source "$OUT_DIR/config.sh"
set +o allexport

croot()
{
    cd -- "$SRC_DIR${1:+/$1}"
}

run_cmd()
{
    local CMD="${1:-}"
    if [ -n "$CMD" ] && [ -x "$SRC_DIR/scripts/$CMD.sh" ]; then
        shift
        mkdir -p "$OUT_DIR/target/b5q"
        (
            set -o pipefail
            "$SRC_DIR/scripts/$CMD.sh" "$@" |& tee "$OUT_DIR/target/b5q/$CMD-$(date +%Y%m%d_%H%M%S).log"
        )
    else
        echo "Commands: download_fw, extract_fw, build_dependencies, build_kernel, make_rom, build_odin, make_ota, release, apktool, cleanup" >&2
        return 1
    fi
}

onigiri()
{
    run_cmd "$@"
}

cat "$OUT_DIR/config.sh"
return 0
