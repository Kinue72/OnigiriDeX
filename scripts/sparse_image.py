#!/usr/bin/env python3
"""Shapes a sparse super image the way odin4 (Linux/macOS) flashes correctly; build_odin.sh uses it.

- A super sparse image with FILL chunks was acknowledged by the bootloader but landed corrupted
  ("liblp: invalid geometry magic" at boot); Samsung's own super images only use RAW and
  DONT_CARE, so FILL chunks are expanded to RAW.
- odin4 pads large images to a multiple of 512 bytes, and the padding breaks the next image
  (BOOTLOADER_FAIL code=11), so the largest DONT_CARE chunk is split until the sparse file size
  is a multiple of 512 (and build_odin.sh puts super last).
"""
import struct

SPARSE_MAGIC = 0xED26FF3A
RAW, FILL, DONT_CARE = 0xCAC1, 0xCAC2, 0xCAC3


def sparse_fixed(path):
    """Size and byte generator of the sparse image at path, FILL expanded and 512-aligned."""
    src = open(path, "rb")
    magic, major, minor, fhs, chs, blk, blocks, count, _ = struct.unpack("<IHHHHIIII", src.read(28))
    if magic != SPARSE_MAGIC or fhs != 28 or chs != 12:
        raise SystemExit(f"{path}: not an Android sparse image")
    # (kind, blocks, output size with header, input data offset); a FILL becomes RAW chunks small
    # enough for the 32-bit chunk size field.
    chunks = []
    for _ in range(count):
        kind, _, cb, total = struct.unpack("<HHII", src.read(chs))
        if kind == FILL:
            for start in range(0, cb, (0xFFFFFFFF - chs) // blk):
                n = min(cb - start, (0xFFFFFFFF - chs) // blk)
                chunks.append((FILL, n, chs + n * blk, src.tell()))
        else:
            chunks.append((kind, cb, total, src.tell()))
        src.seek(total - chs, 1)
    size = 28 + sum(total for _, _, total, _ in chunks)
    extra = next(x for x in range(512) if (size + chs * x) % 512 == 0)
    holes = [i for i, c in enumerate(chunks) if c[0] == DONT_CARE]
    big = max(holes, key=lambda i: chunks[i][1], default=None)
    if extra and (big is None or chunks[big][1] <= extra):
        raise SystemExit(f"{path}: no DONT_CARE chunk large enough to align the image")

    def generate():
        yield struct.pack("<IHHHHIIII", magic, major, minor, fhs, chs, blk, blocks, len(chunks) + extra, 0)
        for i, (kind, cb, total, offset) in enumerate(chunks):
            src.seek(offset)
            if kind == FILL:
                block = src.read(4) * (blk // 4)
                yield struct.pack("<HHII", RAW, 0, cb, total)
                for _ in range(cb):
                    yield block
            elif i == big and extra:
                pieces = [cb // (extra + 1)] * extra
                for piece in pieces + [cb - sum(pieces)]:
                    yield struct.pack("<HHII", DONT_CARE, 0, piece, chs)
            else:
                yield struct.pack("<HHII", kind, 0, cb, total)
                left = total - chs
                while left:
                    data = src.read(min(left, 1 << 24))
                    if not data:
                        raise SystemExit(f"{path}: truncated chunk")
                    yield data
                    left -= len(data)
        src.close()

    return size + chs * extra, generate()
