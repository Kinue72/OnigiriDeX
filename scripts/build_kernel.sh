#!/usr/bin/env bash

set -eo pipefail

SRC_DIR="${SRC_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
KERNEL_DIR="$SRC_DIR/external/kernel"
KERNEL_REVISION="$(git -C "$SRC_DIR" rev-parse :external/kernel)"
PATCHES=("$SRC_DIR"/external/patches/kernel/*.patch)

source "$SRC_DIR/onigiri/configs/version.sh"
export ROM_VERSION KERNEL_RELEASE
export LOCALVERSION="-$KERNEL_VERSION"
unset BUILD_NUMBER

source "$SRC_DIR/scripts/utils/source_patches.sh"
if [[ -e "$KERNEL_DIR/.git" ]]; then
    # Every camera driver build rewrites this tracked header with its build time and host.
    git -C "$KERNEL_DIR" checkout -- vendor/qcom/opensource/camera-kernel/cam_generated_h
    require_clean_source "$KERNEL_DIR"
else
    git -C "$SRC_DIR" submodule update --init --depth 1 external/kernel
fi
[[ "$(git -C "$KERNEL_DIR" rev-parse HEAD)" = "$KERNEL_REVISION" ]]
trap 'status=$?; restore_source_patches || status=1; exit "$status"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
apply_source_patches "$KERNEL_DIR" "${PATCHES[@]}"
export PATH="${TOOLS_DIR:-$SRC_DIR/out/tools}/bin:$PATH"

"$KERNEL_DIR/build.sh" ksu oneui
"$SRC_DIR/scripts/package_kernel.sh"
