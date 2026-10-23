# High performance

Experimental. Profile loading and on/off control have been checked on the phone;
sustained performance and hot DeX/5G behaviour are not yet measured.

The Flip5 and Fold5 use the same SoC but different Samsung performance tables.
Onigiri keeps the Flip5's `LRP2` skin model and its battery, charging, modem
hardware, and emergency protection. High performance is opt-in and off by default.

With an external cooler running, the profile:

- Uses the Fold5 CPU/GPU and over-limit stages for normal and Light mode.
- Uses its CPU boost limits for app launch, typing, badges, calls, and wakeup.
- Moves the DeX 30 fps and DeX/multiwindow refresh restrictions from 45°C
  estimated SKIN temperature to 46°C. They release below 44°C instead of 43°C.
- Moves the default XXV 5G cell-drop, SA-disable, LTE carrier, and final modem
  low-power restrictions from 42.5–45°C to 46°C SKIN. They release below 44°C.
  Regional overrides stay stock.

Samsung enters each stage at its own threshold and leaves it below the previous
one, so `temp="440:460"` restricts at 46°C, one degree before the emergency stage.

The original 47°C SKIN emergency/DeX protection remains. Camera, brightness,
Wi-Fi, low-temperature, and sensor-calibration settings remain stock. This
option relaxes thermal limits without raising peak CPU/GPU clocks, faking
temperatures, or stopping either thermal service.
60–75°C CPU-core temperature is not equivalent to 60–75°C SKIN or battery
temperature; the profile does not raise battery or chassis limits to that range.

After installing a ROM containing this patch, open **Settings → Onigiri Software
→ High performance**. In Vietnamese, the option is **Hiệu năng cao**. The switch
is off by default and is shown only for the supported Flip5 thermal policy. Turn it on
with an external cooler running, then use the restart prompt to apply the change.
Turning it off also requires a restart to reload Samsung Device Health's policy.

The root command equivalent uses the property's internal name:

```sh
su -c 'setprop persist.sys.onigiri.overclocking true'
```

An unset or false property uses the original Flip5 policy. The previous
experimental `cooler` flag does not enable High performance. To disable it with
root:

```sh
su -c 'setprop persist.sys.onigiri.overclocking false'
```

Restart after either command to apply it. Keep the switch off when the cooler
is detached. There is no automatic cooler detection.

Samsung Device Health (SDHMS) must be installed and enabled for the profile to
load. If a debloat or thermal-disable tool removed it, the switch can still save
the choice, but changing the property alone cannot restore that service.

The generated policy is an APK asset, not an editable app-data file. An absent
or malformed asset falls back to the stock policy. A rejected cooler table also
retries the stock Flip5 policy before Samsung's generic fallback. The build checks the exact
three Samsung input-table hashes and stops on an unsupported donor version.

Host checks:

```sh
python3 -B scripts/tests/test_cooler_policy.py
bash -n target/b5q/patches/thermal/customize.sh
python3 scripts/check_patches.py target/b5q/patches/thermal/smali/system/priv-app/SamsungDeviceHealthManagerService/SamsungDeviceHealthManagerService.apk/0001-Load-opt-in-cooler-policy.patch
python3 scripts/check_patches.py onigiri/mods/settings/smali/system/priv-app/SecSettings/SecSettings.apk/0024-Add-overclocking-toggle.patch
```

On 2026-10-24, a temporary overlay was tested on the rooted SM-F731B running
Onigiri `3a6bf5f` / One UI 7. Samsung Device Health loaded the cooler policy,
switched back to stock when disabled, and loaded the cooler policy again when
enabled. The native Samsung and Qualcomm thermal services stayed running and
reported real temperatures. No policy rejection or application crash appeared
in either mode. The overlay disappears on reboot; a ROM build is still needed
for a permanent installation. That policy-loading check used the previous
experimental `cooler` flag.

The Settings switch was then tested on the phone with a temporary Settings APK
overlay: English and Vietnamese rendered correctly on the cover display, both
on/off changes saved `persist.sys.onigiri.overclocking`, and each showed the
restart prompt. The final switch state is off, the app's original
language preference was restored, and the phone was not rebooted. Both the
Settings APK and the renamed thermal loader assembled successfully on the host.

The display name was then corrected to **High performance** / **Hiệu năng cao**.
Both labels were verified on the phone. The preview update changed only its
resource table; the controller, saved property, and off-by-default behavior stayed
the same.

Review then found that the tested table entered the DeX and multiwindow limits
at 48°C, above the emergency stage. The table now enters every relaxed limit at
46°C and leaves the app-casting rules stock. The corrected table has not been
loaded on the phone.

The user had removed SDHMS before this Settings check. Android could not restore
it with `install-existing`, and installing its original system APK was rejected
with `INSTALL_FAILED_REJECTED_BY_BUILDTYPE`. The original SDHMS APK was restored
at its system path, but its package/service remains absent. Loading the profile
through the renamed flag therefore remains unverified on this phone. The native
Samsung and Qualcomm thermal services were not disabled by these changes.

Neither host checks nor that loading/control check establishes a sustained
performance gain or 5G stability. The 46°C transitions have not been triggered
under a real hot workload, and the 47°C emergency behaviour has not been
heat-tested. Those checks require measurements under the intended workload.
