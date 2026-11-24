#!/usr/bin/env python3
"""Report the rear cameras' orientation as seen from the fixed cover screen."""
import hashlib
from pathlib import Path
import struct
import sys

# Stock HAL -> hook sites in ChiContext::InitializeStaticMetadataPool and the patched HAL. The
# SM-F731N's differs from the B's only in read-only data; the SM-F7310's code is the same with
# these two sites 0x1130 further on (same instructions around them and in the cave).
HALS = {
    '5dc150aa45902ddd0bacf088958f7d9c7b0828bd2eeeb3042a402b344eda12bc': (  # F731BXXS5EYI1
        (0x16867f8, 0x1686840), '23f8d81beb3a5e6a85f30e55e1cf65f89cc7f1273828c04fadc272fcb7e2fe28'),
    '3f1e9edb1cf837f603d73784183363b77eafead4e6dc9ca8727d1d472a0e3878': (  # F731NKSS5EYGB
        (0x16867f8, 0x1686840), '86ced429b572388f12703951f2b247cb840ce56ca70c82995f8504ca45687961'),
    '736f56c72372403d10777afa5778fe6415c7e3ffb233063d295e20f1d2744f59': (  # F7310ZSS7EYI1
        (0x1687928, 0x1687970), 'd548b286b653bc9d09cce1716eea8ea0af806cadb5f73a695b0d1f4e37f44f8a'),
}

# The rear lenses sit in the top half, which is turned over when the Flip folds. Stock firmware
# only corrects that through its folded-camera path (front ID swapped to the rear sensor), so on
# the always-folded cover every rear preview and photo came out 180 degrees off. Publish 270
# (front lenses already report 270) as android.sensor.orientation; CamX keeps its own mount
# angle, which its AWB and tuning depend on.
CAVE = 0x11749a0  # ICASetting::DumpWarpComposition (.cfi): debug dump, return value unused


def patch(binary):
    stock = binary.read_bytes()
    digest = hashlib.sha256(stock).hexdigest()
    if digest in (result for _, result in HALS.values()):
        return
    if digest not in HALS:
        raise SystemExit(f'Unsupported camera HAL: {digest}')
    sites, result = HALS[digest]
    patched = bytearray(stock)
    # bti c; adr x2, .+12; ret; nop; .word 270
    struct.pack_into('<5I', patched, CAVE, 0xd503245f, 0x10000062, 0xd65f03c0, 0xd503201f, 270)
    for site in sites:
        if stock[site:site + 4].hex() != '621240f9':  # ldr x2, [x19, #0x20] (&sensor orientation)
            raise SystemExit('Camera HAL hook mismatch')
        struct.pack_into('<I', patched, site, 0x94000000 | (((CAVE - site) >> 2) & 0x3ffffff))  # bl CAVE
    if hashlib.sha256(patched).hexdigest() != result:
        raise SystemExit('Unexpected camera HAL patch result')
    binary.write_bytes(patched)


if __name__ == '__main__':
    patch(Path(sys.argv[1]))
