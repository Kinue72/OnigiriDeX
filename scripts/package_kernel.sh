#!/usr/bin/env bash

set -eo pipefail

SRC_DIR="${SRC_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
BIN="$SRC_DIR/out/tools/bin"
KERNEL_DIR="$SRC_DIR/external/kernel"
BUILD="$KERNEL_DIR/out/oneui/b5q/msm-kalama-kalama-gki-ksu"
STOCK="$SRC_DIR/out/fw/SM-F731B_XXV/kernel"
OUTPUT="$SRC_DIR/out/target/b5q/kernel"

python3 - "$BUILD" "$BIN" "$KERNEL_DIR/custom_defconfigs/susfs_defconfig" "$KERNEL_RELEASE" <<'PY'
import hashlib
import re
import subprocess
import sys
from pathlib import Path

if sys.flags.optimize:
    raise SystemExit("Python assertions must be enabled for kernel packaging")
build, tools, susfs_config = map(Path, sys.argv[1:4])
release = sys.argv[4]
config = (build / "gki_kernel/common/.config").read_text()
for option in ("CONFIG_KSU=y", "CONFIG_KSU_SUSFS=y", "CONFIG_MODVERSIONS=y", *susfs_config.read_text().splitlines()):
    if option.startswith("CONFIG_"):
        if option + "\n" not in config:
            raise SystemExit("Required kernel configuration missing: " + option)
for name, checksum in {
    "magiskboot": "a18ecbd7981179494b7d281453d6c4e25b5c719e7d2ef7f6eba3c6be3043c58e",
    "busybox": "060844b0769f7a50262854af027c4d6076a212d160a51309b53057cfb7122900",
}.items():
    assert hashlib.sha256((tools / name).read_bytes()).hexdigest() == checksum, name
assert (build / "dist/kernel.release").read_text().strip() == release, "Kernel release does not match the kernel sources"
msm_makefile = susfs_config.parents[1] / "kernel_platform/msm-kernel/Makefile"
version = dict(re.findall(r"^(VERSION|PATCHLEVEL|SUBLEVEL|EXTRAVERSION)[ \t]*=[ \t]*(.*)$", msm_makefile.read_text(), re.M))
msm_release = ".".join(version[name] for name in ("VERSION", "PATCHLEVEL", "SUBLEVEL")) + version["EXTRAVERSION"] + "-" + release.partition("-")[2]
for tree, expected in (("gki_kernel/common", release), ("msm-kernel", msm_release)):
    assert (build / tree / "include/config/kernel.release").read_text().strip() == expected, "Native kernel release mismatch: " + tree
symbols = {}
paths = [build / "gki_kernel/common/Module.symvers", build / "msm-kernel/Module.symvers"]
paths += list(build.parent.glob("vendor/**/Module.symvers"))
for path in paths:
    for line in path.read_text().splitlines():
        crc, name = line.split()[:2]
        assert name not in symbols or symbols[name] == crc, "Conflicting kernel export: " + name
        symbols[name] = crc
modules = list((build / "dist").glob("*.ko"))
assert len(modules) == 530
for module in modules:
    # MODVERSIONS compares flags and import CRCs across the native GKI/MSM releases.
    module_release, _, flags = subprocess.check_output(["modinfo", "-F", "vermagic", str(module)], text=True).strip().partition(" ")
    assert module_release in {release, msm_release}, "Module release mismatch: " + module.name
    assert flags == "SMP preempt mod_unload modversions aarch64", "Module vermagic flags mismatch: " + module.name
    for line in subprocess.check_output(["modprobe", "--show-modversions", str(module)], text=True).splitlines():
        crc, name = line.split()[:2]
        assert symbols.get(name) == crc, "Module ABI mismatch: " + module.name + ": " + name
print("Verified official KernelSU + SUSFS configuration and all 530 module ABIs")
PY

STAGE="$(mktemp -d "$SRC_DIR/out/target/b5q/.kernel-package.XXXXXX")"
cleanup()
{
    local STATUS="$?"
    if [ -d "$STAGE/previous" ] && [ ! -e "$OUTPUT" ]; then
        mv -T "$STAGE/previous" "$OUTPUT" || {
            echo "Previous kernel artifacts retained in $STAGE/previous" >&2
            return 1
        }
    fi
    if [ "$STATUS" -ne 0 ] && [ -d "$STAGE/previous" ]; then
        echo "Previous kernel artifacts retained in $STAGE/previous" >&2
        return "$STATUS"
    fi
    rm -rf "$STAGE"
    return "$STATUS"
}
trap cleanup EXIT
abort() { echo "$*" >&2; exit 1; }
source "$KERNEL_DIR/prebuilts/sm8550-repack.sh"

sm8550_prepare_boot "$STAGE/boot-work" "$STOCK/boot.img" "$BUILD/packaged/Image" "$STAGE/boot.img" || abort "Boot repack failed"
sm8550_prepare_vendor_boot "$STAGE/vendor-work" "$STOCK/vendor_boot.img" \
    "$BUILD/packaged/vendor_ramdisk/ramdisk/lib/modules" "$STAGE/vendor_boot.img" || abort "Vendor boot repack failed"
sm8550_check_image_size "$STAGE/boot.img" "$STOCK/boot.img" boot
sm8550_check_image_size "$STAGE/vendor_boot.img" "$STOCK/vendor_boot.img" vendor_boot

python3 - "$BUILD" "$STAGE" <<'PY'
import hashlib
import json
import shutil
import sys
from pathlib import Path

build, stage = map(Path, sys.argv[1:])
output = stage / "artifacts"
shutil.copytree(build / "packaged", output)
for name, source in {
    "gki.config": "gki_kernel/common/.config", "msm.config": "msm-kernel/.config",
    "kernel.release": "dist/kernel.release", "vmlinux.symvers": "dist/vmlinux.symvers",
    "modules.load": "dist/modules.load", "vendor_dlkm.modules.load": "dist/vendor_dlkm.modules.load",
    "system_dlkm.modules.load": "dist/system_dlkm.modules.load",
}.items():
    shutil.copyfile(build / source, output / name)
for name in ("boot.img", "vendor_boot.img"):
    shutil.move(stage / name, output / name)
manifest = {}
for path in output.iterdir():
    if path.is_file() and path.name != "artifacts.json":
        with path.open("rb") as stream:
            manifest[path.name] = {"bytes": path.stat().st_size, "sha256": hashlib.file_digest(stream, "sha256").hexdigest()}
(output / "artifacts.json").write_text(json.dumps(manifest, indent=2) + "\n")
PY

[ ! -e "$OUTPUT" ] || mv -T "$OUTPUT" "$STAGE/previous"
mv -T "$STAGE/artifacts" "$OUTPUT"
rm -rf "$KERNEL_DIR/out"
