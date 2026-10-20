#!/usr/bin/env bash

set -eo pipefail

source "$SRC_DIR/scripts/utils/build_utils.sh"
CHECK_BUILD_DEPENDENCIES
"$SRC_DIR/scripts/make_rom.sh"
set -o allexport
source "$OUT_DIR/config.sh"
set +o allexport

[[ "$TARGET_CODENAME" = b5q && "$TARGET_ASSERT_MODEL" = SM-F731B ]]
[ "$TARGET_OS_FILE_SYSTEM" = erofs ]
[ "$TARGET_SUPER_PARTITION_SIZE" = 12664700928 ]
[ "$TARGET_SUPER_GROUP_SIZE" = 12660506624 ]
[ -f "$WORK_DIR/.completed" ]

OUTPUT="$OUT_DIR/Onigiri_AP_SM-F731B_F731BXXS5EYI1_${ROM_VERSION}_$(date +%Y%m%d).tar.md5"
if [ -e "$OUTPUT" ]; then
    LOGE "Output already exists: $OUTPUT"
    exit 1
fi

mkdir -p "$OUT_DIR/tmp"
STAGE="$(mktemp -d "$OUT_DIR/tmp/odin.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

SUPER_COMMAND=(lpmake --metadata-size 65536 --super-name super --metadata-slots 2
    --device "super:$TARGET_SUPER_PARTITION_SIZE"
    --group "$TARGET_SUPER_GROUP_NAME:$TARGET_SUPER_GROUP_SIZE"
    --sparse --output "$STAGE/super.img")
OCCUPIED=0

for PARTITION in system product system_ext vendor odm vendor_dlkm system_dlkm; do
    LOG "- Building Flip5 Odin partition $PARTITION"
    "$SRC_DIR/scripts/build_fs_image.sh" erofs -o "$STAGE/$PARTITION.img" \
        "$WORK_DIR/$PARTITION" "$WORK_DIR/configs/file_context-$PARTITION" \
        "$WORK_DIR/configs/fs_config-$PARTITION"
    SIZE="$(GET_IMAGE_SIZE "$STAGE/$PARTITION.img")"
    OCCUPIED=$((OCCUPIED + SIZE))
    SUPER_COMMAND+=(--partition "$PARTITION:readonly:$SIZE:$TARGET_SUPER_GROUP_NAME"
        --image "$PARTITION=$STAGE/$PARTITION.img")
done

if [ "$OCCUPIED" -gt "$TARGET_SUPER_GROUP_SIZE" ]; then
    LOGE "OS size exceeds the Flip5 dynamic partition group"
    exit 1
fi

LOG "- Building and verifying Flip5 super image"
python3 - "$STAGE" "${SUPER_COMMAND[@]}" <<'PYCHECK'
import hashlib
import subprocess
import sys
from pathlib import Path

stage = Path(sys.argv[1])
partitions = ("system", "product", "system_ext", "vendor", "odm", "vendor_dlkm", "system_dlkm")
expected = {}
for partition in partitions:
    image = stage / (partition + ".img")
    with image.open("rb") as stream:
        expected[partition] = (image.stat().st_size, hashlib.file_digest(stream, "sha256").digest())
subprocess.run(sys.argv[2:], check=True)
for partition in partitions:
    (stage / (partition + ".img")).unlink()
raw = stage / "super.raw.img"
subprocess.run(["simg2img", str(stage / "super.img"), str(raw)], check=True)
images = stage / "unpacked"
images.mkdir()
for partition in partitions:
    subprocess.run(["lpunpack", "-p", partition, str(raw), str(images)], check=True)
    image = images / (partition + ".img")
    if {path.name for path in images.iterdir()} != {image.name}:
        raise ValueError("Unexpected unpacked partition files: " + partition)
    with image.open("rb") as stream:
        actual = (image.stat().st_size, hashlib.file_digest(stream, "sha256").digest())
    if actual != expected[partition]:
        raise ValueError("Packed partition checksum mismatch: " + partition)
    image.unlink()
images.rmdir()
raw.unlink()
PYCHECK

LOG "- Compressing Odin images"
SUPER_IMAGE_SIZE="$(stat -c '%s' "$STAGE/super.img")"
lz4 -B6 --content-size -12 "$STAGE/super.img" "$STAGE/super.img.lz4"
rm "$STAGE/super.img"
for IMAGE in boot init_boot vendor_boot dtbo vbmeta recovery; do
    lz4 -B6 --content-size -12 "$WORK_DIR/kernel/$IMAGE.img" "$STAGE/$IMAGE.img.lz4"
done

LOG "- Creating Odin AP archive"
tar --format=gnu -cf "$STAGE/package.tar" -C "$STAGE" \
    super.img.lz4 boot.img.lz4 init_boot.img.lz4 vendor_boot.img.lz4 dtbo.img.lz4 vbmeta.img.lz4 recovery.img.lz4

python3 - "$STAGE/package.tar" "$OUTPUT" "$SRC_DIR" "$SUPER_IMAGE_SIZE" "$WORK_DIR" <<'PY'
import hashlib
import sys
import tarfile
from pathlib import Path

package, output, root = map(Path, sys.argv[1:4])
super_size = int(sys.argv[4])
work = Path(sys.argv[5])
sys.path.insert(0, str(root / "scripts"))
from import_fw import verify_odin_package

with tarfile.open(package) as archive:
    if {entry.name for entry in archive.getmembers()} != {
        "super.img.lz4", "boot.img.lz4", "init_boot.img.lz4", "vendor_boot.img.lz4", "dtbo.img.lz4", "vbmeta.img.lz4",
        "recovery.img.lz4"}:
        raise ValueError("Unexpected Odin archive contents")
    if not all(entry.isfile() for entry in archive.getmembers()):
        raise ValueError("Odin archive contains a non-regular image")
    for entry in archive.getmembers():
        with archive.extractfile(entry) as stream:
            header = stream.read(15)
        if len(header) != 15 or header[:5] != b"\x04\x22\x4d\x18\x6c" or header[5] not in (0x40, 0x50, 0x60):
            raise ValueError("Invalid LZ4 image header: " + entry.name)
        expected_size = super_size if entry.name == "super.img.lz4" else (work / "kernel" / entry.name.removesuffix(".lz4")).stat().st_size
        if int.from_bytes(header[6:14], "little") != expected_size:
            raise ValueError("LZ4 image size mismatch: " + entry.name)
with package.open("rb") as stream:
    checksum = hashlib.file_digest(stream, "md5").hexdigest()
with package.open("ab") as stream:
    stream.write(f"{checksum}  {output.name.removesuffix('.md5')}\n".encode())
staged = package.with_name(output.name)
package.rename(staged)
verify_odin_package(staged)
staged.rename(output)
with output.open("rb") as stream:
    checksum = hashlib.file_digest(stream, "sha256").hexdigest()
output.with_name(output.name + ".sha256").write_text(f"{checksum}  {output.name}\n")
PY

LOG "- Odin AP package created: $OUTPUT"
