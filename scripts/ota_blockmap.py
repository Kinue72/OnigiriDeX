#!/usr/bin/env python3
"""Usage: ota_blockmap.py <source.img> <target.img> <source.map> <target.map>

Block maps that let the OTA generator move unchanged data instead of shipping it again. It diffs a
partition without a map block by block at the same offsets, so one file added early in an erofs
image shifts everything after it and the whole image ships as new data (3.4 GB instead of tens of
MB). Every run of target blocks found unchanged anywhere in the source gets one name in both maps,
which the generator turns into a move. What's left (new and changed data) it still diffs as before.

The names have no leading "/": the generator would look those up as files in the target-files.
"""
import hashlib
import mmap
import sys

BLOCK = 4096
ZERO = hashlib.blake2b(bytes(BLOCK), digest_size=16).digest()


def block_hashes(path):
    with open(path, "rb") as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as data:
        return [hashlib.blake2b(data[i : i + BLOCK], digest_size=16).digest() for i in range(0, len(data), BLOCK)]


def match(src, tgt):
    """[(target start, source start, length)]: runs of equal non-zero blocks. Block 0 always ships
    whole (the generator's clobbered block), and no source block is used twice."""
    # ponytail: only the first copy of a repeated block can start a run; keep every position per
    # hash if duplicate-heavy images ever make updates noticeably bigger.
    first = {}
    for i, h in enumerate(src):
        if i and h != ZERO:
            first.setdefault(h, i)
    used = bytearray(len(src))
    runs, t = [], 1
    while t < len(tgt):
        s = first.get(tgt[t])
        if s is None or used[s]:
            t += 1
            continue
        n = 0
        while t + n < len(tgt) and s + n < len(src) and tgt[t + n] == src[s + n] != ZERO and not used[s + n]:
            used[s + n] = 1
            n += 1
        runs.append((t, s, n))
        t += n
    return runs


def main(source, target, source_map, target_map):
    runs = match(block_hashes(source), block_hashes(target))
    with open(source_map, "w") as src_f, open(target_map, "w") as tgt_f:
        for i, (t, s, n) in enumerate(runs):
            # Samsung's generator splits name and blocks at "|" (AOSP's at a space); blocks are an
            # inclusive "first-last".
            src_f.write(f"unchanged-{i}|{s}-{s + n - 1}\n")
            tgt_f.write(f"unchanged-{i}|{t}-{t + n - 1}\n")
    moved = sum(n for _, _, n in runs)
    print(f"{moved * BLOCK >> 20} MB unchanged in {len(runs)} runs")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit(__doc__.splitlines()[0])
    main(*sys.argv[1:])
