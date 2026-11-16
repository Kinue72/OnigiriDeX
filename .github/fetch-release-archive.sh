#!/usr/bin/env bash
# Usage: fetch-release-archive.sh <release> <archive> <directory> [tar option or member]...
#
# Extracts a .tar.zst kept on a GitHub release, whole (<archive>) or split (<archive>.NN), into a
# directory, straight from the download. GitHub's asset servers reset a connection now and then
# and a stream can't resume, so a failed attempt starts over.
set -eo pipefail

RELEASE="$1"
ARCHIVE="$2"
DIRECTORY="$3"
shift 3

PARTS="$(gh release view "$RELEASE" --json assets --jq '.assets[].name' |
    awk -v name="$ARCHIVE" '$0 == name || index($0, name ".") == 1' | sort)"
[ -n "$PARTS" ] || { echo "No $ARCHIVE on the $RELEASE release." >&2; exit 1; }
mkdir -p "$DIRECTORY"

for WAIT in 15 60 0; do
    if for PART in $PARTS; do
        gh release download "$RELEASE" --pattern "$PART" --output - || exit 1
    done | zstd -dc | tar -x -C "$DIRECTORY" "$@"; then
        exit 0
    fi
    [ "$WAIT" != 0 ] || break
    echo "::warning::Fetching $ARCHIVE failed, trying again in $WAIT s"
    sleep "$WAIT"
    # What the failed attempt left may include folders it can't write into again.
    chmod -R u+w "$DIRECTORY"
done
echo "Fetching $ARCHIVE failed three times." >&2
exit 1
