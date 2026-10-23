PRELOAD_APKS="$(python3 - "$SRC_DIR/prebuilts/apps" <<'PY'
from pathlib import Path
import hashlib
import json
import re
import sys

root = Path(sys.argv[1]).resolve()
manifest = json.loads((root / 'manifest.json').read_text())
if len(manifest['assets']) != 3 or {Path(a['path']).parent.name for a in manifest['assets']} != {'GoodLock', 'me.weishu.kernelsu-Onigiri', 'SBrowser'}:
    raise ValueError('Unexpected preload app manifest')
payloads = set()
apks = []
for asset in manifest['assets']:
    if not re.fullmatch(r'system/system/preload/(GoodLock|me\.weishu\.kernelsu-Onigiri|SBrowser)/[A-Za-z0-9._-]+\.apk', asset['path']):
        raise ValueError('Invalid preload asset path: ' + asset['path'])
    path = root / asset['path']
    chunks = sorted(path.parent.glob(path.name + '.*'))
    if path.exists() or path.is_symlink():
        if chunks:
            raise ValueError('Preload APK has both whole and chunked payloads: ' + asset['path'])
        parts = [path]
    else:
        if not chunks or [chunk.name for chunk in chunks] != [f'{path.name}.{i:02d}' for i in range(len(chunks))]:
            raise ValueError('Missing or invalid preload APK chunks: ' + asset['path'])
        parts = chunks
    checksum = hashlib.sha256()
    size = 0
    for part in parts:
        if part.is_symlink() or not part.is_file() or not part.resolve().is_relative_to(root):
            raise ValueError('Invalid preload payload: ' + str(part))
        with part.open('rb') as source:
            while data := source.read(1024 * 1024):
                size += len(data)
                checksum.update(data)
    if size != asset['bytes'] or checksum.hexdigest() != asset['sha256']:
        raise ValueError('Preload APK size or checksum mismatch: ' + asset['path'])
    payloads.update(parts)
    apks.append(str(path.relative_to(root / 'system')))
if {p for p in (root / 'system').rglob('*') if p.is_file() or p.is_symlink()} != payloads:
    raise ValueError('Unexpected preload payload files')
print('\n'.join(apks))
PY
)" || return 1

while IFS= read -r FILE; do
    ADD_TO_WORK_DIR "$SRC_DIR/prebuilts/apps" "system" "$FILE" 0 0 644 "u:object_r:system_file:s0" || return 1
done <<< "$PRELOAD_APKS"

sed -i "/system\/preload/d" "$WORK_DIR/configs/fs_config-system" \
    && sed -i "/system\/preload/d" "$WORK_DIR/configs/file_context-system"
while read -r i; do
    FILE="${i#"$WORK_DIR/system/"}"
    [ -d "$i" ] && echo "$FILE 0 0 755 capabilities=0x0" >> "$WORK_DIR/configs/fs_config-system"
    [ -f "$i" ] && echo "$FILE 0 0 644 capabilities=0x0" >> "$WORK_DIR/configs/fs_config-system"
    FILE="$(echo -n "$FILE" | sed 's/\./\\./g')"
    echo "/$FILE u:object_r:system_file:s0" >> "$WORK_DIR/configs/file_context-system"
done <<< "$(find "$WORK_DIR/system/system/preload")"

rm -f "$WORK_DIR/system/system/etc/vpl_apks_count_list.txt"
while read -r i; do
    FILE="${i#"$WORK_DIR/system"}"
    echo "$FILE" >> "$WORK_DIR/system/system/etc/vpl_apks_count_list.txt"
done <<< "$(find "$WORK_DIR/system/system/preload" -name "*.apk" | sort)"
