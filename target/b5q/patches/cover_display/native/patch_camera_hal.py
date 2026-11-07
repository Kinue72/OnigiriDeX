#!/usr/bin/env python3
"""Report the rear cameras' orientation as seen from the fixed cover screen."""
import hashlib
from pathlib import Path
import struct
import sys

# Stock HAL -> patched HAL. The SM-F731N's differs from the B's only in read-only data, so the
# code below sits at the same offsets in both.
PATCHED_SHA = {
    '5dc150aa45902ddd0bacf088958f7d9c7b0828bd2eeeb3042a402b344eda12bc':  # F731BXXS5EYI1
        '23f8d81beb3a5e6a85f30e55e1cf65f89cc7f1273828c04fadc272fcb7e2fe28',
    '3f1e9edb1cf837f603d73784183363b77eafead4e6dc9ca8727d1d472a0e3878':  # F731NKSS5EYGB
        '86ced429b572388f12703951f2b247cb840ce56ca70c82995f8504ca45687961',
}

# The rear lenses sit in the top half, which is turned over when the Flip folds. Stock firmware
# only corrects that through its folded-camera path (front ID swapped to the rear sensor), so on
# the always-folded cover every rear preview and photo came out 180 degrees off. Publish 270
# (front lenses already report 270) as android.sensor.orientation; CamX keeps its own mount
# angle, which its AWB and tuning depend on.
CAVE = 0x11749a0  # ICASetting::DumpWarpComposition (.cfi): debug dump, return value unused
ORIENTATION_SITES = (0x16867f8, 0x1686840)  # ChiContext::InitializeStaticMetadataPool


def patch(binary):
    stock = binary.read_bytes()
    digest = hashlib.sha256(stock).hexdigest()
    if digest in PATCHED_SHA.values():
        return
    if digest not in PATCHED_SHA:
        raise SystemExit(f'Unsupported camera HAL: {digest}')
    patched = bytearray(stock)
    # bti c; adr x2, .+12; ret; nop; .word 270
    struct.pack_into('<5I', patched, CAVE, 0xd503245f, 0x10000062, 0xd65f03c0, 0xd503201f, 270)
    for site in ORIENTATION_SITES:
        if stock[site:site + 4].hex() != '621240f9':  # ldr x2, [x19, #0x20] (&sensor orientation)
            raise SystemExit('Camera HAL hook mismatch')
        struct.pack_into('<I', patched, site, 0x94000000 | (((CAVE - site) >> 2) & 0x3ffffff))  # bl CAVE
    if hashlib.sha256(patched).hexdigest() != PATCHED_SHA[digest]:
        raise SystemExit('Unexpected camera HAL patch result')
    binary.write_bytes(patched)


if __name__ == '__main__':
    patch(Path(sys.argv[1]))
