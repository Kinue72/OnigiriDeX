# Flashing with Odin

`onigiri build_odin` writes `out/Onigiri_AP_<model>_<firmware>_<commit>_<date>.tar.md5`, an AP
package with `boot`, `init_boot`, `vendor_boot`, `dtbo`, `vbmeta`, `recovery` and `super`, all
LZ4 compressed.

- **First install**: flash the stock Flip5 BL, CP and CSC (CSC wipes data; HOME_CSC keeps it)
  together with the Onigiri AP. Never flash Fold5 bootloader, modem or hardware partitions.
- **Updates**: the AP alone keeps your data. Once a release is installed, the next one also
  comes over the air: Settings > Onigiri Software > Software update (see
  [releasing.md](releasing.md)).

Samsung Odin3 on Windows takes the `.tar.md5` in the AP slot as is. This has not been tested on
the current builds; if it reports PASS but the phone boot-loops, use odin4 as below.

## Linux and macOS: odin4

[odin4](https://github.com/Llucs/odin4) works with three changes, all tested on an Apple
Silicon Mac flashing an SM-F731B.

### 1. Build odin4 with two fixes

```sh
git clone https://github.com/Llucs/odin4
cd odin4
git apply /path/to/OnigiriDeX/scripts/odin4/0001-Fix-handshake-and-large-tar-sizes.patch
cmake -B build -DODIN4_BUILD_GUI=OFF && cmake --build build
```

The patch (against upstream `b8630fb`) fixes:

- the handshake on 0x685d bootloaders, which NAK the first bulk transfer until the endpoints
  are cleared ([#284](https://github.com/Llucs/odin4/issues/284));
- `Invalid TAR size field` for images of 8 GiB or more, which GNU tar stores in base-256
  ([#288](https://github.com/Llucs/odin4/issues/288)). Onigiri's super image is ~8.9 GB.

On macOS also remove the Linux-only link flags from `CMakeLists.txt` (`-static-libgcc`,
`-static-libstdc++`, `-z relro`, `-z now`, `-pie`), and run odin4 with `sudo`: macOS binds its
USB modem driver to the Odin interface, and only root can claim it. While the Mac is locked,
macOS holds new USB accessories until you allow them.

### 2. Repack the AP for odin4

```sh
python3 scripts/make_odin4_ap.py out/Onigiri_AP_*.tar.md5 out/AP_odin4.tar
```

It needs the `lz4` CLI and about 18 GB free next to the output file. What it changes, and why:

| Problem | Symptom | Fix |
|---|---|---|
| odin4's compressed download only takes LZ4 frames of one block, so it unpacks every real image to a temporary file first | an extra ~9 GB write for super | images are stored plain |
| FILL chunks in the super sparse image | every step acknowledged, then a boot loop; `/proc/last_kmsg` shows `liblp: invalid geometry magic` | FILL chunks expanded to RAW, as in Samsung's own super images |
| odin4 pads large images to 512 bytes | the image after super fails with `BOOTLOADER_FAIL code=11` | the largest DONT_CARE chunk is split until the sparse file is a multiple of 512 bytes, and super goes last |

### 3. Flash

Boot Download Mode with `adb reboot download` (or hold both volume keys while plugging in
USB), then:

```sh
sudo ./build/odin4 -l                      # the phone must be listed
sudo ./build/odin4 --reboot -a out/AP_odin4.tar
```

For a first install add `-b BL_<...>.tar.md5 -c CP_<...>.tar.md5 -s CSC_<...>.tar.md5` from the
stock firmware.

- **One session per Download Mode boot.** After a failed or `--check-only` run the phone ignores
  further sessions: restart Download Mode before trying again.
- odin4 can end with `Failed to send reboot command` (exit code 3) after the last image. The
  images are written; if the phone stays in Download Mode, hold Volume Down and Power.
- `BOOTLOADER_FAIL code=3` on super means the image is not a sparse image.
- `METADATA` is write-protected (`code=-5`); don't add it to a package.
