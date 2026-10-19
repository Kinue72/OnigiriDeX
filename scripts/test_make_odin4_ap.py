#!/usr/bin/env python3
"""Checks for make_odin4_ap.py: python3 scripts/test_make_odin4_ap.py"""
import io
import os
import struct
import sys
import tarfile
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_odin4_ap import DONT_CARE, FILL, RAW, SPARSE_MAGIC, main, sparse_fixed

BLK = 4096


def sparse(path, chunks, blocks):
    with open(path, "wb") as f:
        f.write(struct.pack("<IHHHHIIII", SPARSE_MAGIC, 1, 0, 28, 12, BLK, blocks, len(chunks), 0))
        for kind, cb, data in chunks:
            f.write(struct.pack("<HHII", kind, 0, cb, 12 + len(data)) + data)


def unsparse(data):
    blk, count = struct.unpack_from("<I", data, 12)[0], struct.unpack_from("<I", data, 20)[0]
    out, pos = bytearray(), 28
    for _ in range(count):
        kind, _, cb, total = struct.unpack_from("<HHII", data, pos)
        body = data[pos + 12 : pos + total]
        out += body if kind == RAW else body * (cb * blk // 4) if kind == FILL else b"\0" * cb * blk
        pos += total
    assert pos == len(data)
    return bytes(out)


with tempfile.TemporaryDirectory() as tmp:
    # FILL is expanded, the image is padded to 512 bytes with DONT_CARE, contents unchanged.
    src = os.path.join(tmp, "super.img")
    sparse(src, [(RAW, 1, b"r" * BLK), (FILL, 3, b"abcd"), (DONT_CARE, 1000, b"")], 1004)
    size, pieces = sparse_fixed(src)
    out = b"".join(pieces)
    assert len(out) == size and size % 512 == 0
    assert unsparse(out) == unsparse(open(src, "rb").read())
    assert struct.unpack_from("<H", out, 28 + 12 + BLK)[0] == RAW

    # A FILL of 4 GiB becomes RAW chunks whose sizes fit 32 bits.
    sparse(src, [(FILL, 1 << 20, b"\0\0\0\0"), (DONT_CARE, 1000, b"")], (1 << 20) + 1000)
    size, pieces = sparse_fixed(src)
    assert size % 512 == 0 and size > (1 << 32)
    next(pieces)  # file header
    first = struct.unpack("<HHII", next(pieces))
    for _ in range(first[2]):
        next(pieces)
    second = struct.unpack("<HHII", next(pieces))
    assert first[0] == second[0] == RAW and first[2] + second[2] == 1 << 20

    # Entries other than plain images are refused before anything is written outside the work dir.
    package = os.path.join(tmp, "AP.tar")
    with tarfile.open(package, "w") as tar:
        info = tarfile.TarInfo("../escape.img")
        info.size = 4
        tar.addfile(info, io.BytesIO(b"oops"))
    sys.argv = ["make_odin4_ap.py", package, os.path.join(tmp, "out.tar")]
    try:
        main()
        raise AssertionError("a path entry was accepted")
    except SystemExit as e:
        assert "unexpected entry" in str(e)
    assert not os.path.exists(os.path.join(os.path.dirname(tmp), "escape.img"))
    assert sorted(os.listdir(tmp)) == ["AP.tar", "super.img"]

print("ok")
