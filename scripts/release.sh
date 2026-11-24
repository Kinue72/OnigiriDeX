#!/usr/bin/env bash
# Usage: release <tag> <AP .tar.md5 built from this commit>...
#        release --begin <tag> | --previous <model> | --model <tag> <AP .tar.md5> | --publish <tag>
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
#
# It works in three steps, so that .github/workflows/release.yml can give each model its own
# machine: --begin starts a draft release, which phones can't see; --model makes one model's
# OTAs and uploads them and its AP to the draft; --publish adds update.json and version.txt,
# checks that everything arrived and makes the release public. With ONIGIRI_DRY_RUN=true it
# deletes the draft instead. Without an option, all three run here. --previous is optional: it
# fetches and unpacks the previous release's AP of a model ahead of --model, which the workflow
# does while the new AP is still building.

set -eo pipefail

case "${1:-}" in
    --begin|--publish|--previous) STEP="${1#--}"; [ "$#" -eq 2 ] || STEP="" ;;
    --model) STEP=model; [ "$#" -eq 3 ] || STEP="" ;;
    -*) STEP="" ;;
    *) STEP=all; [ "$#" -ge 2 ] || STEP="" ;;
esac
if [ -z "$STEP" ]; then
    sed -n '2,3s/^# //p' "$0" >&2
    exit 1
fi
[ "$STEP" = all ] || shift
# The tag, or for --previous the model.
TAG="$1"
shift

REPO="${ONIGIRI_REPO:-Kinue72/OnigiriDeX}"
RELEASES="$OUT_DIR/releases"
# What each model's step leaves for the publish step: its packages for update.json
# (<model>.updates.json), its part of the release notes (<model>.notes.md) and the files it
# uploaded (<model>.assets).
STATE="$OUT_DIR/release/$TAG"
# Phones download OTAs to /cache (779 MB, which recovery also needs for patching), so a bigger
# update, like a new Samsung base, ships as the AP only.
OTA_LIMIT=$((400 * 1024 * 1024))

# RETRY <command>...: GitHub's asset servers drop a request now and then, and one shouldn't cost
# a build that took the better part of an hour.
RETRY()
{
    local WAIT
    for WAIT in 10 30 60; do
        "$@" && return 0
        echo "- Failed, trying again in $WAIT s: $*" >&2
        sleep "$WAIT"
    done
    "$@"
}

# ro.onigiri.version is what phones report and OTAs are named after, so it must be a real commit.
CLEAN_TREE()
{
    if [ -n "$(git -C "$SRC_DIR" status --porcelain --untracked-files=no --ignore-submodules=dirty)" ]; then
        echo "Commit or stash local changes first: a release is named after its commit." >&2
        exit 1
    fi
}

# OTA_NAME <model> <from version>
OTA_NAME()
{
    if [ "$1" = SM-F731B ]; then echo "Onigiri_OTA_$2.zip"; else echo "Onigiri_OTA_${1}_$2.zip"; fi
}

# The latest published release: PREVIOUS_TAG, its build (PREVIOUS), its asset names ($WORK/assets)
# and its update.json (PREVIOUS_JSON). Only "no release yet" or a hand-made release without
# version.txt may leave them empty; any other lookup error stops here instead of publishing
# without an OTA.
PREVIOUS_RELEASE()
{
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
            # To a file: on stdout, what a failed attempt printed would run into the next one's.
            RETRY gh release download "$PREVIOUS_TAG" --repo "$REPO" --pattern version.txt --clobber --output "$WORK/previous.txt"
            PREVIOUS="$(cut -d " " -f 1 "$WORK/previous.txt")"
            [[ "$PREVIOUS" =~ ^[0-9a-f]{7,40}$ ]] || { echo "Unexpected version.txt in $PREVIOUS_TAG: $PREVIOUS" >&2; exit 1; }
        fi
        if grep -qx update.json "$WORK/assets"; then
            PREVIOUS_JSON="$WORK/previous.json"
            RETRY gh release download "$PREVIOUS_TAG" --repo "$REPO" --pattern update.json --clobber --output "$PREVIOUS_JSON"
        fi
    fi
}

# PREVIOUS_AP <model>: the previous release's AP of a model as KEPT, downloaded when it isn't
# kept in out/releases. Fails when that release has none for the model (or is this very build).
PREVIOUS_AP()
{
    # out/releases/<commit>.tar.md5 is the SM-F731B AP (from before other models were built).
    KEPT="$RELEASES/$PREVIOUS.tar.md5"
    [ "$1" = SM-F731B ] || KEPT="$RELEASES/${1}_$PREVIOUS.tar.md5"
    [ -n "$PREVIOUS" ] && [ "$PREVIOUS" != "$ROM_VERSION" ] || return 1
    [ ! -f "$KEPT" ] || return 0
    grep -q "^Onigiri_AP_${1}_.*\.tar\.md5\.[0-9]$" "$WORK/assets" || return 1
    echo "- Downloading the $PREVIOUS_TAG $1 AP"
    # Callers test this function, which turns "set -e" off inside it: stop by hand.
    RETRY gh release download "$PREVIOUS_TAG" --repo "$REPO" --pattern "Onigiri_AP_${1}_*.tar.md5.*" --clobber --dir "$WORK/previous" || exit 1
    cat "$WORK"/previous/*.tar.md5.[0-9]* > "$KEPT.part" || exit 1
    mv "$KEPT.part" "$KEPT" || exit 1
    rm -rf "$WORK/previous"
}

# FETCH_PREVIOUS <model>
FETCH_PREVIOUS()
{
    mkdir -p "$RELEASES" "$OUT_DIR/tmp"
    WORK="$(mktemp -d "$OUT_DIR/tmp/release.XXXXXX")"
    trap 'rm -rf "$WORK"' EXIT
    PREVIOUS_RELEASE
    if PREVIOUS_AP "$1"; then
        echo "- Unpacking the $PREVIOUS_TAG $1 AP"
        "$SRC_DIR/scripts/make_ota.sh" --unpack "$KEPT"
    else
        echo "- No earlier $1 AP to update from"
    fi
}

BEGIN()
{
    CLEAN_TREE
    local DRAFT
    if DRAFT="$(gh release view "$TAG" --repo "$REPO" --json isDraft --jq .isDraft 2> /dev/null)"; then
        if [ "$DRAFT" != true ]; then
            echo "Release $TAG already exists." >&2
            exit 1
        fi
        # A draft is what a run that failed left behind.
        gh release delete "$TAG" --repo "$REPO" --yes
    fi
    rm -rf "$STATE"
    gh release create "$TAG" --repo "$REPO" --draft --target "$(git -C "$SRC_DIR" rev-parse HEAD)" \
        --title "Onigiri $TAG" --notes ""
}

# MODEL <AP>
MODEL()
{
    CLEAN_TREE
    local AP NAME MODEL KEPT OTA CHAIN CHAINED FROM FROM_TAGS PREFIX JOIN
    local ASSETS=() OTAS=() PARTS NOTES=""
    UPLOAD=""
    AP="$(realpath "$1")"
    NAME="$(basename "$AP")"
    if [[ "$NAME" != *"_${ROM_VERSION}_"* ]]; then
        echo "$AP was not built from this commit ($ROM_VERSION)." >&2
        exit 1
    fi
    MODEL="$(sed -n 's/^Onigiri_AP_\(SM-[A-Z0-9]*\)_.*/\1/p' <<< "$NAME")"
    if [ -z "$MODEL" ] || [ -e "$STATE/$MODEL.assets" ]; then
        echo "$NAME: expected one Onigiri_AP_<model>_... per model." >&2
        exit 1
    fi

    mkdir -p "$RELEASES" "$OUT_DIR/tmp" "$STATE"
    WORK="$(mktemp -d "$OUT_DIR/tmp/release.XXXXXX")"
    trap '[ -z "$UPLOAD" ] || kill "$UPLOAD" 2> /dev/null; rm -rf "$WORK"' EXIT
    PREVIOUS_RELEASE

    # The AP is most of the upload and nothing below changes it: send it while the OTAs are made.
    split -b 1900M -d -a 1 "$AP" "$WORK/$NAME."
    PARTS=("$WORK/$NAME".[0-9])
    RETRY gh release upload "$TAG" --repo "$REPO" --clobber "$AP.sha256" "${PARTS[@]}" > "$WORK/upload.log" 2>&1 &
    UPLOAD="$!"

    OTA="$WORK/$(OTA_NAME "$MODEL" "$PREVIOUS")"

    if PREVIOUS_AP "$MODEL"; then
        "$SRC_DIR/scripts/make_ota.sh" "$KEPT" "$AP" "$OTA"
        if [ "$(stat -c %s "$OTA")" -le "$OTA_LIMIT" ]; then
            ASSETS+=("$OTA")
            OTAS+=("$PREVIOUS:$OTA")
            # Each OTA of the previous release, with this one after it, takes its build here in one go.
            CHAINED=0
            PREFIX="$(OTA_NAME "$MODEL" "")"
            mkdir -p "$WORK/chain"
            for FROM in $(sed -n "s/^${PREFIX%.zip}\([0-9a-f]\{7,40\}\)\.zip$/\1/p" "$WORK/assets"); do
                [ "$FROM" != "$ROM_VERSION" ] || continue
                CHAIN="$(OTA_NAME "$MODEL" "$FROM")"
                RETRY gh release download "$PREVIOUS_TAG" --repo "$REPO" --pattern "$CHAIN" --clobber --dir "$WORK/chain"
                python3 "$SRC_DIR/scripts/ota_chain.py" "$WORK/chain/unsigned.zip" "$WORK/chain/$CHAIN" "$OTA"
                signapk -w "$SRC_DIR/security/onigiri_ota.x509.pem" "$SRC_DIR/security/onigiri_ota.pk8" \
                    "$WORK/chain/unsigned.zip" "$WORK/$CHAIN"
                rm "$WORK/chain/unsigned.zip" "$WORK/chain/$CHAIN"
                if [ "$(stat -c %s "$WORK/$CHAIN")" -le "$OTA_LIMIT" ]; then
                    ASSETS+=("$WORK/$CHAIN")
                    OTAS+=("$FROM:$WORK/$CHAIN")
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

    JOIN="$(printf '%s+' "${PARTS[@]##*/}")"
    NOTES+="$(cat << EOF
**$MODEL, new install or any other build:** download every \`$NAME.N\` part, join them and flash the result as AP with Odin (see [flashing](https://github.com/$REPO/blob/main/docs/flashing.md)):
- macOS / Linux: \`cat $NAME.? > $NAME\`
- Windows: \`copy /b ${JOIN%+} $NAME\`

Check it against \`$NAME.sha256\`.
EOF
)"$'\n\n'

    if ! wait "$UPLOAD"; then
        cat "$WORK/upload.log" >&2
        exit 1
    fi
    UPLOAD=""
    [ "${#ASSETS[@]}" = 0 ] || RETRY gh release upload "$TAG" --repo "$REPO" --clobber "${ASSETS[@]}"

    python3 "$SRC_DIR/scripts/ota_manifest.py" updates "$STATE/$MODEL.updates.json" "$MODEL" "${OTAS[@]}"
    printf '%s' "$NOTES" > "$STATE/$MODEL.notes.md"
    printf '%s\n' "$NAME.sha256" "${PARTS[@]##*/}" "${ASSETS[@]##*/}" > "$STATE/$MODEL.assets"

    KEPT="$RELEASES/$ROM_VERSION.tar.md5"
    [ "$MODEL" = SM-F731B ] || KEPT="$RELEASES/${MODEL}_$ROM_VERSION.tar.md5"
    ln -f "$AP" "$KEPT"
    echo "- $MODEL: uploaded to the $TAG draft"
}

PUBLISH()
{
    local MODEL MODELS
    if ! ls "$STATE"/*.assets > /dev/null 2>&1; then
        echo "No model has been released for $TAG yet (release --model)." >&2
        exit 1
    fi
    mkdir -p "$OUT_DIR/tmp"
    WORK="$(mktemp -d "$OUT_DIR/tmp/release.XXXXXX")"
    trap 'rm -rf "$WORK"' EXIT
    PREVIOUS_RELEASE

    # What's new, shown on the phone and under the install notes: the pull requests merged since
    # the previous release.
    gh api "repos/$REPO/releases/generate-notes" -f tag_name="$TAG" \
        -f target_commitish="$(git -C "$SRC_DIR" rev-parse HEAD)" ${PREVIOUS_TAG:+-f previous_tag_name="$PREVIOUS_TAG"} \
        --jq .body > "$WORK/notes.md"
    python3 "$SRC_DIR/scripts/ota_manifest.py" manifest "$WORK/update.json" "$TAG" "$ROM_VERSION" "$WORK/notes.md" \
        "$PREVIOUS_JSON" "$STATE"/*.updates.json
    echo "$ROM_VERSION $TAG" > "$WORK/version.txt"
    RETRY gh release upload "$TAG" --repo "$REPO" --clobber "$WORK/version.txt" "$WORK/update.json"

    # Phones follow update.json as soon as the release is public: every file must be there first.
    gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[].name' | sort > "$WORK/uploaded"
    { cat "$STATE"/*.assets; echo version.txt; echo update.json; } | sort > "$WORK/expected"
    if ! diff "$WORK/expected" "$WORK/uploaded" >&2; then
        echo "The $TAG draft doesn't hold exactly the files that were made (< missing, > unexpected)." >&2
        exit 1
    fi

    # Each model's notes in firmware.json order (a glob would put the SM-F7310 before the B). The
    # list is read first: a failure inside "for ... in $(...)" wouldn't stop the script.
    MODELS="$(python3 -c 'import json, sys; print(*json.load(open(sys.argv[1]))["targets"])' \
        "$SRC_DIR/onigiri/configs/firmware.json")"
    for MODEL in $MODELS; do
        [ ! -f "$STATE/$MODEL.notes.md" ] || cat "$STATE/$MODEL.notes.md"
    done > "$WORK/body.md"
    cat "$WORK/notes.md" >> "$WORK/body.md"
    if [ "${ONIGIRI_DRY_RUN:-}" = true ]; then
        echo "- Dry run: $TAG would be published with $(wc -l < "$WORK/uploaded") files and these notes:"
        cat "$WORK/body.md" "$WORK/update.json"
        gh release delete "$TAG" --repo "$REPO" --yes
    else
        gh release edit "$TAG" --repo "$REPO" --draft=false --latest --notes-file "$WORK/body.md"
        echo "- Released $TAG ($ROM_VERSION: $(cd "$STATE" && ls -- *.assets | sed 's/\.assets$//' | xargs))"
    fi
    rm -rf "$STATE"
}

case "$STEP" in
    begin) BEGIN ;;
    previous) FETCH_PREVIOUS "$TAG" ;;
    model) MODEL "$1" ;;
    publish) PUBLISH ;;
    all)
        BEGIN
        for AP in "$@"; do
            ( MODEL "$AP" )
        done
        PUBLISH
        ;;
esac
