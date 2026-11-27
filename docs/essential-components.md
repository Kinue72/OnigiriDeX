# Essential component integration

This replaces first-boot module installation with three built-in adapters. The
Settings design is option B: a main switch and a page per component, with
current status, component-specific controls, and a PIF-style version/update row.

## Payloads and scope

| Component | Bundled release | Built-in integration |
| --- | --- | --- |
| HMA-OSS | oss-173 | Original signed manager and backend with the hook-installation race and preset-scan GC fixes below; a guarded services.jar entry loads it without Vector or Zygisk. Config schema remains 93. |
| TEESimulator | v3.2, code 67 | Original arm64 injector, native library and dex run through an init service. The keybox is the one supplied at `onigiri/mods/essential/tee-keybox.xml`, never the expired copy in the upstream archive. |
| BRENE | v0.0.72 | Original susfs CLI and ROM-name list, with `onigiri` appended, so custom-ROM path hiding covers this build's own files. Only custom-ROM path, addon.d and module-mount hiding are ported. |

The build verifies the original archives against `prebuilts/rootmods/manifest.json`
and `bundled.properties`. It never executes their installers. The HMA manager keeps
its upstream signing certificate. PIF's existing certificate handling remains
in place. TEESimulator's expired bundled keybox is replaced by the keybox supplied in
`onigiri/mods/essential/tee-keybox.xml`, which is deliberately not in this
repository (see [releasing.md](releasing.md); without it the build warns and keeps the
archive's expired key). A supplied key must pass the same chain, root and private-key
checks a device applies before it may enter an image; only its dates are advisory, since
it has to last until a boot that has network, and an offline install keeps using
whatever the image carried. The build warns when the leaf is inside
`TEE_KEYBOX_REFRESH_WINDOW` or already expired rather than failing.

## Keybox refresh

A shared attestation key dies within days: Google revokes it once it circulates. The
mirror's own index lists every key old enough to matter as revoked, so an image can
only carry a bootstrap key. `moe.foss.onigiri.KeyboxUpdate` fetches the newest one
once TEESimulator is active, off the startup path the trial guard measures; the daemon
watches the store directory and reloads `keybox.xml` when the file changes. The first fetch is bounded
to 20 seconds. When it fails, the TEE service asks init to run `onigiri-keybox` once
more, which waits 90 seconds for data and then gets 90 of its own. Both services carry
the `inet` group, and the delayed run rechecks the toggle before it starts.

It fetches base64 from `https://evoker.qzz.io/key`, the only host it will talk to, and a
redirect anywhere else fails closed.

A keybox is accepted only when every key it holds is a real Google attestation chain;
one good key does not vouch for the rest of the file. Keys are read one at a time, as the
daemon reads them, so a `<Keybox>` that holds an EC and an RSA key side by side is two
chains and not one. Every certificate must verify against the next and be valid now, the
leaf must have more than two days left, the chain must end at a pinned Google attestation
root (`Key Attestation CA1` or the hardware attestation root), and the private key must
sign for its own certificate: the public values are not compared, because a key that
cannot sign is useless to the daemon whatever it claims. That rejects the AOSP software
key upstream ships, so the refresh cannot quietly install one. The document is read as
XML would be: comments and character data are dropped first, a DTD is refused, and a file
that stops before its closing tag is not a keybox. A rejected or unreachable key leaves
the file exactly as it was: the shipped key on a fresh install, whatever was there on any
other device.

`/data/adb/tricky_store/keybox.xml` is replaced only when this module installed it: its
checksum must match what the seeder recorded in
`/data/system/onigiri-essential/keybox/shipped` when it copied the keybox in, the record
of an install in flight in `installing`, the ROM's own `tee/keybox.xml`, or the archive
keybox that releases before the marker installed. `installing` is removed once the new
file is committed, so it can only ever vouch for the install it was written for. A
keybox supplied by hand or by another module reports `custom` and is left alone, even
when it has expired, and a symlink is someone else's file likewise. States appear in
`sys.onigiri.keybox.state` (`updated`, `current`, `custom`, `unavailable`, `busy`) with
the leaf expiry in `sys.onigiri.keybox.expires`, which is cleared whenever the file is
not one this module installed and on every failed attempt, so an offline boot shows no
expiry rather than a stale one. `persist.sys.onigiri.keybox_update false` switches the
refresh off, and `onigiri-essential.sh keybox` runs it by hand.

Publication is ordered: the file is staged under the store's own label, a first install
is a hard link so it can only create, and a replacement is a rename after the checksum is
rechecked. The new file and its directory are synced before the marker that claims it
exists, so a power cut cannot leave the old key beside the new digest. The daemon reloads
on a close for write or a rename, never on a create, so the first install also closes the
file it just created. One window stays open by construction: a writer that publishes
between that checksum recheck and the rename loses its file. POSIX has no
compare-and-swap rename, and the other writers are upstream modules that do not take this
lock, so the guarantee is "only a file whose bytes this module recorded", not "never
replaced whatever happens".

Bundled payloads live under `/system/framework/onigiri-essential`, which is
permitted by keystore's linker namespace. Updates use the root-owned
`/data/system/onigiri-essential` tree. Both retain the dedicated SELinux label.
HMA's hook engine also requires `system_server` to create anonymous executable
memory for its trampolines; the policy grants that specific `execmem` permission.
SELinux remains enforcing, and upstream crash status (work mode 4) stays unavailable.

HMA's pinned AndroidVMTools revision publishes a hook before preparing its
original-call trampoline. A concurrent Binder call can recursively re-enter the
hook and crash system_server. Adapter 2 reverses those two operations during
extraction. HMA's boot-time preset scan also calls `System.gc()` and clears its
manifest cache whenever `freeMemory()` drops below 2 MB, and its own allocation
churn keeps setting that off. On a busy boot, the repeated blocking GCs and
evictions can keep the scan running past the loader's deadline. That is the
likely cause of a stalled Flip5 boot whose guard then turned HMA off. Adapter 3
sets that threshold to 0, which cut a from-scratch scan on the Flip5 from 12.7 s
with 15 forced GCs to 4.3 s with none, and the presets came out identical. `HmaHookPatch` checks the complete input and
output dex SHA-256, changes only the two calls, the result registers and that
constant, and repairs the dex header checksums. The archive and signed manager stay unchanged. Both bundled builds
and downloaded updates use this same extractor. Unknown backend dex versions
are rejected until reviewed; a changed backend or an upstream fix needs a new
ROM adapter. Manager-only updates using the supported backend remain possible.

The legacy first-boot installer and the archives only it used (NeoZygisk, Tricky
Addon and Hybrid Mount) are no longer in the repository: these adapters don't
need them and no image installs them. The three archives the adapters extract
remain under `prebuilts/rootmods`, with their upstream URLs and checksums in
`manifest.json`.

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
Only the TEE process adds KernelSU's root-owned bin directory to its PATH so
upstream can invoke `resetprop` when started by init.

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

HMA, TEE and BRENE have separate init updater services and locks. Downloads use HTTPS with
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

- HMA adapter 3 requires the reviewed oss-173 backend dex, its hook-order fix and GC patch,
  no-argument `ZygoteEntry.main()`, manager signing identity, config schema 93,
  and current status.json semantics.
- TEE adapter 1 requires the v3.2 entry point, current-directory injector
  layout, and `/data/adb/tricky_store` configuration. TEESimulator v4 changes
  these and is explicitly reported as requiring a ROM update.
- BRENE adapter 1 imports the ROM-name list (with `onigiri` appended) and susfs
  binary; it does not start following the rest of BRENE's evolving scripts or
  settings.

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
responding susfs interface, mount hiding for non-root processes, and successful
requested path operations. None of these statuses proves an integrity verdict
from a third-party app.

susfs ships that mount hiding off for Zygisk, which these adapters do not use.
Without it, apps see the mounts of KernelSU modules that stay enabled, such as
bindhosts' `/system/etc/hosts`. VNeID rejects that with code CA-E003.

## Validation

```sh
python3 scripts/tests/test_essential.py
bash -n onigiri/mods/essential/system/bin/onigiri-essential.sh
```

`scripts/build_essential.py` builds Java adapters with the checksum-pinned R8
compiler installed by `build_dependencies`, then applies the verified HMA hook
fix, the supplied keybox for TEESimulator and the `onigiri` entry for BRENE's path
list. Every other upstream payload is packaged unchanged. Tests cover payload identity, invalid inputs,
archive boundaries, migration, desired/current state, and interrupted update
recovery. Also apply and assemble the services.jar and Settings patches against
the matching ROM and compile the policy additions.

Host tests cannot establish that the Android verifier, native injector,
SELinux transitions, HMA Binder service or Settings activities work on the
phone. A full cold boot, module migration, disabled/enabled cycles, offline
update failure, staged update, rollback, and English/Vietnamese UI checks on
the Flip5 remain release requirements.
