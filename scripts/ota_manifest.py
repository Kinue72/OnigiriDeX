#!/usr/bin/env python3
"""Usage: ota_manifest.py updates <output .json> <model> [<from version>:<package>]...
       ota_manifest.py manifest <output update.json> <tag> <version> <notes .md> <previous update.json | ""> <updates .json>...

Writes the update.json a release carries for Software update: what's new in this release and the
ones before it, and per model the package that updates each earlier build to this one. Each model
is released by its own job (scripts/release.sh --model), which describes its packages with
"updates"; "manifest" joins those when the release is published.

  {"tag": "2026.11.10", "version": "abc1234",
   "releases": [{"tag": "2026.11.10", "version": "abc1234", "date": "2026-11-10",
                 "new": ["Record the DeX desktop with Screen recorder"], "fixed": ["..."]}, ...],
   "updates": {"SM-F731B": {"<from version>": {"file": "Onigiri_OTA_<from>.zip", "size": 123, "sha256": "..."}}}}

What's new comes from GitHub's generated release notes: the titles of the pull requests merged
since the last release, "feat" ones under new and "fix" and "perf" ones under fixed. Other kinds
(docs, ci, build...) don't change the phone and are left out. Releases newest first, at most
HISTORY of them.
"""
import datetime
import hashlib
import json
import os
import re
import sys

HISTORY = 20
KINDS = {"feat": "new", "fix": "fixed", "perf": "fixed"}


def notes(markdown):
    """{"new": [...], "fixed": [...]} from GitHub's generated notes."""
    result = {"new": [], "fixed": []}
    for title in re.findall(r"^\* (.+?) by @\S+ in \S+$", markdown, re.M):
        match = re.match(r"(\w+)(?:\([^)]*\))?!?: (.+)", title)
        kind, text = (KINDS.get(match[1]), match[2]) if match else ("new", title)
        if kind:
            result[kind].append(text[0].upper() + text[1:].rstrip("."))
    return result


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        while block := f.read(1 << 20):
            digest.update(block)
    return digest.hexdigest()


def updates(output, model, packages):
    """One model's packages; a model without any (an AP-only release) isn't listed."""
    found = {}
    for spec in packages:
        source, path = spec.split(":", 1)
        found[source] = {"file": os.path.basename(path), "size": os.path.getsize(path), "sha256": sha256(path)}
    with open(output, "w") as f:
        json.dump({model: found} if found else {}, f)


def manifest(output, tag, version, notes_path, previous_path, updates_paths):
    with open(notes_path) as f:
        release = {"tag": tag, "version": version, "date": datetime.date.today().isoformat(), **notes(f.read())}
    history = []
    if previous_path:
        with open(previous_path) as f:
            history = [r for r in json.load(f)["releases"] if r["tag"] != tag]
    merged = {}
    for path in sorted(updates_paths):
        with open(path) as f:
            merged.update(json.load(f))
    with open(output, "w") as f:
        json.dump({"tag": tag, "version": version, "releases": [release, *history][:HISTORY],
                   "updates": merged}, f, indent=1, ensure_ascii=False)
        f.write("\n")


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "updates":
        updates(sys.argv[2], sys.argv[3], sys.argv[4:])
    elif len(sys.argv) >= 7 and sys.argv[1] == "manifest":
        manifest(*sys.argv[2:7], sys.argv[7:])
    else:
        raise SystemExit(__doc__.split("\n\n")[0])
