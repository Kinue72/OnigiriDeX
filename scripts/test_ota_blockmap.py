#!/usr/bin/env python3
"""Checks for ota_blockmap.py: python3 scripts/test_ota_blockmap.py"""
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ota_blockmap import BLOCK, main


def image(path, blocks):
    with open(path, "wb") as f:
        f.write(b"".join(bytes([b]) * BLOCK for b in blocks))


with tempfile.TemporaryDirectory() as tmp:
    src, tgt, src_map, tgt_map = (os.path.join(tmp, n) for n in ("s.img", "t.img", "s.map", "t.map"))
    # A new file (9) lands before the rest, which shifts by one block; 4 changed to 8, 0 is empty.
    image(src, [1, 2, 3, 0, 4, 5, 6, 2])
    image(tgt, [1, 9, 2, 3, 0, 8, 5, 6, 2, 2])
    main(src, tgt, src_map, tgt_map)
    with open(src_map) as f:
        assert f.read() == "unchanged-0|1-2\nunchanged-1|5-7\n", "source runs"
    with open(tgt_map) as f:
        # Block 0 always ships whole; the second copy of 2 has no unused source block left.
        assert f.read() == "unchanged-0|2-3\nunchanged-1|6-8\n", "target runs"

print("ota_blockmap: ok")
