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
    echo "Usage: source buildenv.sh [--debug] [SM-F731B|b5q]"
    return 0
fi

if [ "$#" -gt 1 ] || [[ "${1:-b5q}" != "b5q" && "${1:-b5q}" != "SM-F731B" ]]; then
    echo "Onigiri supports only SM-F731B (b5q)." >&2
    return 1
fi

export OUT_DIR="$SRC_DIR/out"
export TMP_DIR="$OUT_DIR/tmp"
export ODIN_DIR="$OUT_DIR/odin"
export FW_DIR="$OUT_DIR/fw"
export TOOLS_DIR="$OUT_DIR/tools"
export APKTOOL_DIR="$OUT_DIR/target/b5q/apktool"
export WORK_DIR="$OUT_DIR/target/b5q/work_dir"

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
