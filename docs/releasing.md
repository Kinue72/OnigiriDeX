# Releases and OTA updates

Phones on a released build update from **Settings > Onigiri Software > Software update**. It
reads `version.txt` from the latest GitHub release and, when that release carries the update
from its build, downloads it to `/cache` and reboots to recovery, which installs it. The update
is `Onigiri_OTA_<installed ro.onigiri.version>.zip` on the SM-F731B (the name older builds look
for) and `Onigiri_OTA_<model>_<installed ro.onigiri.version>.zip` on other models; the model is
`ro.product.vendor.model`, the installed build's. An update that only changes the ROM was 3 MB in testing, one with a
new kernel 40 MB, instead of the 8 GB AP. Phones on any other build need the full AP.

The AP ships Samsung's stock recovery with one change: `otacerts.zip` holds only the Onigiri OTA
certificate, so recovery installs packages signed with `security/onigiri_ota.pk8` and nothing
else. A phone only downloads the package named for its own `ro.onigiri.version`, and before it
writes anything the package checks every block it reads against the build it was made from.
Blocks it doesn't read go unchecked, so that check catches another build only where the two
differ in those blocks.

Each Flip5 model in `onigiri/configs/firmware.json` gets its own AP: vendor, odm, dtbo, init_boot,
recovery and vbmeta come from that model's stock firmware, because they differ (the SM-F731N has
an MST chip and a grip sensor in its dtbo, its own RIL, Wi-Fi board data and camera blobs). The
system and the kernel are the same for all of them; the kernel builds every model's modules and
is repacked from the SM-F731B's stock boot images, whose device trees match the N's.

## Making a release

Push a tag, for example `git tag 2026.10.21 && git push origin 2026.10.21`.
`.github/workflows/release.yml` first runs the checks from `check.yml` (shell, Python, patch and
config checks, which also run on every pull request and push to main) and that the signing key
secret and firmware draft are in place. Only then does it build that commit on GitHub's runners
for every model, one after the other, and runs `scripts/release.sh`, which for each model:

1. makes its OTA from the previous release's AP of that model with `scripts/make_ota.sh`
   (Samsung's `ota_from_target_files`, from that model's firmware), when the previous release
   has one: a model's first release is AP only;
2. uploads the AP split into parts under GitHub's 2 GiB asset limit, its `.sha256` and the OTA,
   plus one `version.txt` for all.

Only tags build. The kernel (~70 minutes on GitHub's runners) and the build tools are kept in
the private `build-cache` draft release under a hash of their sources and rebuilt only when those
change, so a release that only changes the ROM takes about an hour. Only an update from the
previous release is made; someone two releases behind flashes the AP.

Without GitHub, the same works on the build machine from a clean git checkout:
`onigiri build_odin` after `source buildenv.sh <model>` for each model, then
`onigiri release <tag> out/Onigiri_AP_*.tar.md5` with every model's AP (needs `gh` logged in with
push access).

## Testing a branch on a phone

Build locally; CI ROM builds run only for release tags. Use the existing firmware and
build-tool caches and keep the installed build's AP available for rollback:

```sh
source buildenv.sh SM-F731B   # the connected phone's model
onigiri build_odin
```

Flash only the resulting AP for the connected phone's model. Preserve the phone's data and
module configuration. Reuse the original signing keys in `security` when updating an
existing installation. Verify the AP checksum and keep the original AP until the test
build is accepted. Do not publish a release for a phone test.

## Setup (once)

**Signing keys.** The workflow reads the keys from the `ONIGIRI_SIGNING_KEYS` secret. Set it
on the machine that holds them:

```sh
tar -C security -cz onigiri_platform.pk8 onigiri_platform.x509.pem onigiri_ota.pk8 onigiri_ota.x509.pem |
    base64 -w0 | gh secret set ONIGIRI_SIGNING_KEYS --repo Kinue72/OnigiriDeX
```

Back the keys up as well. Without the platform key, updates can't be installed over an existing
install; without the OTA key, every phone needs a recovery with the new certificate flashed with
Odin before it can update again. Without the secret a release stops before building.

**Firmware.** Samsung's servers no longer serve the pinned firmware, so the workflow downloads
`out/fw` (what `onigiri extract_fw` produces) from a draft release named `firmware`. Drafts are
only visible to people with push access; never publish it (or `build-cache`). After changing the firmware pins in
`onigiri/configs/firmware.json`, extract the new firmware and replace it:

```sh
mkdir -p /tmp/fw && tar -C out -cf - fw | zstd -T0 -10 | split -b 1900M -d -a 2 - /tmp/fw/onigiri-fw.tar.zst.
gh release delete firmware --repo Kinue72/OnigiriDeX --yes
gh release create firmware --repo Kinue72/OnigiriDeX --draft --title "Firmware for CI (never publish)" \
    --notes "Pre-extracted pinned Samsung firmware for .github/workflows/release.yml." /tmp/fw/onigiri-fw.tar.zst.*
```

The workflow extracts every split archive in the draft (`<name>.tar.zst.NN`), so a new model's
firmware can go in as its own archive instead of replacing the rest:

```sh
mkdir -p /tmp/fw && tar -C out -cf - fw/SM-F731N_KOO | zstd -T0 -10 | split -b 1900M -d -a 2 - /tmp/fw/onigiri-fw-SM-F731N.tar.zst.
gh release upload firmware --repo Kinue72/OnigiriDeX /tmp/fw/onigiri-fw-SM-F731N.tar.zst.*
```
