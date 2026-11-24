# Releases and OTA updates

Phones on a released build update from **Settings > Onigiri Software > Software update**. Its
page reads `update.json` from the latest GitHub release (twice a day in the background too, with
one notification per release), shows what's new, and when that release carries the update from
its build, asks, downloads it to `/cache`, checks its sha256 and reboots to recovery, which
installs it. Settings (`moe.foss.onigiri.update` in the SecSettings patch 0029) does the checks
and the page; `onigiri-update.sh` downloads and installs as root. **Install from storage** takes a
package file instead: Settings copies it into its own files and hands the path over; recovery
installs it only if it fits the installed build (a wrong one aborts before writing and the phone
starts again unchanged, in about 80 s). Builds from before 0029 read
`version.txt` instead and still update the same way. The update
is `Onigiri_OTA_<installed ro.onigiri.version>.zip` on the SM-F731B (the name older builds look
for) and `Onigiri_OTA_<model>_<installed ro.onigiri.version>.zip` on other models; the model is
`ro.product.vendor.model`, the installed build's. An update that only changes the ROM was 3 MB in testing, one with a
new kernel 40 MB, instead of the 8 GB AP.

A release also carries, per model, the previous release's OTAs with its own chained after them
(`scripts/ota_chain.py`), under the names of the builds they start from, so a phone several
releases behind updates with one download and one restart too. Each hop in a chained package
still checks the blocks it reads before it writes; after each hop the package records it in
misc's stage field, so an install cut short starts again after the hops already done. A chain
ends at a release without an OTA (an AP-only release) or when it would pass 400 MB. Phones on any
other build need the full AP.

`update.json` lists, per model, each build a release updates and its package (size, sha256), and
what's new in the last 20 releases: the titles of the pull requests GitHub's generated notes list,
`feat` ones as new and `fix`/`perf` ones as fixed (`scripts/ota_manifest.py`). Write pull request
titles for the people using the phone.

The AP ships Samsung's stock recovery with one change: `otacerts.zip` holds only the Onigiri OTA
certificate, so recovery installs packages signed with `security/onigiri_ota.pk8` and nothing
else. A phone only downloads the package named for its own `ro.onigiri.version`, and before it
writes anything the package checks every block it reads against the build it was made from.
Blocks it doesn't read go unchecked, so that check catches another build only where the two
differ in those blocks.

Each Flip5 model in `onigiri/configs/firmware.json` gets its own AP: vendor, odm, dtbo, init_boot,
recovery and vbmeta come from that model's stock firmware, because they differ (the SM-F731N has
an MST chip and a grip sensor in its dtbo, its own RIL, Wi-Fi board data and camera blobs; the
SM-F7310 has a smaller super partition and a camera HAL built at other offsets). The system and the
kernel are the same for all of them; the kernel builds every model's modules (except the SM-F7310's
second grip sensor, sx9360_sub, whose driver Samsung didn't publish) and is repacked from the
SM-F731B's stock boot images, whose base device trees match the other models'.

## Making a release

Push a tag, for example `git tag 2026.10.21 && git push origin 2026.10.21`.
`.github/workflows/release.yml` then runs, on GitHub's runners:

1. the checks from `check.yml` (shell, Python, patch and config checks, which also run on every
   pull request and push to main), and next to them a setup job: it checks that the signing key
   secret and firmware draft are in place, builds the tools and the kernel if their sources
   changed, and starts a draft release, which phones can't see;
2. one job per model, side by side. Each builds that model's AP, then runs
   `scripts/release.sh --model`, which
   - starts uploading the AP, split into parts under GitHub's 2 GiB asset limit, with its `.sha256`;
   - makes the model's OTA from the previous release's AP with `scripts/make_ota.sh` (Samsung's
     `ota_from_target_files`, from that model's firmware), when the previous release has one: a
     model's first release is AP only;
   - chains it after each of the previous release's OTAs of that model, signs those and uploads
     the OTAs;
3. a last job that runs `scripts/release.sh --publish`: it writes `version.txt` and `update.json`
   for all models, checks that the draft holds exactly the files the model jobs made and makes
   it public. If a job fails, the draft is deleted and nothing is published.

Only tags publish. The kernel (30 to 50 minutes on GitHub's runners), the build tools and the few
files the ROM build reads from the kernel tree are kept in the private `build-cache` draft release
under a hash of their sources and rebuilt only when those change. With all three cached, a
release takes about half an hour, since the models build side by side. Only the OTA from the previous release is diffed;
older builds get chained packages, which take seconds to make.

**Dry run.** To try a change to the build or the workflow without releasing, run the workflow by
hand: Actions > Release > Run workflow, on any branch (or `gh workflow run release.yml --ref
<branch>`). It does everything above, uploads included, into a draft named `dry-run-<run id>`,
prints the notes and `update.json` it would publish and deletes the draft.

Without GitHub, the same works on the build machine from a clean git checkout:
`onigiri build_odin` after `source buildenv.sh <model>` for each model, then
`onigiri release <tag> out/Onigiri_AP_*.tar.md5` with every model's AP (needs `gh` logged in with
push access). It runs the same three steps in a row.

## Testing a branch on a phone

Build locally: a dry run on GitHub tests the pipeline but deletes what it built. Use the
existing firmware and build-tool caches and keep the installed build's AP available for rollback:

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
mkdir -p out/tmp/fw && tar -C out -cf - fw | zstd -T0 -10 | split -b 1900M -d -a 2 - out/tmp/fw/onigiri-fw.tar.zst.
gh release delete firmware --repo Kinue72/OnigiriDeX --yes
gh release create firmware --repo Kinue72/OnigiriDeX --draft --title "Firmware for CI (never publish)" \
    --notes "Pre-extracted pinned Samsung firmware for .github/workflows/release.yml." out/tmp/fw/onigiri-fw.tar.zst.*
```

A model's job extracts every split archive in the draft (`<name>.tar.zst.NN`) except the other
models' own, `onigiri-fw-<model>.tar.zst.NN`, so a new model's firmware goes in under that name
instead of replacing the rest:

```sh
mkdir -p out/tmp/fw && tar -C out -cf - fw/SM-F731N_KOO | zstd -T0 -10 | split -b 1900M -d -a 2 - out/tmp/fw/onigiri-fw-SM-F731N.tar.zst.
gh release upload firmware --repo Kinue72/OnigiriDeX out/tmp/fw/onigiri-fw-SM-F731N.tar.zst.*
```
