#!/usr/bin/env python3
"""Usage: ota_chain.py <output .zip> <package .zip>...

Chains incremental OTA packages into one that installs them in order in a single recovery run, so a
phone several releases behind updates with one download and one restart. Each package must be made
from the build the one before it updates to (release.sh chains the previous release's packages with
its own); a package may itself be a chain. The output is unsigned: sign it with signapk -w.

Each hop keeps its own script and files under a directory named after its script's hash, and the
chain's script runs every hop's script in turn: each still checks the blocks it reads before it
writes, so a hop only patches what the hop before it left. An interrupted install restarts the
chain, so after each hop the script records it in misc's stage field (the bootloader message, which
recovery clears once the install ends) and skips the hops already done.
"""
import hashlib
import re
import sys
import zipfile

MISC = "/dev/block/bootdevice/by-name/misc"
SCRIPT = "META-INF/com/google/android/updater-script"
# The updater and metadata (Samsung's fingerprints, which every Onigiri build keeps) come from the
# last hop.
KEPT = ("META-INF/com/android/metadata", "META-INF/com/android/metadata.pb",
        "META-INF/com/google/android/update-binary", "META-INF/com/android/otacert")
EPOCH = (2009, 1, 1, 0, 0, 0)


def hops(package):
    """[(id, script, {name: ZipInfo})] of a package, oldest hop first."""
    names = package.namelist()
    if "hops" not in names:
        files = {n: package.getinfo(n) for n in names if not n.startswith("META-INF/")}
        script = package.read(SCRIPT).decode()
        return [(hashlib.sha1(script.encode()).hexdigest()[:12], script, files)]
    result = []
    for hop in package.read("hops").decode().split():
        prefix = hop + "/"
        files = {n[len(prefix):]: package.getinfo(n) for n in names
                 if n.startswith(prefix) and n != prefix + "updater-script"}
        result.append((hop, package.read(prefix + "updater-script").decode(), files))
    return result


def hop_script(hop, script, files, share):
    # Point the hop's file names at its directory, and give its progress steps its share of the bar.
    script = re.sub(r'"([^"\\]*)"', lambda m: f'"{hop}/{m[1]}"' if m[1] in files else m[0], script)
    return re.sub(r"show_progress\(([0-9.]+),",
                  lambda m: f"show_progress({float(m[1]) * share:.6f},", script)


def chain_script(chain):
    lines = []
    for i, (hop, script, files) in enumerate(chain):
        # Run this hop unless it or a later one already finished.
        pending = " && ".join(f'get_stage("{MISC}") != "onigiri:{later}"' for later, _, _ in chain[i:])
        lines += [f"# ---- Hop {i + 1} of {len(chain)} ----",
                  f'if {pending} then',
                  f'ui_print("Installing update {i + 1} of {len(chain)}...");',
                  hop_script(hop, script, files, 1 / len(chain)).rstrip(),
                  f'set_stage("{MISC}", "onigiri:{hop}");',
                  "endif;"]
    lines.append(f'set_stage("{MISC}", "");')
    return "\n".join(lines) + "\n"


def entry(name, compress_type):
    info = zipfile.ZipInfo(name, EPOCH)
    info.compress_type = compress_type
    info.external_attr = 0o644 << 16
    return info


def main(output, packages):
    sources = [zipfile.ZipFile(p) for p in packages]
    chain = [(hop, script, files, source) for source in sources for hop, script, files in hops(source)]
    ids = [hop for hop, _, _, _ in chain]
    if len(set(ids)) != len(ids):
        raise SystemExit("ota_chain: a hop shows up twice; the packages don't follow each other")
    last = sources[-1]
    with zipfile.ZipFile(output, "w") as out:
        # Recovery reads the metadata first; block_image_update maps patch data, so each file keeps
        # its compression.
        for name in KEPT:
            out.writestr(entry(name, last.getinfo(name).compress_type), last.read(name))
        out.writestr(entry("hops", zipfile.ZIP_STORED), "\n".join(ids) + "\n")
        for hop, script, files, source in chain:
            out.writestr(entry(f"{hop}/updater-script", zipfile.ZIP_DEFLATED), script)
            for name, info in files.items():
                with source.open(info) as data, out.open(entry(f"{hop}/{name}", info.compress_type), "w") as dest:
                    while block := data.read(1 << 20):
                        dest.write(block)
        out.writestr(entry(SCRIPT, zipfile.ZIP_DEFLATED),
                     chain_script([(hop, script, files) for hop, script, files, _ in chain]))


if __name__ == "__main__":
    if len(sys.argv) < 4:
        raise SystemExit(__doc__.split("\n\n")[0])
    main(sys.argv[1], sys.argv[2:])
