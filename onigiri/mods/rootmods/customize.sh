# Puts the pinned module zips in /system/etc/onigiri-rootmods for onigiri-rootmods.sh, with the
# KernelSU daemon (ksud) from the preloaded KernelSU app, so they install before that app is ever
# opened, and the default HMA-OSS config (hma-oss.json, exported from its app). Root-only, so
# apps can't list them. NN- sets the install order, the rest is the module id.
python3 - "$SRC_DIR/prebuilts/rootmods" \
    "$SRC_DIR/prebuilts/apps/system/system/preload/me.weishu.kernelsu-Onigiri/base.apk" "$WORK_DIR" \
    "$MODPATH/hma-oss.json" <<'PY' || return 1
from pathlib import Path
import hashlib
import json
import re
import shutil
import sys
import zipfile

root, apk, work, hma_config = (Path(arg).resolve() for arg in sys.argv[1:])
dest = work / 'system/system/etc/onigiri-rootmods'
dest.mkdir(parents=True)
# HMA-OSS ignores a config whose version isn't its own: re-export it after bumping HMA-OSS.
if json.loads(hma_config.read_text())['configVersion'] != 93:
    raise ValueError('hma-oss.json is not for HMA-OSS oss-173 (config version 93)')
shutil.copyfile(hma_config, dest / 'hma-oss.json')
payloads = set()
for asset in json.loads((root / 'manifest.json').read_text())['assets']:
    name = re.fullmatch(r'system/etc/onigiri-rootmods/\d\d-([A-Za-z][A-Za-z0-9._-]+)\.zip', asset['path'])
    if not name:
        raise ValueError('Invalid root module path: ' + asset['path'])
    path = root / asset['path']
    if path.is_symlink() or not path.is_file():
        raise ValueError('Missing root module: ' + asset['path'])
    data = path.read_bytes()
    if len(data) != asset['bytes'] or hashlib.sha256(data).hexdigest() != asset['sha256']:
        raise ValueError('Root module size or checksum mismatch: ' + asset['path'])
    with zipfile.ZipFile(path) as module:
        props = dict(line.split('=', 1) for line in module.read('module.prop').decode().splitlines() if '=' in line)
    # The phone keys its "installed once" marker on the id in the file name.
    if props.get('id', '').strip() != name[1]:
        raise ValueError('Root module id does not match its file name: ' + asset['path'])
    shutil.copyfile(path, dest / path.name)
    payloads.add(path)
if {p for p in (root / 'system').rglob('*') if not p.is_dir()} != payloads:
    raise ValueError('Unexpected root module files')
with zipfile.ZipFile(apk) as manager:
    (dest / 'ksud').write_bytes(manager.read('lib/arm64-v8a/libksud.so'))

with open(work / 'configs/fs_config-system', 'a') as fs_config, \
        open(work / 'configs/file_context-system', 'a') as file_context:
    for path in [dest, *sorted(dest.iterdir())]:
        entry = path.relative_to(work / 'system').as_posix()
        mode = 700 if path.is_dir() or path.name == 'ksud' else 600
        fs_config.write(f'{entry} 0 0 {mode} capabilities=0x0\n')
        file_context.write('/' + entry.replace('.', '\\.') + ' u:object_r:system_file:s0\n')
PY
