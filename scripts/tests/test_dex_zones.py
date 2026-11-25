#!/usr/bin/env python3
"""Builds and runs OnigiriZonesTest: the DeX zone layout maths, against host stand-ins for Android."""
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / 'scripts/tests'

with tempfile.TemporaryDirectory(prefix='dex-zones-javac-') as classes:
    subprocess.run(['javac', '--release', '8', '-Xlint:-options', '-d', classes,
                    str(ROOT / 'target/b5q/patches/dex/java/zones/src/com/android/wm/shell/freeform/OnigiriZones.java'),
                    str(TESTS / 'OnigiriZonesTest.java'), *map(str, sorted((TESTS / 'zones').glob('**/*.java')))],
                   check=True)
    subprocess.run(['java', '-ea', '-cp', classes, 'com.android.wm.shell.freeform.OnigiriZonesTest'], check=True)
print('dex zones OK')
