#!/usr/bin/env python3
"""Usage: check_patches.py <patch>...   (no arguments: self-test)

Fails when a hunk holds more or fewer lines than its @@ header says. git apply quietly drops
lines past the end of a hunk, so a hand-edited patch can lose the end of a file and still
apply: once it cut ".end method" off a new smali class, which only broke hours later in apktool.
"""
import re
import sys

HUNK = re.compile(r"@@ -\d+(?:,(\d+))? \+\d+(?:,(\d+))? @@")


def check(path):
    old = new = 0  # lines the current hunk still expects
    in_diff = False
    with open(path, encoding="utf-8", errors="surrogateescape") as patch:
        for number, line in enumerate(patch, 1):
            line = line.rstrip("\n")
            where = f"{path}:{number}"
            if old or new:
                if line.startswith("\\"):  # "\ No newline at end of file"
                    continue
                kind = line[:1] or " "  # editors strip the space of blank context lines
                if kind == " " and old and new:
                    old, new = old - 1, new - 1
                elif kind == "-" and old:
                    old -= 1
                elif kind == "+" and new:
                    new -= 1
                else:
                    return f"{where}: hunk is shorter or longer than its header"
            elif match := HUNK.match(line):
                old, new = (int(count) if count is not None else 1 for count in match.groups())
            elif line.startswith("diff --git "):
                in_diff = True
            elif in_diff and (line[:1] in ("+", " ") and not line.startswith("+++ ") or
                              line[:1] == "-" and not line.startswith(("--- ", "-- "))):
                return f"{where}: line after the end of a hunk; is its header count too small?"
    if old or new:
        return f"{path}: last hunk ends early"
    return None


if len(sys.argv) == 1:
    import tempfile
    for body, ok in ((" a\n-b\n+c\n", True), (" a\n-b\n+c\n+d\n", False), (" a\n+c\n", False)):
        with tempfile.NamedTemporaryFile("w", suffix=".patch") as sample:
            sample.write("diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1,2 +1,2 @@\n" + body)
            sample.flush()
            assert (check(sample.name) is None) == ok, body
    sys.exit(print("self-test OK"))

errors = [error for error in map(check, sys.argv[1:]) if error]
print("\n".join(errors) or f"{len(sys.argv) - 1} patches OK")
sys.exit(1 if errors else 0)
