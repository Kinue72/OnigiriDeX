#!/usr/bin/env bash
# Usage: build.sh <out dir>
#
# Builds Software update (src/, package moe.foss.onigiri.update) into smali for SecSettings patch
# 0029: javac against SDK 35 and stubs/ (compile-only copies of the Settings classes it uses,
# checked against the decoded SecSettings), d8, baksmali. Copy <out dir>/moe/foss/onigiri/update
# into a decoded SecSettings' smali_classes5 (its own dex: smali_classes4 is at the 64K
# method reference limit) and diff it into the patch. Needs the Android SDK
# platform 35 (ANDROID_HOME, or ~/Android/Sdk) and the built tools (onigiri build_dependencies).
set -eo pipefail
[ "$#" -eq 1 ] || { sed -n 2p "$0" >&2; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
SDK="${ANDROID_HOME:-$HOME/Android/Sdk}/platforms/android-35/android.jar"
TOOLS="${TOOLS_DIR:-$HERE/../../../../../out/tools}/bin"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/stubs" "$WORK/classes" "$WORK/dex"
javac -Xlint:-options -source 8 -target 8 -bootclasspath "$SDK" -d "$WORK/stubs" $(find "$HERE/stubs" -name '*.java')
javac -Xlint:-options -source 8 -target 8 -bootclasspath "$SDK" -cp "$WORK/stubs" -d "$WORK/classes" \
    $(find "$HERE/src" -name '*.java')
java -cp "$TOOLS/r8.jar" com.android.tools.r8.D8 --release --min-api 35 --lib "$SDK" --classpath "$WORK/stubs" \
    --output "$WORK/dex" $(find "$WORK/classes" -name '*.class')
java -cp "$TOOLS/apktool.jar" com.android.tools.smali.baksmali.Main d --use-locals --sequential-labels \
    -o "$OUT" "$WORK/dex/classes.dex"
