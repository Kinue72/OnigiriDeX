#!/usr/bin/env bash
# Usage: release <tag> <AP .tar.md5 built from this commit>...
#
# Publishes a GitHub release with one Odin AP per Flip5 model (named Onigiri_AP_<model>_..., split
# into parts under GitHub's 2 GiB asset limit), per model OTAs, update.json and version.txt, which
# Settings > Onigiri Software > Software update reads (version.txt for builds before update.json).
# A model's OTAs are one from the previous release, when that release has the model's AP, and
# that one chained after each of the previous release's OTAs (scripts/ota_chain.py), so builds
# several releases back update in one go too. The SM-F731B OTAs keep the name older builds look
# for (Onigiri_OTA_<from>.zip); other models get Onigiri_OTA_<model>_<from>.zip. Released APs are
# kept in out/releases as the base of the next OTA (downloaded from the previous release when
# missing).
# .github/workflows/release.yml runs this for every pushed tag.

set -eo pipefail

[ "$#" -ge 2 ] || { echo "Usage: release <tag> <AP .tar.md5>..." >&2; exit 1; }
TAG="$1"
shift
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

APS=()
MODELS=()
for AP in "$@"; do
    AP="$(realpath "$AP")"
    if [[ "$(basename "$AP")" != *"_${ROM_VERSION}_"* ]]; then
        echo "$AP was not built from this commit ($ROM_VERSION)." >&2
        exit 1
    fi
    MODEL="$(basename "$AP" | sed -n 's/^Onigiri_AP_\(SM-[A-Z0-9]*\)_.*/\1/p')"
    if [ -z "$MODEL" ] || [[ " ${MODELS[*]} " == *" $MODEL "* ]]; then
        echo "$(basename "$AP"): expected one Onigiri_AP_<model>_... per model." >&2
        exit 1
    fi
    APS+=("$AP")
    MODELS+=("$MODEL")
done

mkdir -p "$RELEASES" "$OUT_DIR/tmp"
WORK="$(mktemp -d "$OUT_DIR/tmp/release.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
ASSETS=("$WORK/version.txt" "$WORK/update.json")
NOTES=""
OTAS=()
echo "$ROM_VERSION $TAG" > "$WORK/version.txt"
# Phones download OTAs to /cache (779 MB, which recovery also needs for patching), so a bigger
# update, like a new Samsung base, ships as the AP only.
OTA_LIMIT=$((400 * 1024 * 1024))

# OTA_NAME <model> <from version>
OTA_NAME()
{
    if [ "$1" = SM-F731B ]; then echo "Onigiri_OTA_$2.zip"; else echo "Onigiri_OTA_${1}_$2.zip"; fi
}

# Only "no release yet" or a hand-made release without version.txt may skip the OTA; any other
# lookup error stops here instead of publishing without one.
if ! PREVIOUS_TAG="$(gh api "repos/$REPO/releases/latest" --jq .tag_name 2> "$WORK/error")"; then
    grep -q "HTTP 404" "$WORK/error" || { cat "$WORK/error" >&2; exit 1; }
    PREVIOUS_TAG=""
fi
PREVIOUS=""
PREVIOUS_JSON=""
: > "$WORK/assets"
if [ -n "$PREVIOUS_TAG" ]; then
    gh release view "$PREVIOUS_TAG" --repo "$REPO" --json assets --jq '.assets[].name' > "$WORK/assets"
    if grep -qx version.txt "$WORK/assets"; then
        PREVIOUS="$(gh release download "$PREVIOUS_TAG" --repo "$REPO" --pattern version.txt --output - | cut -d " " -f 1)"
        [[ "$PREVIOUS" =~ ^[0-9a-f]{7,40}$ ]] || { echo "Unexpected version.txt in $PREVIOUS_TAG: $PREVIOUS" >&2; exit 1; }
    fi
    if grep -qx update.json "$WORK/assets"; then
        PREVIOUS_JSON="$WORK/previous.json"
        gh release download "$PREVIOUS_TAG" --repo "$REPO" --pattern update.json --output "$PREVIOUS_JSON"
    fi
fi
# What's new, shown on the phone: the pull requests merged since the previous release.
gh api "repos/$REPO/releases/generate-notes" -f tag_name="$TAG" \
    -f target_commitish="$(git -C "$SRC_DIR" rev-parse HEAD)" ${PREVIOUS_TAG:+-f previous_tag_name="$PREVIOUS_TAG"} \
    --jq .body > "$WORK/notes.md"

for i in "${!APS[@]}"; do
    AP="${APS[$i]}"
    MODEL="${MODELS[$i]}"
    NAME="$(basename "$AP")"
    ASSETS+=("$AP.sha256")
    # out/releases/<commit>.tar.md5 is the SM-F731B AP (from before other models were built).
    KEPT="$RELEASES/$PREVIOUS.tar.md5"
    [ "$MODEL" = SM-F731B ] || KEPT="$RELEASES/${MODEL}_$PREVIOUS.tar.md5"
    OTA="$WORK/$(OTA_NAME "$MODEL" "$PREVIOUS")"

    if [ -n "$PREVIOUS" ] && [ "$PREVIOUS" != "$ROM_VERSION" ] && \
            { [ -f "$KEPT" ] || grep -q "^Onigiri_AP_${MODEL}_.*\.tar\.md5\.[0-9]$" "$WORK/assets"; }; then
        if [ ! -f "$KEPT" ]; then
            echo "- Downloading the $PREVIOUS_TAG $MODEL AP"
            gh release download "$PREVIOUS_TAG" --repo "$REPO" --pattern "Onigiri_AP_${MODEL}_*.tar.md5.*" --dir "$WORK/previous"
            cat "$WORK"/previous/*.tar.md5.[0-9]* > "$KEPT"
            rm -rf "$WORK/previous"
        fi
        "$SRC_DIR/scripts/make_ota.sh" "$KEPT" "$AP" "$OTA"
        if [ "$(stat -c %s "$OTA")" -le "$OTA_LIMIT" ]; then
            ASSETS+=("$OTA")
            OTAS+=("$MODEL:$PREVIOUS:$OTA")
            # Each OTA of the previous release, with this one after it, takes its build here in one go.
            CHAINED=0
            PREFIX="$(OTA_NAME "$MODEL" "")"
            mkdir -p "$WORK/chain"
            for FROM in $(sed -n "s/^${PREFIX%.zip}\([0-9a-f]\{7,40\}\)\.zip$/\1/p" "$WORK/assets"); do
                [ "$FROM" != "$ROM_VERSION" ] || continue
                CHAIN="$(OTA_NAME "$MODEL" "$FROM")"
                gh release download "$PREVIOUS_TAG" --repo "$REPO" --pattern "$CHAIN" --dir "$WORK/chain"
                python3 "$SRC_DIR/scripts/ota_chain.py" "$WORK/chain/unsigned.zip" "$WORK/chain/$CHAIN" "$OTA"
                signapk -w "$SRC_DIR/security/onigiri_ota.x509.pem" "$SRC_DIR/security/onigiri_ota.pk8" \
                    "$WORK/chain/unsigned.zip" "$WORK/$CHAIN"
                rm "$WORK/chain/unsigned.zip" "$WORK/chain/$CHAIN"
                if [ "$(stat -c %s "$WORK/$CHAIN")" -le "$OTA_LIMIT" ]; then
                    ASSETS+=("$WORK/$CHAIN")
                    OTAS+=("$MODEL:$FROM:$WORK/$CHAIN")
                    CHAINED=$((CHAINED + 1))
                else
                    rm "$WORK/$CHAIN"
                fi
            done
            echo "- $MODEL: OTA from $PREVIOUS_TAG, chained for $CHAINED older builds"
            FROM_TAGS="$PREVIOUS_TAG"
            [ "$CHAINED" = 0 ] || FROM_TAGS+=" or earlier"
            NOTES+="**$MODEL, updating from $FROM_TAGS:** Settings > Onigiri Software > Software update. It downloads only what changed and installs it in recovery; your data stays."$'\n\n'
        else
            echo "- The $MODEL update from $PREVIOUS_TAG is $(du -h "$OTA" | cut -f 1), too big for /cache: AP only"
            NOTES+="**$MODEL, updating from $PREVIOUS_TAG** needs the full AP this time: the changes are too big for an over-the-air update. Flash it with Odin as below; your data stays."$'\n\n'
            rm "$OTA"
        fi
    fi

    split -b 1900M -d -a 1 "$AP" "$WORK/$NAME."
    PARTS=("$WORK/$NAME".[0-9])
    ASSETS+=("${PARTS[@]}")
    JOIN="$(printf '%s+' "${PARTS[@]##*/}")"
    NOTES+="$(cat << EOF
**$MODEL, new install or any other build:** download every \`$NAME.N\` part, join them and flash the result as AP with Odin (see [flashing](https://github.com/$REPO/blob/main/docs/flashing.md)):
- macOS / Linux: \`cat $NAME.? > $NAME\`
- Windows: \`copy /b ${JOIN%+} $NAME\`

Check it against \`$NAME.sha256\`.
EOF
)"$'\n\n'
done

python3 "$SRC_DIR/scripts/ota_manifest.py" "$WORK/update.json" "$TAG" "$ROM_VERSION" "$WORK/notes.md" \
    "$PREVIOUS_JSON" "${OTAS[@]}"

gh release create "$TAG" --repo "$REPO" --target "$(git -C "$SRC_DIR" rev-parse HEAD)" \
    --title "Onigiri $TAG" --generate-notes --notes "$NOTES" "${ASSETS[@]}"

for i in "${!APS[@]}"; do
    KEPT="$RELEASES/$ROM_VERSION.tar.md5"
    [ "${MODELS[$i]}" = SM-F731B ] || KEPT="$RELEASES/${MODELS[$i]}_$ROM_VERSION.tar.md5"
    ln -f "${APS[$i]}" "$KEPT"
done
echo "- Released $TAG ($ROM_VERSION: ${MODELS[*]})"
