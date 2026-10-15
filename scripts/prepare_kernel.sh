#!/usr/bin/env bash

set -eo pipefail

[[ "$TARGET_CODENAME" = b5q && "$TARGET_ASSERT_MODEL" = SM-F731B ]]
KERNEL_DIR="$OUT_DIR/target/b5q/kernel"

python3 - "$KERNEL_DIR" "$SRC_DIR/external/kernel/custom_defconfigs/susfs_defconfig" "$KERNEL_RELEASE" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

if sys.flags.optimize:
    raise SystemExit("Python assertions must be enabled for kernel preparation")
root = Path(sys.argv[1])
manifest = json.loads((root / "artifacts.json").read_text())
for name, expected in manifest.items():
    path = root / name
    assert path.parent == root and path.is_file(), name
    with path.open("rb") as stream:
        checksum = hashlib.file_digest(stream, "sha256").hexdigest()
    assert checksum == expected["sha256"] and path.stat().st_size == expected["bytes"], "Kernel payload checksum mismatch: " + name
required = {"boot.img", "vendor_boot.img", "vendor_dlkm.img", "system_dlkm.img", "gki.config", "kernel.release"}
assert required <= manifest.keys(), "Incomplete Onigiri kernel artifacts"
config = (root / "gki.config").read_text()
for option in ("CONFIG_KSU=y", "CONFIG_KSU_SUSFS=y", "CONFIG_MODVERSIONS=y", *Path(sys.argv[2]).read_text().splitlines()):
    if option.startswith("CONFIG_") and option + "\n" not in config:
        raise SystemExit("Required kernel configuration missing: " + option)
assert (root / "kernel.release").read_text().strip() == sys.argv[3], "Kernel release does not match the ROM commit"
for name in ("boot.img", "vendor_boot.img"):
    assert (root / name).stat().st_size <= 100663296, name
PY

source "$SRC_DIR/scripts/utils/firmware_utils.sh"
source "$SRC_DIR/scripts/utils/module_utils.sh"
STAGE="$(mktemp -d "$OUT_DIR/.kernel-work.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

for PARTITION in vendor_dlkm system_dlkm; do
    EXTRACT_EROFS_PARTITION "$KERNEL_DIR/$PARTITION.img" "$STAGE"
done

for PARTITION in vendor_dlkm system_dlkm; do
    rm -rf "$WORK_DIR/$PARTITION"
    mv "$STAGE/$PARTITION" "$WORK_DIR/$PARTITION"
    mv "$STAGE/fs_config-$PARTITION" "$WORK_DIR/configs/fs_config-$PARTITION"
    mv "$STAGE/file_context-$PARTITION" "$WORK_DIR/configs/file_context-$PARTITION"
    SET_PROP "$PARTITION" "ro.product.$PARTITION.name" b5qxxx
    SET_PROP "$PARTITION" "ro.product.$PARTITION.device" b5q
done

for IMAGE in boot vendor_boot; do
    cp "$KERNEL_DIR/$IMAGE.img" "$WORK_DIR/kernel/$IMAGE.img"
done
