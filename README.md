# Onigiri

Android 15 / One UI 7 firmware for **Galaxy Z Flip5 SM-F731B (XXV)**, based on
[UN1CA fifteen](https://github.com/salvogiangri/UN1CA/tree/fifteen) and
[ArtisanROM](https://github.com/ArtisanROM/ArtisanROM).

Uses the Fold5 system on the cover display, with wired DeX, official KernelSU
and SUSFS. The inner display is disabled.

**This project is AI slop with limited manual review. Use at your own risk.**
The maintainer has little time to inspect every change. Back up your data and
keep stock firmware available; flashing can erase data or leave the phone
unable to boot.

## Build

Use Linux, Bash, Python 3 and Java 17.

```sh
git clone --recurse-submodules https://github.com/Kinue72/zflip5-dex.git
cd zflip5-dex
bash
source ./buildenv.sh SM-F731B
onigiri build_dependencies
```

Place the full firmware ZIPs in `firmware/`:

- Flip5: SM-F731B / XXV / F731BXXS5EYI1
- Fold5: SM-F946B / XXV / F946BXXS5EYI1
- S24 adaptive colour assets: SM-S921B / S921BXXS9BYH1

Replace these example filenames with the downloaded filenames:

```sh
python3 scripts/import_fw.py target firmware/flip5.zip
python3 scripts/import_fw.py donor firmware/fold5.zip
onigiri extract_fw
onigiri extract_fw --ignore-source --ignore-target SM-F946B/XXV
python3 scripts/extract_adaptive_display.py firmware/s24.zip
source ./buildenv.sh SM-F731B
onigiri build_kernel
onigiri make_rom
onigiri build_odin
```

Output is in `out/`. Keep `security/onigiri_platform.pk8` private and reuse it
for updates. Flash only Flip5 bootloader, modem and hardware partitions.

## Kernel and contributions

`external/kernel` is a pinned
[GoRhanHee submodule](https://github.com/GoRhanHee/android_kernel_samsung_sm8550).
The build applies the numbered patches in `external/patches/kernel/` and
reverses them on exit. Keep project changes in that patch series and the
submodule checkout clean.

Found a bug or have an improvement? [Open an issue](https://github.com/Kinue72/zflip5-dex/issues)
or [submit a pull request](https://github.com/Kinue72/zflip5-dex/pulls).
See [LICENSE](LICENSE) and [NOTICE](NOTICE) for licensing and attribution.
