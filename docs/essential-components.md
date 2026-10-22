# Essential component integration

This replaces first-boot module installation with three built-in adapters. The
Settings design is option B: a main switch and a page per component, with
current status, component-specific controls, and a PIF-style version/update row.

## Payloads and scope

| Component | Bundled release | Built-in integration |
| --- | --- | --- |
| HMA-OSS | oss-173 | Original dex and signed manager; a guarded services.jar entry loads the backend without Vector or Zygisk. Config schema remains 93. |
| TEESimulator | v3.2, code 67 | Original arm64 injector, native library and dex run through an init service. |
| BRENE | v0.0.72 | Original susfs CLI and ROM-name list; only custom-ROM path and addon.d hiding are ported. |

The build verifies the original archives against `prebuilts/rootmods/manifest.json`
and `bundled.properties`. It never executes their installers. The HMA manager keeps
its upstream signing certificate. PIF's existing certificate handling remains
in place. This does not provide new keys, download keys, or guarantee an app's
integrity result.

`onigiri/mods/rootmods/disable` prevents the legacy installer and its payloads
from entering a new image. The original archives remain in the repository for
source provenance and recovery. NeoZygisk, Vector, Hybrid Mount and Tricky Addon
are not needed by these adapters and are not installed by the new image.

## Boot and migration

The pinned Samsung init.rc loads persistent properties in its main
`post-fs-data` action. The imported essential action then prepares immutable
boot snapshots and runs the BRENE rules before zygote starts. These two init
services have time limits so their failure cannot indefinitely block boot.

HMA loads on a daemon thread in system_server, once per boot. Its original
backend waits for Android services. After boot, the manager is matched to the
selected payload before its backend loads. An identical APK is left in place;
updates and rollbacks replace it while retaining app data and checking its
signing identity. Manager commands have deadlines; a stalled manager cannot
prevent the other components from completing their recovery checks. HMA's
readiness deadline starts after boot completion. TEESimulator starts after
boot and retries at most three times if its daemon exits.

Clean installations default the three features on. A phone with the legacy
installer's state or existing KernelSU modules defaults them off. Explicit
Settings choices take precedence on later boots. An enabled module copy, a
pending module installation/removal, or the recovery marker blocks the matching
built-in adapter. A disabled copy can stay installed for recovery.

For an existing phone, disable the matching module in KernelSU, enable the
built-in switch, and restart. Keep the disabled module while testing. BRENE's
uninstaller deletes `/data/adb/brene`, so uninstalling it is not a preservation
step. The new adapter never removes modules or changes their enabled state.

Existing HMA `config.json`, TEESimulator `keybox.xml` and `target.txt`, and
BRENE `config.sh` are preserved. BRENE's two initial choices are read as plain
data; its shell configuration is never executed. Developer options and USB or
wireless debugging are not modified. Multiple HMA data directories or an
unsupported HMA config schema fail closed instead of guessing which to use.

## Updates

Like PIF, the Settings action uses a curated feed:

`https://raw.githubusercontent.com/Kinue72/OnigiriDeX/main/prebuilts/rootmods/updates.properties`

This URL becomes available when this change reaches main. HMA, TEE and BRENE
have separate init updater services and locks. Downloads use HTTPS with
bounded sizes, timeouts and a fixed host/source allowlist. Whole-archive size,
SHA-256, module id and version code must match. Only named payload files are
extracted; module scripts, WebUIs and arbitrary archive paths are never run.
HMA manager updates also require the original package name and signing identity.

Payloads are staged under `/data/system/onigiri-essential/<id>/releases/<sha256>`.
A pending reference is published atomically only after extraction and SELinux
labeling complete. A restart selects that payload while preserving the previous
reference. If the switch is off, the payload is selected but runtime validation
waits until it is enabled. Another update is refused while a trial is unverified.
A ROM carrying a newer release or different adapter supersedes an older override.

The feed's `adapter` is a compatibility contract, not an upstream version:

- HMA adapter 1 requires its no-argument `ZygoteEntry.main()`, manager signing
  identity, config schema 93, and current status.json semantics.
- TEE adapter 1 requires the v3.2 entry point, current-directory injector
  layout, and `/data/adb/tricky_store` configuration. TEESimulator v4 changes
  these and is explicitly reported as requiring a ROM update.
- BRENE adapter 1 imports the ROM-name list and susfs binary; it does not
  start following the rest of BRENE's evolving scripts or settings.

To approve an upstream bump, review its entry points, config schema, native
dependencies and policy needs. Update the feed's source, digest, size and
version code from that release. Bump the adapter and ship a ROM update when
the integration contract changes. The live feed can advance independently of
the ROM's pinned inputs. For a newly bundled baseline, also update
`bundled.properties`, the archived ZIP and `manifest.json`. Run the host checks below and validate
the candidate on the target phone before publishing the feed change.

## Recovery and status

A persistent guard is written before a component executes. After Android
finishes booting, 60 consecutive seconds of Active status accepts the trial
and clears the guard. An unfinished start disables the feature on the next
boot and, for a trial update, restores the previous payload reference. On retry,
HMA also restores the matching manager, including a downgrade to the bundled
version, without enabling the general app-downgrade setting. A
system_server restart within the same boot does not inject HMA a second time.

For manual recovery, create this file as root or from recovery, then restart:

```text
/data/system/onigiri-essential/disable
```

It suppresses all three runtimes without deleting configuration. Remove that
marker only when ready to retry. KernelSU's module safe mode alone should not
be relied on to suppress a framework integration; use this explicit marker.

Desired switches are `persist.sys.onigiri.{hma,tee,brene}` and
`persist.sys.onigiri.brene.{rom_paths,addon_d}`. Boot snapshots are
`sys.onigiri.{hma,tee,brene}.enabled` and
`sys.onigiri.brene.{rom_paths,addon_d}`. Actual status is
`sys.onigiri.<id>.state` (`active`, `off`, `unavailable`; `ready`/`loading` are
internal startup states). Version and pending version use
`sys.onigiri.<id>.{version,pending_version}`.

HMA reports Active only from a fresh upstream status.json after loading.
TEESimulator reports Active from its own successful interceptor initialization
message and returns to Unavailable when the daemon exits. BRENE requires a
responding susfs interface and successful requested path operations. None of
these statuses proves an integrity verdict from a third-party app.

## Validation

```sh
python3 scripts/tests/test_essential.py
bash -n onigiri/mods/essential/system/bin/onigiri-essential.sh
```

`scripts/build_essential.py` builds Java adapters with the checksum-pinned R8
compiler installed by `build_dependencies`, then packages the untouched
upstream dex/binaries/APK. Tests cover payload identity, invalid inputs,
archive boundaries, migration, desired/current state, and interrupted update
recovery. Also apply and assemble the services.jar and Settings patches against
the matching ROM and compile the policy additions.

Host tests cannot establish that the Android verifier, native injector,
SELinux transitions, HMA Binder service or Settings activities work on the
phone. A full cold boot, module migration, disabled/enabled cycles, offline
update failure, staged update, rollback, and English/Vietnamese UI checks on
the Flip5 remain release requirements.
