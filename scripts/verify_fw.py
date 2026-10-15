#!/usr/bin/env python3

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read_values(path):
    values = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or (key in values and values[key] != value):
            raise ValueError(f"Invalid or duplicate property in {path.name}: {key}")
        values[key] = value
    return values


def verify_firmware(folder, spec):
    system = read_values(folder / "system/system/build.prop")
    vendor = read_values(folder / "vendor/build.prop")
    expected = (
        (vendor, "ro.product.vendor.model", spec["model"], "model"),
        (vendor, "ro.product.vendor.device", spec["device"], "device"),
        (system, "ro.build.version.incremental", spec["version"].split("/")[0], "version"),
        (system, "ro.build.version.sdk", str(spec["sdk"]), "SDK"),
    )
    for properties, key, value, description in expected:
        if properties.get(key) != value:
            raise ValueError(f"Firmware {description} mismatch: expected {value}, found {properties.get(key)!r}")

    metadata = read_values(folder / "os_partitions_metadata.txt")
    group = metadata.get("super_partition_group", "")
    if not re.fullmatch(r"[A-Za-z0-9_]+", group):
        raise ValueError("Invalid super partition geometry: group name")
    try:
        size = int(metadata["super_partition_size"])
        group_size = int(metadata[f"super_{group}_group_size"])
    except (KeyError, ValueError) as error:
        raise ValueError("Invalid super partition geometry: missing size") from error
    if not 0 < group_size < size:
        raise ValueError("Invalid super partition geometry: group exceeds partition")

    partitions = metadata.get(f"super_{group}_partition_list", "").split()
    for partition in ("system", "vendor", "product", "odm", "system_ext"):
        if partition not in partitions or not (folder / partition).is_dir():
            raise ValueError(f"Missing extracted partition: {partition}")
        if metadata.get(f"{partition}_file_system") not in ("erofs", "ext4", "f2fs"):
            raise ValueError(f"Missing or unsupported {partition} filesystem metadata")
        for prefix in ("fs_config", "file_context"):
            path = folder / f"{prefix}-{partition}"
            if not path.is_file() or not path.stat().st_size:
                raise ValueError(f"Missing {partition} metadata: {path.name}")

    boot = folder / "kernel/boot.img"
    if not boot.is_file() or not boot.stat().st_size:
        raise ValueError("Missing target kernel image: boot.img")


def main():
    entries = json.loads((ROOT / "onigiri/configs/firmware.json").read_text())
    specs = {f"{spec['model']}/{spec['csc']}": spec for spec in entries.values()}
    parser = argparse.ArgumentParser(description="Verify original firmware identity and partition metadata")
    parser.add_argument("firmware", choices=specs)
    parser.add_argument("folder", type=Path)
    args = parser.parse_args()
    try:
        verify_firmware(args.folder, specs[args.firmware])
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")
    print(f"Verified original firmware: {args.firmware}")


if __name__ == "__main__":
    main()
