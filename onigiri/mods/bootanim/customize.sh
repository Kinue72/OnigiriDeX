[ "$TARGET_CODENAME" = b5q ] || return 1

ANIMATION_DIR="$SRC_DIR/onigiri/mods/bootanim/2340x1080"
python3 - "$ANIMATION_DIR" <<'PYQMG' || return 1
import struct
import sys
from pathlib import Path

for name in ("bootsamsung.qmg", "bootsamsungloop.qmg", "shutdown.qmg"):
    path = Path(sys.argv[1]) / name
    with path.open("rb") as stream:
        header = stream.read(20)
    if len(header) != 20 or header[:2] != b"QM" or struct.unpack_from("<HH", header, 6) != (1080, 2340):
        raise SystemExit(f"Invalid animation header: {path}")
PYQMG

for ANIMATION in bootsamsung bootsamsungloop shutdown; do
    for PREFIX in "" sub_; do
        FILE="system/media/${PREFIX}${ANIMATION}.qmg"
        cp -f "$ANIMATION_DIR/$ANIMATION.qmg" "$WORK_DIR/system/$FILE" || return 1
        SET_METADATA system "$FILE" 0 0 644 u:object_r:system_file:s0 || return 1
    done
done
