python3 - "$WORK_DIR/system/system/apex/com.android.btservices.apex" \
    "$WORK_DIR/system/system/lib64/libbluetooth_jni.so" <<'PY'
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

apex, output = map(Path, sys.argv[1:])
with tempfile.TemporaryDirectory(prefix='onigiri-bt-', dir='/tmp') as directory:
    payload = Path(directory) / 'payload.img'
    library = Path(directory) / 'libbluetooth_jni.so'
    with zipfile.ZipFile(apex) as archive:
        assert archive.namelist().count('apex_payload.img') == 1
        with archive.open('apex_payload.img') as source, payload.open('wb') as destination:
            shutil.copyfileobj(source, destination)
    with payload.open('rb') as source:
        source.seek(1080)
        assert source.read(2) == b'\x53\xef', 'Bluetooth APEX payload must be ext4'
    subprocess.run(['debugfs', '-R', f'dump /lib64/libbluetooth_jni.so {library}', str(payload)], check=True, capture_output=True)
    data = library.read_bytes()
    assert data[:6] == b'\x7fELF\x02\x01' and data[18:20] == b'\xb7\x00', 'Bluetooth library must be AArch64 ELF'
    before = bytes.fromhex('480500352800805228')
    after = bytes.fromhex('530100142800805228')
    assert data.count(before) == 1, 'Unexpected Bluetooth patch site count'
    library.write_bytes(data.replace(before, after))
    temporary = output.with_suffix('.so.tmp')
    try:
        shutil.copyfile(library, temporary)
        os.chmod(temporary, 0o644)
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
PY

SET_METADATA "system" "system/lib64/libbluetooth_jni.so" 0 0 644 "u:object_r:system_lib_file:s0"
