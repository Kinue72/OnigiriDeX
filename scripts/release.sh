#!/usr/bin/env bash
# Usage: release <tag> <AP .tar.md5 built from this commit>
#
# Publishes a GitHub release: the Odin AP (split into parts under GitHub's 2 GiB asset limit),
# an OTA from the previous release when there is one, and version.txt, which Settings > Onigiri
# Software > Software update reads. Released APs are kept in out/releases as the base of the
# next OTA (downloaded from the previous release when missing).
# .github/workflows/release.yml runs this for every pushed tag.

set -eo pipefail

[ "$#" -eq 2 ] || { echo "Usage: release <tag> <AP .tar.md5>" >&2; exit 1; }
TAG="$1"
AP="$(realpath "$2")"
REPO="${ONIGIRI_REPO:-Kinue72/OnigiriDeX}"
RELEASES="$OUT_DIR/releases"

# ro.onigiri.version is what phones report and OTAs are named after, so it must be a real commit.
if [ -n "$(git -C "$SRC_DIR" status --porcelain --untracked-files=no --ignore-submodules=dirty)" ]; then
    echo "Commit or stash local changes first: a release is named after its commit." >&2
    exit 1
fi
if gh release view "$TAG" --repo "$REPO" &> /dev/null; then
    echo "Release $TAG already exists." >&2
    exit 1
fi

if [[ "$(basename "$AP")" != *"_${ROM_VERSION}_"* ]]; then
    echo "$AP was not built from this commit ($ROM_VERSION)." >&2
    exit 1
fi

mkdir -p "$RELEASES" "$OUT_DIR/tmp"
WORK="$(mktemp -d "$OUT_DIR/tmp/release.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
ASSETS=("$AP.sha256" "$WORK/version.txt")
NOTES=""
echo "$ROM_VERSION $TAG" > "$WORK/version.txt"

# Only "no release yet" or a hand-made release without version.txt may skip the OTA; any other
# lookup error stops here instead of publishing without one.
if ! PREVIOUS_TAG="$(gh api "repos/$REPO/releases/latest" --jq .tag_name 2> "$WORK/error")"; then
    grep -q "HTTP 404" "$WORK/error" || { cat "$WORK/error" >&2; exit 1; }
    PREVIOUS_TAG=""
fi
PREVIOUS=""
if [ -n "$PREVIOUS_TAG" ]; then
    gh release view "$PREVIOUS_TAG" --repo "$REPO" --json assets --jq '.assets[].name' > "$WORK/assets"
    if grep -qx version.txt "$WORK/assets"; then
        PREVIOUS="$(gh release download "$PREVIOUS_TAG" --repo "$REPO" --pattern version.txt --output - | cut -d " " -f 1)"
        [[ "$PREVIOUS" =~ ^[0-9a-f]{7,40}$ ]] || { echo "Unexpected version.txt in $PREVIOUS_TAG: $PREVIOUS" >&2; exit 1; }
    fi
fi
if [ -n "$PREVIOUS" ] && [ "$PREVIOUS" != "$ROM_VERSION" ]; then
    if [ ! -f "$RELEASES/$PREVIOUS.tar.md5" ]; then
        echo "- Downloading the $PREVIOUS_TAG AP"
        gh release download "$PREVIOUS_TAG" --repo "$REPO" --pattern "Onigiri_AP_*.tar.md5.*" --dir "$WORK/previous"
        cat "$WORK"/previous/*.tar.md5.[0-9]* > "$RELEASES/$PREVIOUS.tar.md5"
        rm -rf "$WORK/previous"
    fi
    OTA="$WORK/Onigiri_OTA_$PREVIOUS.zip"
    "$SRC_DIR/scripts/make_ota.sh" "$RELEASES/$PREVIOUS.tar.md5" "$AP" "$OTA"
    # Phones download it to /cache (779 MB, which recovery also needs for patching), so a bigger
    # update, like a new Samsung base, ships as the AP only.
    if [ "$(stat -c %s "$OTA")" -le $((400 * 1024 * 1024)) ]; then
        ASSETS+=("$OTA")
        NOTES="**Updating from $PREVIOUS_TAG:** Settings > Onigiri Software > Software update. It downloads only what changed and installs it in recovery; your data stays."$'\n\n'
    else
        echo "- The update from $PREVIOUS_TAG is $(du -h "$OTA" | cut -f 1), too big for /cache: AP only"
        NOTES="**Updating from $PREVIOUS_TAG** needs the full AP this time: the changes are too big for an over-the-air update. Flash it with Odin as below; your data stays."$'\n\n'
    fi
fi

NAME="$(basename "$AP")"
split -b 1900M -d -a 1 "$AP" "$WORK/$NAME."
PARTS=("$WORK/$NAME".[0-9])
ASSETS+=("${PARTS[@]}")
JOIN="$(printf '%s+' "${PARTS[@]##*/}")"

gh release create "$TAG" --repo "$REPO" --target "$(git -C "$SRC_DIR" rev-parse HEAD)" \
    --title "Onigiri $TAG" --generate-notes --notes "$NOTES$(cat << EOF
**New install, or any other build:** download every \`$NAME.N\` part, join them and flash the result as AP with Odin (see [flashing](https://github.com/$REPO/blob/main/docs/flashing.md)):
- macOS / Linux: \`cat $NAME.? > $NAME\`
- Windows: \`copy /b ${JOIN%+} $NAME\`

Check it against \`$NAME.sha256\`.
EOF
)" "${ASSETS[@]}"

ln -f "$AP" "$RELEASES/$ROM_VERSION.tar.md5"
echo "- Released $TAG ($ROM_VERSION)"
