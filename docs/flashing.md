# Flashing with Odin

`onigiri build_odin` writes `out/Onigiri_AP_<model>_<firmware>_<commit>_<date>.tar.md5`, an AP
package with `boot`, `init_boot`, `vendor_boot`, `dtbo`, `vbmeta`, `recovery` and `super`, all
LZ4 compressed.

- **First install**: flash the stock Flip5 BL, CP and CSC (CSC wipes data; HOME_CSC keeps it)
  together with the Onigiri AP. Never flash Fold5 bootloader, modem or hardware partitions.
- **Updates**: the AP alone keeps your data. Once a release is installed, the next one also
  comes over the air: Settings > Onigiri Software > Software update (see
  [releasing.md](releasing.md)).

Samsung Odin3 on Windows and [brokkr](https://github.com/Gabriel2392/brokkr-flash) (Windows,
macOS, Linux and Android) take the `.tar.md5` in the AP slot as is. With
2026.10.20, a CSC flash ends at "Can't load Android system" on the inner screen: choose Factory data
reset. Later builds do that reset themselves.

## Linux and macOS: odin4

[odin4](https://github.com/Llucs/odin4) works with two fixes, tested on an Apple Silicon Mac
flashing an SM-F731B.

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

### 2. Flash

odin4 unpacks each image to a temporary file first, so keep about 9 GB free there. Packages up
to 2026.10.20 aren't shaped for odin4 (it lands their super image corrupted, and the phone
boot loops with `liblp: invalid geometry magic` in `/proc/last_kmsg`): flash a later release.

Boot Download Mode with `adb reboot download` (or hold both volume keys while plugging in
USB), then:

```sh
sudo ./build/odin4 -l                      # the phone must be listed
sudo ./build/odin4 --reboot -a out/Onigiri_AP_*.tar.md5
```

For a first install add `-b BL_<...>.tar.md5 -c CP_<...>.tar.md5 -s CSC_<...>.tar.md5` from the
stock firmware.

- **One session per Download Mode boot.** After a failed or `--check-only` run the phone ignores
  further sessions: restart Download Mode before trying again.
- odin4 can end with `Failed to send reboot command` (exit code 3) after the last image. The
  images are written; if the phone stays in Download Mode, hold Volume Down and Power.
- `BOOTLOADER_FAIL code=3` on super means the image is not a sparse image.
- `METADATA` is write-protected (`code=-5`); don't add it to a package.
