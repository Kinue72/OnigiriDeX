# OnigiriDeX

Onigiri is a custom system for the **Galaxy Z Flip5 (SM-F731B)**. It's built on Android 15 / One UI 7 and based on [UN1CA](https://github.com/salvogiangri/UN1CA/tree/fifteen).

## What it does

- Runs the whole phone on the **small outside screen** because this uses the software from the **Galaxy Z Fold5**, so the outside screen works like a full phone screen.
  With auto-rotate on, it also turns upside down, so you can hold the phone
  hinge down with the cameras on top.
- Lets you plug the phone into a monitor and use **Samsung DeX** (a desktop mode, like a small computer).
  A live wallpaper you set for the home screen, like one from Wallpaper
  Engine, shows on the DeX desktop too. Pick a wallpaper in DeX's own
  settings to go back to a picture there.
- Can split the DeX desktop into **zones** and open your favourite apps in them.
- Can work as a **car screen**: it turns on with the car and sleeps when the car turns off.
- Comes with root access (KernelSU + susFS) and
  [built-in app privacy components](#built-in-components).

## Please read first

**Most of this project was written by AI, and only part of it has been checked
by a person.** The maintainer doesn't have time to review every change.

Installing it can wipe your phone or stop it from starting up. Before you try:

- Back up everything you care about.
- Keep a copy of the original Samsung software so you can go back.

**Use it at your own risk.**

## Installing

**You need:**

- A Galaxy Z Flip5 **SM-F731B**. Other Flip5 models haven't been tested.
- An **unlocked bootloader**. You can only unlock it on Android 15 / One UI 7
  or older; some early Android 16 / One UI 8 builds can still be downgraded
  first.
- The original Samsung software [F731BXXS5EYI1](https://samfw.com/firmware/SM-F731B/XXV/F731BXXS5EYI1) for the SM-F731B. You only need its BL, CP and CSC files.
- Something to flash with, one of:
  - a computer: **Odin3** on Windows, **odin4** on Linux and macOS, or
    [brokkr](https://github.com/Gabriel2392/brokkr-flash) on any of them;
  - another Android phone with brokkr and a USB-C cable or OTG adapter between the two phones.

**1. Download Onigiri.** From the [latest release](https://github.com/Kinue72/OnigiriDeX/releases/latest),
download every `Onigiri_AP_….tar.md5.0`, `.1`, `.2`… part. GitHub can't hold
the whole 8 GB file in one piece, so join the parts
back into one file with the same name, minus the number at the end. The
release notes show the exact command for Windows, macOS and Linux; on an
Android phone, run the Linux command in [Termux](https://termux.dev).

**2. Check the download (optional).** To make sure nothing got corrupted,
download the `.sha256` file too and run `sha256sum -c Onigiri_AP_*.sha256` (Linux and
Termux) or `shasum -a 256 -c Onigiri_AP_*.sha256` (macOS); it should say `OK`.
On Windows, compare `certutil -hashfile <file> SHA256` with the number in the
`.sha256` file.

**3. Flash it.** Turn the Flip5 off, hold both volume keys while you plug in
USB, then press Volume Up to enter Download Mode. Put the Onigiri file in
**AP** and the Samsung BL, CP and CSC files in their slots.

- **Odin3 (Windows):** press Start.
- **odin4 (Linux, macOS):** follow [docs/flashing.md](docs/flashing.md). It
  needs two small fixes to odin4, explained there.
- **brokkr (Windows, macOS, Linux, Android):** start the flash. On Android,
  connect the two phones first.

Only odin4 has been tested with Onigiri so far. If the phone keeps restarting
after Odin3 or brokkr, flash it again with odin4.

Use **CSC** the first time: it wipes the phone, which a phone coming from
Samsung's own software needs. Never flash Fold5 files. The first start takes a
few minutes.

**Updating.** Open **Settings → Onigiri Software → Software update** and tap
it. When a new version is out, tap again: the phone downloads only what
changed, restarts, installs it in about a minute and starts again. Your data
stays. If it says the new version needs a full flash, flash just the new AP
(no BL, CP or CSC), which keeps your data too.

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

## Extra features

Onigiri's own settings live in **Settings → Onigiri Software**, in English or
Vietnamese following the phone's language. Here's what each part does.

### DeX zones

![Zone layouts in Onigiri Software](docs/images/onigiri-settings-zones.png)

Off by default. Zones split the monitor into fixed areas, like a map on one
side and other apps next to it. You can pick a map on the left or right, three
columns, a grid, or a priority grid.

- **Snap windows**: drag a window to the edge of the screen and it fills the
  zone there.
- **New windows** open in the main zone.
- **Zone apps**: pick an app for each zone. It opens in its zone every time it
  starts, and all of them open by themselves each time DeX starts on a wired
  monitor (handy in the car). Each app can only have one zone.

![DeX desktop with the Map left layout](docs/images/dex-zones-map-left.jpg)

![Zone apps opened in the Map and Main zones](docs/images/dex-zone-apps.jpg)

### Phone settings

![Sleep when folded, power on and standby switches, and the standby shutdown time](docs/images/onigiri-settings-car.png)

- **Power on when power connected**: when the phone is off and gets power, it
  turns on by itself once the battery reaches 5%.
- **Standby when unplugged**: when the car turns off, the phone waits
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
  cable back in after changing it. **Automatic** uses the monitor's default,
  or its fastest refresh rate while **DeX high refresh rate** or **Mirroring
  high refresh rate** is on.
- **External display rotation**: turns the desktop on the monitor. It changes
  right away.
- **DeX high refresh rate** (experimental, off by default): lets the desktop
  run smoother than 60 frames per second on fast monitors. In testing, a
  144 Hz monitor reached about 142 frames per second instead of 60. Unplug and
  plug the cable back in after turning it on. The outside screen can stay on,
  but it updates less often while the monitor runs faster. Some apps may still
  run slower. Overheating protection still works as usual.
- **Mirroring high refresh rate** (experimental, off by default): the outside
  screen only runs at 60 Hz, which holds a mirrored monitor to 60 frames per
  second too. With this on, opening the phone while it mirrors a monitor (DeX
  off) shows the 120 Hz inside screen instead, shaped to fill the monitor, and
  turns the outside one off. Plug the cable back in after turning it on, so
  the monitor switches to its fastest refresh rate.
  Closing the phone goes back to the outside screen. In testing, scrolling
  reached about 118 frames per second on a 144 Hz monitor, the most the
  inside screen can show.

Power saving holds every screen to 60 Hz, so the phone turns it off while it
charges and back on when charging stops, if it was on before.

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
- **Keep apps in cover rotation**: apps that only work upright, like TikTok
  and Messenger, no longer turn the outside screen sideways. They follow the
  screen's rotation instead. Off by default.
- **Allow application downgrade**: lets you install an older version of an
  app over a newer one.
- **Disable low target SDK block**: lets you install very old apps that
  Android 15 normally refuses.
- **Disable ASKS**: turns off a Samsung security check that can stop some
  apps from installing or running.

</details>

### Built-in components

**Settings → Onigiri Software** has a switch and a page for each component.
The switch saves your choice; Status shows what is running. Switch changes
and component updates take effect after a restart.

- **[HMA-OSS](https://github.com/frknkrc44/HMA-OSS)**: hides your other apps
  from the apps you pick. It comes set up for common banking, shopping,
  root checker and driver apps (Grab Driver, Green SM Driver, ShopeeFood
  Driver and beDriver/bePartner). **App rules** opens the original HMA app.
  Its backend loads directly in Android without Vector or Zygisk.
- **[TEESimulator](https://github.com/JingMatrix/TEESimulator)**: runs its
  standalone key-attestation service. Existing keys and app targets are kept.
  New installations use upstream's AOSP software key, which does not
  guarantee passing Play Integrity or any particular app's checks.
- **[BRENE](https://github.com/rrr333nnn333/BRENE)**: provides its essential
  **Hide custom ROM paths** and **Hide /system/addon.d** features through susFS.
  Both default to on. Its other features are not ported; developer options
  and USB or wireless debugging stay under your control.

Tap the version inside a component's page to check for an update, like PIF.
Onigiri's update feed selects compatible upstream releases and verifies
their hashes. Updates wait for a restart and keep the previous payload for
recovery. A release needing a different loader or configuration format
reports that a ROM update is required; TEESimulator v4 currently needs one.

The old first-boot module installer is disabled. Vector, NeoZygisk, Hybrid
Mount and Tricky Addon are no longer installed by the ROM. Existing modules
and their data remain untouched, and upgrades default the built-in switches
to off. A built-in component stays unavailable while its module copy is
enabled. Turn that copy off in KernelSU, enable the built-in switch, and
restart when you are ready to migrate. Keep the disabled module while testing;
BRENE's uninstall script deletes its saved configuration.

These adapters have host build and recovery tests. Loading hooks and the
native Settings pages still need validation on the Flip5 before release.
See [component integration and recovery](docs/essential-components.md).

## For contributors

The kernel (the core of the system) comes from
[GoRhanHee's kernel](https://github.com/GoRhanHee/android_kernel_samsung_sm8550) and lives in `external/kernel`. Our own changes are kept as numbered patch
files in `external/patches/kernel/`. The build adds them in and removes them
again when it's done. Please put your kernel changes there and leave
`external/kernel` itself untouched.

## Help and feedback

Found a problem or have an idea? [Open an issue](https://github.com/Kinue72/OnigiriDeX/issues) or [send a pull request](https://github.com/Kinue72/OnigiriDeX/pulls).

See [LICENSE](LICENSE) and [NOTICE](NOTICE) for license and credits.
