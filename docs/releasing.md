# Releases and OTA updates

Phones on a released build update from **Settings > Onigiri Software > Software update**. It
reads `version.txt` from the latest GitHub release and, when that release carries
`Onigiri_OTA_<installed ro.onigiri.version>.zip`, downloads it to `/cache` and reboots to
recovery, which installs it. An update that only changes the ROM was 3 MB in testing, one with a
new kernel 40 MB, instead of the 8 GB AP. Phones on any other build need the full AP.

The AP ships Samsung's stock recovery with one change: `otacerts.zip` holds only the Onigiri OTA
certificate, so recovery installs packages signed with `security/onigiri_ota.pk8` and nothing
else. A phone only downloads the package named for its own `ro.onigiri.version`, and before it
writes anything the package checks every block it reads against the build it was made from.
Blocks it doesn't read go unchecked, so that check catches another build only where the two
differ in those blocks.

## Making a release

Push a tag, for example `git tag 2026.10.21 && git push origin 2026.10.21`.
`.github/workflows/release.yml` first runs the checks from `check.yml` (shell, Python, patch and
config checks, which also run on every pull request and push to main) and that the signing key
secret and firmware draft are in place. Only then does it build that commit on GitHub's runners
and run `scripts/release.sh`, which:

1. makes `Onigiri_OTA_<previous version>.zip` from the previous release's AP with
   `scripts/make_ota.sh` (Samsung's `ota_from_target_files`, from the Flip5 firmware);
2. uploads the AP split into parts under GitHub's 2 GiB asset limit, its `.sha256`, the OTA and
   `version.txt`.

Only tags build. The kernel (~70 minutes on GitHub's runners) and the build tools are kept in
the private `build-cache` draft release under a hash of their sources and rebuilt only when those
change, so a release that only changes the ROM takes about an hour. Only an update from the
previous release is made; someone two releases behind flashes the AP.

Without GitHub, the same works on the build machine from a clean git checkout:
`onigiri build_odin`, then `onigiri release <tag> out/Onigiri_AP_*.tar.md5` (needs `gh` logged in
with push access).

## Testing a branch on a phone

Run the Release workflow manually with the branch and the release already installed on the
phone, for example `gh workflow run release.yml --ref <branch> -f base_tag=2026.10.22.1`.
Manual runs use the existing signing keys and upload a seven-day `phone-test-<commit>` Actions
artifact containing the update, reverse update, runtime files, source commit and checksums.
They do not publish a release or change the version offered to other phones. Check the device's
installed version against `base-version.txt` and verify `SHA256SUMS` before testing. Keep the
rollback package and the original AP available until the test build is accepted.

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
