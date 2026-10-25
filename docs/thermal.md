# High performance

Experimental. Measured on the phone with a 144 Hz DeX monitor and an external
cooler; hot 5G behaviour and the 46/47°C transitions are not yet measured.

The Flip5 and Fold5 use the same SoC but different Samsung performance tables.
Onigiri keeps the Flip5's `LRP2` skin model and its battery, charging, modem
hardware, and emergency protection. High performance is opt-in and off by default.

With an external cooler running, the profile:

- Keeps the CPU minimum clocks at 1.23/1.40/1.36 GHz (little/gold/prime) instead
  of 0.56/0.61/0.86 GHz, so frames are not missed while the CPU ramps up.
- Uses the Fold5 CPU/GPU and over-limit stages for normal and Light mode, with
  higher minimums in the first two normal-mode stages: GPU 550/401 MHz instead of
  348/295, CPU 2.09/1.84 GHz instead of 1.84/1.59. The last two stages stay
  Fold5, so Samsung's loop can still pull SKIN back before the emergency stage.
- Uses the Fold5 CPU boost limits for app launch, typing, badges, calls, and wakeup.
- Moves the DeX 30 fps and DeX/multiwindow refresh restrictions from 45°C
  estimated SKIN temperature to 46°C. They release below 44°C instead of 43°C.
- Moves the default XXV 5G cell-drop, SA-disable, LTE carrier, and final modem
  low-power restrictions from 42.5–45°C to 46°C SKIN. They release below 44°C.
  Regional overrides stay stock.

Samsung enters each stage at its own threshold and leaves it below the previous
one, so `temp="440:460"` restricts at 46°C, one degree before the emergency stage.
Under sustained load its CPU/GPU loop holds SKIN at a stage and clamps to that
stage's minimum, which is why the minimums matter more than the thresholds.

The original 47°C SKIN emergency/DeX protection remains. Camera, brightness,
Wi-Fi, low-temperature, and sensor-calibration settings remain stock. This
option does not raise peak CPU/GPU clocks, fake temperatures, or stop either
thermal service. Thermal caps still win over the minimum clocks: the kernel
clamps a minimum to a lower maximum.
60–75°C CPU-core temperature is not equivalent to 60–75°C SKIN or battery
temperature; the profile does not raise battery or chassis limits to that range.

After installing a ROM containing this patch, open **Settings → Onigiri Software
→ High performance**. In Vietnamese, the option is **Hiệu năng cao**. The switch
is off by default and is shown only for the supported Flip5 thermal policy. Turn it on
with an external cooler running, then use the restart prompt to apply the change.
Turning it off also requires a restart to reload Samsung Device Health's policy
and the vendor minimum clocks.

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
the choice, but changing the property alone cannot restore that service. SDHMS
writes the minimum clocks when it loads the profile; it runs as `system_app`,
which may write cpufreq nodes (init may not).

The generated policy is an APK asset, not an editable app-data file. An absent
or malformed asset falls back to the stock policy. A rejected cooler table also
retries the stock Flip5 policy before Samsung's generic fallback. The build checks the exact
three Samsung input-table hashes and stops on an unsupported donor version.

Host checks:

```sh
python3 -B scripts/tests/test_cooler_policy.py
bash -n target/b5q/patches/thermal/customize.sh
python3 scripts/check_patches.py target/b5q/patches/thermal/smali/system/priv-app/SamsungDeviceHealthManagerService/SamsungDeviceHealthManagerService.apk/0001-Load-opt-in-cooler-policy.patch
python3 scripts/check_patches.py onigiri/mods/settings/smali/system/priv-app/SecSettings/SecSettings.apk/0026-Add-high-performance-toggle.patch
```

## Measured

On 2026-10-25 the phone ran Onigiri `6e39c55` with the generated table and the
patched loader bind-mounted over its own SDHMS, a 2560x1600 144 Hz monitor in
DeX, the cooler attached, and the room air-conditioned. Fps is Chrome's content
layer from SurfaceFlinger; "missed" counts frames shown for two or more vsyncs.

TestUFO (light; SKIN 35°C, no thermal caps active):

| | fps | missed |
| --- | --- | --- |
| Stock | 127–131 | 9–18% |
| Fold5 table only | 128 | 12% |
| High performance | 143 | 0.5% |

SurfaceFlinger missed no frames in the stock runs: Chrome missed them while the
CPU ramped up from its minimum. The gold cluster floor alone gave 141 fps.

WebGL Aquarium, 5000 fish, full screen (heavy; 8 minutes from 35°C SKIN):

| | first 90 s | steady | GPU cap | SKIN |
| --- | --- | --- | --- | --- |
| Stock | 80 → 60 fps | 60 fps | 348 MHz | 38.9°C |
| Fold5 table only | 89 → 61 fps | 60.5 fps | 348 MHz | 39.0°C |
| High performance | 104 → 91 fps | 69 fps | 401 MHz | 40.6°C |

The reported battery temperature stayed at 36.4°C. With the Fold5 table alone
both runs settled on the first stage's 348 MHz GPU minimum, which is what the
raised minimums change. SDHMS loaded the profile through
`persist.sys.onigiri.overclocking`, wrote the minimum clocks, and Qualcomm's perf
HAL restored them after its launch boosts. No policy rejection or crash appeared.

Earlier checks (2026-10-24): Samsung Device Health switched between the stock
and cooler policies on demand while the native Samsung and Qualcomm thermal
services kept running with real temperatures. The Settings switch rendered in
English and Vietnamese, saved the property, and offered a restart for each change.
