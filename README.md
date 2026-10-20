# OnigiriDeX

Onigiri is a custom system for the **Galaxy Z Flip5 (SM-F731B)**. It's built on Android 15 / One UI 7 and based on [UN1CA](https://github.com/salvogiangri/UN1CA/tree/fifteen).

## What it does

- Runs the whole phone on the **small outside screen** because this uses the software from the **Galaxy Z Fold5**, so the outside screen works like a full phone screen.
- Lets you plug the phone into a monitor and use **Samsung DeX** (a desktop mode, like a small computer).
  A live wallpaper you set for the home screen, like one from Wallpaper
  Engine, shows on the DeX desktop too. Pick a wallpaper in DeX's own
  settings to go back to a picture there.
- Can split the DeX desktop into **zones** and open your favourite apps in them.
- Can work as a **car screen**: it turns on with the car and sleeps when the car turns off.
- Comes with root access (KernelSU + susFS) built in.

## Please read first

**Most of this project was written by AI, and only part of it has been checked
by a person.** The maintainer doesn't have time to review every change.

Installing it can wipe your phone or stop it from starting up. Before you try:

- Back up everything you care about.
- Keep a copy of the original Samsung software so you can go back.

**Use it at your own risk.**

## Installing

**You need:**

- A Galaxy Z Flip5 **SM-F731B**. Other Flip5 models don't work.
- An **unlocked bootloader**. Unlocking wipes the phone: turn on *OEM unlocking*
  in Developer options, turn the phone off, hold both volume keys while you
  plug in USB, then hold Volume Up and follow the screen.
- The original Samsung software **F731BXXS5EYI1** for the SM-F731B (search for
  that version on a Samsung firmware site). You only use its BL, CP and CSC
  files.
- A computer with Odin: Odin3 on Windows, or odin4 on Linux and macOS.

**1. Download Onigiri.** From the [latest release](https://github.com/Kinue72/OnigiriDeX/releases/latest),
download every `Onigiri_AP_….tar.md5.0`, `.1`, `.2`… part and the `.sha256`
file. GitHub can't hold the whole 8 GB file in one piece, so join the parts
into one file with the same name, without the number. The release notes show
the exact command for macOS, Linux and Windows.

**2. Check the download.** The `.sha256` file holds the file's checksum:
`sha256sum -c Onigiri_AP_*.sha256` on Linux, `shasum -a 256 -c Onigiri_AP_*.sha256`
on macOS, or compare it with `certutil -hashfile <file> SHA256` on Windows.

**3. Flash it.** Turn the phone off, then hold both volume keys while you plug
in USB, and press Volume Up to enter Download Mode.

- **Windows (Odin3):** put the Onigiri file in **AP**, and the BL, CP and CSC
  files from the Samsung software in their slots, then press Start. This hasn't
  been tested with the current builds yet; if the phone keeps restarting
  afterwards, use odin4.
- **Linux and macOS (odin4):** follow [docs/flashing.md](docs/flashing.md). It
  needs two small fixes to odin4 and a repacked AP; both are explained there.

Use **CSC** for the first install: it wipes the phone, which a phone coming
from Samsung's own software needs. Never flash Fold5 files.

The first start takes a few minutes.

**Updating.** Open **Settings → Onigiri Software → Software update** and tap
it. When a new version is out, tap again: the phone downloads only what
changed, restarts, installs it in about a minute and starts again. Your data
stays. If it says the new version needs a full flash, flash just the new AP
(no BL, CP or CSC): that keeps your data too.

## Extra features

Everything Onigiri adds lives in **Settings → Onigiri Software**. Here's what
each part does.

### DeX zones

![Zone layouts in Onigiri Software](docs/images/onigiri-settings-zones.png)

Off by default. Zones split the monitor into fixed areas, like a map on one
side and other apps next to it. You can pick a map on the left or right, three
columns, a grid, or a priority grid.

- **Snap windows**: drag a window to the edge of the screen and it fills the
  zone there.
- **New windows** open in the main zone.
- **Zone apps**: pick an app for each zone. It opens in its zone every time it
  starts, and all of them open by themselves when the phone starts on a
  monitor (handy in the car). Each app can only have one zone.

![DeX desktop with the Map left layout](docs/images/dex-zones-map-left.jpg)

![Zone apps opened in the Map and Main zones](docs/images/dex-zone-apps.jpg)

### Phone settings

![Sleep when folded, power on and car standby switches, and the car standby shutdown time](docs/images/onigiri-settings-car.png)

- **Power on when power connected**: when the phone is off and gets power, it
  turns on by itself once the battery reaches 5%.
- **Car standby when power is lost**: when the car turns off, the phone waits
  a minute and then goes into a deep sleep to save battery. It turns on
  airplane mode, turns off Wi-Fi, Bluetooth and location, closes apps and
  stops powering the monitor. It checks every 30 seconds whether the car is
  back (less often after a long time, or right away if you press the power
  button), and turns everything back on when it is. If the car stays off
  longer than **Shut down after** (1 hour to 4 days, 4 days by default), or
  the battery drops below 10%, the phone shuts down.

### Monitor settings

![DeX monitor settings](docs/images/onigiri-settings-display.png)

- **External display mode**: pick the resolution and refresh rate for your
  monitor. The list shows what your monitor supports. Unplug and plug the
  cable back in after changing it. Choose **Automatic** to go back to the
  monitor's default.
- **External display rotation**: turns the desktop on the monitor. It changes
  right away.
- **DeX high refresh rate** (experimental, off by default): lets the desktop
  run smoother than 60 frames per second on fast monitors. In testing, a
  144 Hz monitor reached about 142 frames per second instead of 60. Unplug and
  plug the cable back in after turning it on. Some apps may still run slower,
  and it may stay at 60 while the phone's own screen is on. Battery saver and
  overheating protection still work as usual.

<details>
<summary><b>Boring stuffs</b></summary>

- **Allow secure screenshot**: lets you take screenshots in apps that normally
  block them.
- **Disable screenshot detection**: apps are no longer told when you take a
  screenshot.
- **Unlock higher FPS in games**: some games only offer their smoothest
  settings on certain phones. This makes them think you have one of those
  phones.
- **Hide developer status from apps**: some apps, often banking apps, refuse
  to work when developer options are turned on. This hides it from them.
- **Sleep when folded**: turns the screen off and locks the phone when you
  close it.
- **Play Integrity Fix**: helps apps that check whether your phone has been
  changed, like Google Wallet or banking apps, keep working. The date shows
  which version you have. Tap the name to check for a newer one.
- **Play power on sound effect**: plays Samsung's sound when the phone starts.
  Off by default.
- **Enable live blur effect**: gives menus and panels a frosted-glass look.
  The phone needs a restart after you change it.
- **Allow application downgrade**: lets you install an older version of an
  app over a newer one.
- **Disable low target SDK block**: lets you install very old apps that
  Android 15 normally refuses.
- **Disable ASKS**: turns off a Samsung security check that can stop some
  apps from installing or running.

</details>

<details>
<summary><b>Building it yourself</b></summary>

You need a Linux computer with Bash, Python 3 and Java 17.

**1. Get the code and tools**

```sh
git clone --recurse-submodules https://github.com/Kinue72/OnigiriDeX.git
cd OnigiriDeX
bash
source ./buildenv.sh SM-F731B
onigiri build_dependencies
```

**2. Download the original Samsung software**

Put these full firmware ZIP files in the `firmware/` folder:

- Flip5: SM-F731B / XXV / F731BXXS5EYI1
- Fold5: SM-F946B / XXV / F946BXXS5EYI1
- Galaxy S24 (only used for screen colours): SM-S921B / S921BXXS9BYH1

**3. Build**

Change the file names below to match the files you downloaded:

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

The finished files show up in the `out/` folder.

**4. Install it on the phone**

Flash `out/Onigiri_AP_….tar.md5` as in [Installing](#installing), or follow
[docs/flashing.md](docs/flashing.md) for odin4. [docs/releasing.md](docs/releasing.md)
explains how releases and over-the-air updates are made.

A few things to keep in mind:

- The build creates two private keys, `security/onigiri_platform.pk8` and
  `security/onigiri_ota.pk8` (recovery only installs updates signed with it).
  Keep them safe, don't share them, and use the same ones for every future update.
- Only install the Flip5's own low-level parts (bootloader, modem and
  hardware files). Never put Fold5 ones on the phone.
- Parts of the build are made for this exact Samsung software version. If you
  use a newer version, the build will stop on purpose so nothing breaks
  quietly.

</details>

## For contributors

The kernel (the core of the system) comes from
[GoRhanHee's kernel](https://github.com/GoRhanHee/android_kernel_samsung_sm8550) and lives in `external/kernel`. Our own changes are kept as numbered patch
files in `external/patches/kernel/`. The build adds them in and removes them
again when it's done. Please put your kernel changes there and leave
`external/kernel` itself untouched.

## Help and feedback

Found a problem or have an idea? [Open an issue](https://github.com/Kinue72/OnigiriDeX/issues) or [send a pull request](https://github.com/Kinue72/OnigiriDeX/pulls).

See [LICENSE](LICENSE) and [NOTICE](NOTICE) for license and credits.
