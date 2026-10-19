#!/usr/bin/env python3
"""Repack an `onigiri build_odin` AP package so odin4 (Linux/macOS) flashes it correctly.

usage: make_odin4_ap.py out/Onigiri_AP_<...>.tar.md5 out/AP_odin4.tar

- odin4 never decompresses .lz4 images, so they are stored decompressed.
- A super sparse image with FILL chunks was acknowledged by the bootloader but landed corrupted
  ("liblp: invalid geometry magic" at boot); Samsung's own super images only use RAW and
  DONT_CARE, so FILL chunks are expanded to RAW.
- odin4 pads large images to a multiple of 512 bytes, and the padding breaks the next image
  (BOOTLOADER_FAIL code=11), so the largest DONT_CARE chunk is split until the sparse file size
  is a multiple of 512, and super goes last.

Needs the lz4 CLI. Writes a GNU tar: super is over 8 GiB, so odin4 needs base-256 tar sizes.
"""
import io
import os
import shutil
import struct
import subprocess
import sys
import tarfile

SPARSE_MAGIC = 0xED26FF3A
RAW, FILL, DONT_CARE = 0xCAC1, 0xCAC2, 0xCAC3


def sparse_fixed(path):
    """Size and byte generator of the sparse image at path, FILL expanded and 512-aligned."""
    src = open(path, "rb")
    magic, major, minor, fhs, chs, blk, blocks, count, _ = struct.unpack("<IHHHHIIII", src.read(28))
    if magic != SPARSE_MAGIC or fhs != 28 or chs != 12:
        raise SystemExit(f"{path}: not an Android sparse image")
    chunks = []
    for _ in range(count):
        kind, _, cb, total = struct.unpack("<HHII", src.read(chs))
        chunks.append((kind, cb, total, src.tell()))
        src.seek(total - chs, 1)
    size = 28 + sum(chs + cb * blk if kind == FILL else total for kind, cb, total, _ in chunks)
    extra = next(x for x in range(512) if (size + chs * x) % 512 == 0)
    holes = [i for i, c in enumerate(chunks) if c[0] == DONT_CARE]
    big = max(holes, key=lambda i: chunks[i][1], default=None)
    if extra and (big is None or chunks[big][1] <= extra):
        raise SystemExit(f"{path}: no DONT_CARE chunk large enough to align the image")

    def generate():
        yield struct.pack("<IHHHHIIII", magic, major, minor, fhs, chs, blk, blocks, count + extra, 0)
        for i, (kind, cb, total, offset) in enumerate(chunks):
            src.seek(offset)
            if kind == FILL:
                block = src.read(4) * (blk // 4)
                yield struct.pack("<HHII", RAW, 0, cb, chs + cb * blk)
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


class Chunks(io.RawIOBase):
    """Read-only file object over a byte generator, for tarfile.addfile."""

    def __init__(self, pieces):
        self.pieces, self.rest = pieces, b""

    def readable(self):
        return True

    def readinto(self, buffer):
        while not self.rest:
            self.rest = next(self.pieces, b"")
            if not self.rest:
                return 0
        n = min(len(buffer), len(self.rest))
        buffer[:n], self.rest = self.rest[:n], self.rest[n:]
        return n


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__.split("\n\n")[1])
    package, out = sys.argv[1], sys.argv[2]
    work = out + ".work"
    os.makedirs(work, exist_ok=True)
    try:
        images = []
        with tarfile.open(package) as tar:
            for member in tar:
                name = member.name[:-4] if member.name.endswith(".lz4") else member.name
                path = os.path.join(work, name)
                with tar.extractfile(member) as data, open(path, "wb") as image:
                    if member.name.endswith(".lz4"):
                        with subprocess.Popen(["lz4", "-dcq"], stdin=subprocess.PIPE, stdout=image) as lz4:
                            shutil.copyfileobj(data, lz4.stdin, 1 << 24)
                            lz4.stdin.close()
                        if lz4.returncode:
                            raise SystemExit(f"lz4 failed on {member.name}")
                    else:
                        shutil.copyfileobj(data, image, 1 << 24)
                images.append(name)
                print(f"unpacked {name}", flush=True)
        if "super.img" not in images:
            raise SystemExit(f"{package}: no super.img")
        images.remove("super.img")
        with tarfile.open(out, "w", format=tarfile.GNU_FORMAT) as tar:
            for name in images:
                tar.add(os.path.join(work, name), arcname=name)
                os.remove(os.path.join(work, name))
            size, pieces = sparse_fixed(os.path.join(work, "super.img"))
            info = tarfile.TarInfo("super.img")
            info.size, info.mode = size, 0o644
            tar.addfile(info, io.BufferedReader(Chunks(pieces), 1 << 24))
        print(f"wrote {out}: {', '.join(images)}, then super.img ({size} bytes, {size % 512} mod 512)")
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
