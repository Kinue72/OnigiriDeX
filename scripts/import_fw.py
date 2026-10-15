#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import tempfile
import zipfile
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]


def verify_odin_package(path):
    with path.open("rb") as package:
        size = package.seek(0, os.SEEK_END)
        package.seek(max(0, size - 4096))
        trailer = re.search(rb"([0-9a-fA-F]{32})[ \t]+([^\r\n]+)\r?\n?\Z", package.read())
        if trailer is None or trailer[2].decode() != path.name.removesuffix(".md5"):
            raise ValueError(f"Invalid Odin checksum trailer: {path.name}")

        remaining = size - len(trailer[0])
        package.seek(0)
        digest = hashlib.md5()
        while remaining:
            chunk = package.read(min(1024 * 1024, remaining))
            if not chunk:
                raise ValueError(f"Truncated Odin package: {path.name}")
            digest.update(chunk)
            remaining -= len(chunk)

        if digest.hexdigest() != trailer[1].decode().lower():
            raise ValueError(f"Odin checksum mismatch: {path.name}")


def import_firmware(archive_path, spec, output):
    if output.exists() or output.is_symlink():
        raise FileExistsError(f"Firmware output already exists: {output}")

    with archive_path.open("rb") as source:
        checksum = hashlib.file_digest(source, "md5").hexdigest()
    if checksum != spec["md5"]:
        raise ValueError(f"ZIP checksum mismatch for {spec['model']} {spec['version']}")

    pda, csc, modem = spec["version"].split("/")
    prefixes = {
        "AP": f"AP_{pda}_",
        "BL": f"BL_{pda}_",
        "CP": f"CP_{modem}_",
        "CSC": f"CSC_OXM_{csc}_",
        "HOME_CSC": f"HOME_CSC_OXM_{csc}_",
    }

    with zipfile.ZipFile(archive_path) as archive:
        packages = {}
        for entry in archive.infolist():
            path = PurePosixPath(entry.filename)
            if path.is_absolute() or ".." in path.parts or "\\" in entry.filename:
                raise ValueError(f"Unsafe archive path: {entry.filename}")
            if stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError(f"Archive symlink is forbidden: {entry.filename}")
            if entry.is_dir():
                continue

            name = path.name
            if not name.endswith(".tar.md5"):
                if name.endswith(".txt"):
                    continue
                raise ValueError(f"Unexpected archive file: {entry.filename}")

            role = next((key for key, prefix in prefixes.items() if name.startswith(prefix)), None)
            if role is None:
                raise ValueError(f"Wrong firmware version: {name}")
            if role in packages:
                raise ValueError(f"Duplicate {role} package")
            packages[role] = entry

        for role in ("AP", "BL", "CP", "CSC"):
            if role not in packages:
                raise ValueError(f"Missing {role} package")

        output.parent.mkdir(parents=True, exist_ok=True)
        required = sum(entry.file_size for entry in packages.values())
        if shutil.disk_usage(output.parent).free < required + 1024 * 1024 * 1024:
            raise OSError(f"Insufficient disk space to import {spec['model']}")

        with tempfile.TemporaryDirectory(prefix=".import-", dir=output.parent) as temporary:
            staged = Path(temporary) / "firmware"
            staged.mkdir()
            for entry in packages.values():
                destination = staged / PurePosixPath(entry.filename).name
                print(f"Verifying {destination.name}", flush=True)
                with archive.open(entry) as source, destination.open("xb") as target:
                    shutil.copyfileobj(source, target, 1024 * 1024)
                verify_odin_package(destination)

            (staged / ".downloaded").write_text(spec["version"])
            if output.exists() or output.is_symlink():
                raise FileExistsError(f"Firmware output already exists: {output}")
            staged.rename(output)


def main():
    specs = json.loads((ROOT / "onigiri/configs/firmware.json").read_text())
    parser = argparse.ArgumentParser(description="Verify and import pinned Onigiri firmware")
    parser.add_argument("role", choices=specs)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    spec = specs[args.role]
    output = ROOT / "out/odin" / f"{spec['model']}_{spec['csc']}"
    try:
        import_firmware(args.archive, spec, output)
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        parser.exit(1, f"{error}\n")
    print(f"Imported {spec['model']} {spec['version']} into {output}")


if __name__ == "__main__":
    main()
