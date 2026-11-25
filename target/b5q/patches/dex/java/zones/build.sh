#!/usr/bin/env bash
# Usage: build.sh <out dir>
#
# Builds Onigiri zones (src/) into smali for SystemUI patch 0002 and services.jar patch 0003:
# javac against SDK 35 and stubs/ (compile-only copies of the stock classes it uses, checked
# against the decoded SystemUI and services.jar; a few shadow SDK classes for hidden members),
# d8, baksmali. OnigiriZones and OnigiriZoneOverlay are built twice: as written for SystemUI,
# and as com.android.server.wm for system_server. Copy <out dir>/SystemUI/com into a decoded
# SystemUI's smali_classes3 and <out dir>/services/com into a decoded services.jar's
# smali_classes2, and diff them into the patches. Needs the Android SDK platform 35
# (ANDROID_HOME, or ~/Android/Sdk) and the built tools (onigiri build_dependencies).
set -eo pipefail
[ "$#" -eq 1 ] || { sed -n 2p "$0" >&2; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
SDK="${ANDROID_HOME:-$HOME/Android/Sdk}/platforms/android-35/android.jar"
TOOLS="${TOOLS_DIR:-$HERE/../../../../../../out/tools}/bin"
SHELL_SRC="$HERE/src/com/android/wm/shell/freeform"
SERVER_SRC="$HERE/src/com/android/server/wm"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/stubs" "$WORK/shared"
javac -Xlint:-options -source 8 -target 8 -bootclasspath "$SDK" -d "$WORK/stubs" $(find "$HERE/stubs" -name '*.java')
for CLASS in OnigiriZones OnigiriZoneOverlay; do
    sed 's/^package com\.android\.wm\.shell\.freeform;$/package com.android.server.wm;/' \
        "$SHELL_SRC/$CLASS.java" > "$WORK/shared/$CLASS.java"
done

# <name> <source>...
build()
{
    mkdir -p "$WORK/$1/classes" "$WORK/$1/dex"
    javac -Xlint:-options -source 8 -target 8 -bootclasspath "$WORK/stubs:$SDK" -d "$WORK/$1/classes" "${@:2}"
    java -cp "$TOOLS/r8.jar" com.android.tools.r8.D8 --release --min-api 35 --lib "$SDK" --classpath "$WORK/stubs" \
        --output "$WORK/$1/dex" $(find "$WORK/$1/classes" -name '*.class')
    java -cp "$TOOLS/apktool.jar" com.android.tools.smali.baksmali.Main d --use-locals --sequential-labels \
        -o "$OUT/$1" "$WORK/$1/dex/classes.dex"
}
build SystemUI "$SHELL_SRC"/*.java
build services "$SERVER_SRC"/*.java "$WORK/shared"/*.java
