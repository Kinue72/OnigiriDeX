# Releases and OTA updates

Phones on a released build update from **Settings > Onigiri Software > Software update**. It
reads `version.txt` from the latest GitHub release and, when that release carries
`Onigiri_OTA_<installed ro.onigiri.version>.zip`, downloads it to `/cache` and reboots to
recovery, which installs it. A typical update is 10-20 MB instead of the 8 GB AP. Phones on any
other build need the full AP.

The AP ships Samsung's stock recovery with one change: `otacerts.zip` holds only the Onigiri OTA
certificate, so recovery installs packages signed with `security/onigiri_ota.pk8` and nothing
else. Before it writes anything, the package checks every block it reads against the build it
was made from, so a package for another build fails without touching the phone.

## Making a release

Push a tag. `.github/workflows/release.yml` then runs `scripts/release.sh <tag>` on the
self-hosted runner, which:

1. builds the kernel (only when `external/kernel` or `external/patches/kernel` changed) and the AP;
2. makes `Onigiri_OTA_<previous version>.zip` from the previous release's AP with
   `scripts/make_ota.sh` (Samsung's `ota_from_target_files`, from the Flip5 firmware);
3. uploads the AP split into parts under GitHub's 2 GiB asset limit, its `.sha256`, the OTA
   and `version.txt`.

Without the runner, run the same thing from a clean git checkout on the build machine:
`onigiri release <tag>` (needs `gh` logged in with push access).

Only an update from the previous release is built. Someone two releases behind flashes the AP.

## Keys

`security/onigiri_ota.pk8` is created on the first build, next to `onigiri_platform.pk8`. Back
both up. With the OTA key lost, every phone needs a full Odin flash of a recovery with the new
certificate before it can update again.

## Runner setup (once, repository admin)

The build needs the firmware ZIPs, the keys and about 250 GB of disk, so it runs on the build
machine. On it:

1. Settings > Actions > Runners > New self-hosted runner (Linux). Follow the commands, adding
   `--labels onigiri` to `./config.sh`, then `sudo ./svc.sh install && sudo ./svc.sh start`.
2. Seed the runner's checkout with what git doesn't carry (adjust the paths):

   ```sh
   W=~/actions-runner/_work/OnigiriDeX/OnigiriDeX
   mkdir -p "$W/security"
   cp ~/dev/OnigiriDeX/security/onigiri_*.{pk8,x509.pem} "$W/security/"
   ln -s ~/dev/OnigiriDeX/firmware "$W/firmware"
   ```

   Then run the README's build steps once in `$W` (import and extract the firmware,
   `onigiri build_dependencies`). The workflow keeps `out/` between runs.
3. Settings > Actions > General > Fork pull request workflows: **Require approval for all
   external contributors**. The repository is public, and a pull request can add a workflow
   that would otherwise run on this machine.
