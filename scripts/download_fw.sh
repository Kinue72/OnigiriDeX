#!/usr/bin/env bash

set -euo pipefail

SRC_DIR="${SRC_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
OUT_DIR="${OUT_DIR:-$SRC_DIR/out}"
TOOLS_DIR="${TOOLS_DIR:-$OUT_DIR/tools}"
ROLE="${1:-target}"

if [ "$#" -gt 1 ] || [[ "$ROLE" != "target" && "$ROLE" != "donor" ]]; then
    echo "Usage: download_fw [target|donor]" >&2
    exit 1
fi

SPEC="$(python3 -c '
import json, sys
spec = json.load(open(sys.argv[1]))[sys.argv[2]]
print(spec["model"], spec["csc"], spec["version"])
' "$SRC_DIR/onigiri/configs/firmware.json" "$ROLE")"
read -r MODEL CSC VERSION <<< "$SPEC"
DESTINATION="$OUT_DIR/odin/${MODEL}_${CSC}"

if [ -e "$DESTINATION" ]; then
    if [ -f "$DESTINATION/.downloaded" ] && [[ "$(cat "$DESTINATION/.downloaded")" == "$VERSION" ]]; then
        echo "Previously imported $MODEL $VERSION"
        exit 0
    fi
    echo "Existing firmware at $DESTINATION differs from the pinned version; preserve or move it before importing." >&2
    exit 1
fi

IMEI_VARIABLE="ONIGIRI_${ROLE^^}_IMEI"
SERIAL_VARIABLE="ONIGIRI_${ROLE^^}_SERIAL"
IDENTIFIER="${!IMEI_VARIABLE:-}"
IDENTIFIER_OPTION="-i"

if [ -n "$IDENTIFIER" ]; then
    if ! [[ "$IDENTIFIER" =~ ^[0-9]{15}$ ]]; then
        echo "$IMEI_VARIABLE must contain a valid 15-digit IMEI." >&2
        exit 1
    fi
else
    IDENTIFIER="${!SERIAL_VARIABLE:-}"
    IDENTIFIER_OPTION="-s"
    if [ -z "$IDENTIFIER" ]; then
        echo "FUS requires $IMEI_VARIABLE or $SERIAL_VARIABLE from the matching $MODEL device." >&2
        echo "Alternatively download $VERSION for $MODEL / $CSC and run:" >&2
        echo "python3 scripts/import_fw.py $ROLE /path/to/firmware.zip" >&2
        exit 1
    fi
    if ! [[ "$IDENTIFIER" =~ ^R[A-Z0-9]{10}$ ]]; then
        echo "$SERIAL_VARIABLE must contain a valid Samsung serial number." >&2
        exit 1
    fi
fi

SAMLOADER="$TOOLS_DIR/venv/bin/samloader"
if [ ! -x "$SAMLOADER" ]; then
    echo "Install external/samloader into $TOOLS_DIR/venv before downloading." >&2
    exit 1
fi

DOWNLOAD_DIR="$OUT_DIR/downloads/${MODEL}_${CSC}"
mkdir -p "$DOWNLOAD_DIR"
echo "Downloading pinned $MODEL / $CSC / $VERSION"

if ! (
    cd -- "$DOWNLOAD_DIR"
    "$SAMLOADER" -m "$MODEL" -r "$CSC" "$IDENTIFIER_OPTION" "$IDENTIFIER" \
        download -v "$VERSION/${VERSION%%/*}" -O "$DOWNLOAD_DIR" > samloader-output.log 2>&1
); then
    echo "FUS download failed. Download the pinned archive manually and use scripts/import_fw.py." >&2
    exit 1
fi

shopt -s nullglob
ARCHIVES=("$DOWNLOAD_DIR/"*.zip)
if [ "${#ARCHIVES[@]}" -ne 1 ]; then
    echo "Expected one decrypted firmware ZIP in $DOWNLOAD_DIR." >&2
    exit 1
fi

python3 "$SRC_DIR/scripts/import_fw.py" "$ROLE" "${ARCHIVES[0]}"
