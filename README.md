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
for updates. Flash only Flip5 bootloader, modem and hardware partitions; see
[docs/flashing.md](docs/flashing.md) for Odin and odin4 (Linux/macOS).

## DeX display settings

Open **Settings → Onigiri Software → Display settings**. The external mode
picker lists resolutions and refresh rates advertised by the connected monitor.
Reconnect after changing the mode; **Automatic** restores the monitor default.
The mode summary shows the active output resolution and refresh rate. Rotation
applies immediately to the native DeX desktop. Both controls work independently
of the high refresh switch.

**DeX high refresh rate** is experimental and defaults off. It lets the external
display drive the compositor's frame timing instead of the 60 Hz cover display.
Reconnect after changing this switch. With a 2560×1600 144 Hz output, the native
scheduler test measured about 142 FPS in Chrome TestUFO, versus 60 FPS with the
original compositor. Individual applications can still impose their own limits.
The compositor can still be limited to 60 FPS while the cover screen is on.
The cover display keeps its native 60 Hz configuration, and thermal and battery
saver policies still apply.

Rebuild the kernel, Android 15 display policy, SurfaceFlinger, and Settings for
these controls. The native patch checks the exact supported firmware binary and
stops the build if it differs; offsets must be reviewed for a firmware update.

## DeX zones

**Settings → Onigiri Software → Zones** (off by default) splits the DeX desktop
into a layout: a map column on the left or right, three columns, a grid or a
priority grid. Drag a window to a screen edge to snap it into the zone there;
while another zone holds a window, new windows open in the main zone.

Below the layouts, give each zone an app: it opens in that zone when it starts (a
window that is already open stays where it is), and all of them open by themselves
when the phone starts on a powered monitor (autoboot in the car) or car standby
brings it back. An app has one zone: giving it another moves it there.

![Zone layouts in Onigiri Software](docs/images/onigiri-settings-zones.png)

![DeX desktop with the Map left layout](docs/images/dex-zones-map-left.jpg)

![Zone apps opened in the Map and Main zones](docs/images/dex-zone-apps.jpg)

## Car head unit

For a phone that runs a car display from the cover screen, with wired DeX to a
monitor that passes the car's power through to the phone. Both switches are in
**Settings → Onigiri Software** and default off.

![Car switches in Onigiri Software](docs/images/onigiri-settings-car.png)

- **Power on when power connected** boots the phone from powered-off charging
  once the battery has 5%.
- **Car standby when power is lost** waits 60 s on battery, then turns on
  airplane mode, switches Wi-Fi, Bluetooth, location and sensors off, closes
  apps, forces deep idle and parks the big CPU cores. It stops powering the
  monitor, rechecks the USB-C link every 30 s (backing off to 2 min on a long
  park; the power key rechecks at once) and puts everything back when car
  power returns. It shuts the phone down after 4 days or below 10%.

The Flip5's USB-C controller has no sink-only mode, so the phone can't simply
wait for the monitor to supply power: the standby script cuts the phone's own
5 V within a millisecond whenever the controller turns it on, and swaps the
port's roles to find a monitor that has power again. Booted on a powered
monitor, the phone replugs the link once in software so DeX starts.

## Kernel and contributions

`external/kernel` is a pinned
[GoRhanHee submodule](https://github.com/GoRhanHee/android_kernel_samsung_sm8550).
The build applies the numbered patches in `external/patches/kernel/` and
reverses them on exit. Keep project changes in that patch series and the
submodule checkout clean.

Found a bug or have an improvement? [Open an issue](https://github.com/Kinue72/zflip5-dex/issues)
or [submit a pull request](https://github.com/Kinue72/zflip5-dex/pulls).
See [LICENSE](LICENSE) and [NOTICE](NOTICE) for licensing and attribution.
