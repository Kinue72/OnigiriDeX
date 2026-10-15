#!/usr/bin/env python3

import argparse
import hashlib
import json
import resource
import shutil
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

sys.path.insert(0, str(Path(__file__).resolve().parent))
from import_fw import verify_odin_package
from verify_fw import read_values

ROOT = Path(__file__).resolve().parents[1]
MAX_IMAGE = 16 * 1024 ** 3
RESERVE = 1024 ** 3
FILES = (
    'system/build.prop',
    'system/etc/floating_feature.xml',
    'system/etc/permissions/privapp-permissions-com.samsung.android.sead.xml',
    'system/framework/framework-res.apk',
    'system/framework/services.jar',
    'system/priv-app/BlueLightFilter/BlueLightFilter.apk',
    'system/priv-app/EnvironmentAdaptiveDisplay/EnvironmentAdaptiveDisplay.apk',
    'system_ext/priv-app/SystemUI/SystemUI.apk',
)


def select_ap(archive):
    candidates = []
    for entry in archive.infolist():
        path = PurePosixPath(entry.filename)
        if path.is_absolute() or '..' in path.parts or '\\' in entry.filename or stat.S_ISLNK(entry.external_attr >> 16):
            raise ValueError(f'Unsafe archive entry: {entry.filename}')
        if entry.is_dir() or not path.name.startswith('AP_'):
            continue
        if not path.name.startswith('AP_S921BXXS9BYH1_') or not path.name.endswith('.tar.md5'):
            raise ValueError(f'Wrong S24 firmware version: {path.name}')
        candidates.append(entry)
    if len(candidates) != 1:
        raise ValueError('Expected exactly one S921BXXS9BYH1 AP package')
    return candidates[0]


def validate_software(folder):
    values = read_values(folder / 'system/build.prop')
    for key, expected in {
        'ro.product.system.model': 'SM-S921B',
        'ro.build.version.incremental': 'S921BXXS9BYH1',
        'ro.build.version.sdk': '35',
        'ro.build.version.oneui': '70000',
    }.items():
        if values.get(key) != expected:
            raise ValueError(f'S24 software mismatch: {key}={values.get(key)!r}, expected {expected}')


def require_space(folder, required):
    if shutil.disk_usage(folder).free < required + RESERVE:
        raise OSError(f'S24 extraction needs at least {(required + RESERVE) / 1024 ** 3:.1f} GiB free at this stage')


def verify_imported_software(folder):
    validate_software(folder)
    manifest = json.loads((folder / 'manifest.json').read_text())
    if set(manifest['files']) != set(FILES):
        raise ValueError('Incomplete S24 software manifest')
    for name in FILES:
        path = folder / name
        expected = manifest['files'][name]
        with path.open('rb') as stream:
            checksum = hashlib.file_digest(stream, 'sha256').hexdigest()
        if path.stat().st_size != expected['bytes'] or checksum != expected['sha256']:
            raise ValueError(f'S24 software checksum mismatch: {name}')


def image_limit():
    resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_IMAGE, MAX_IMAGE))


def extract_software(archive_path, output, tools):
    if output.exists() or output.is_symlink():
        raise FileExistsError(f'S24 software already exists: {output}')
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive_path) as archive:
        entry = select_ap(archive)
        require_space(output.parent, entry.file_size + MAX_IMAGE)
        with tempfile.TemporaryDirectory(prefix='.s24-software-', dir=output.parent) as temporary:
            stage = Path(temporary)
            ap = stage / PurePosixPath(entry.filename).name
            print('Verifying the S24 AP package and its ZIP entry CRC', flush=True)
            with archive.open(entry) as source, ap.open('xb') as destination:
                shutil.copyfileobj(source, destination, 1024 * 1024)
            verify_odin_package(ap)
            with ap.open('rb') as stream:
                ap_checksum = hashlib.file_digest(stream, 'sha256').hexdigest()
            super_image = stage / 'super.img'
            with tarfile.open(ap) as package:
                members = [member for member in package if member.name in ('super.img', 'super.img.lz4')]
                if len(members) != 1 or not members[0].isfile():
                    raise ValueError('Expected one regular S24 super image')
                member = members[0]
                require_space(stage, MAX_IMAGE)
                print('Extracting the S24 super image', flush=True)
                with package.extractfile(member) as source, super_image.open('xb') as destination:
                    if member.name.endswith('.lz4'):
                        with subprocess.Popen(['lz4', '-dc'], stdin=subprocess.PIPE, stdout=destination, preexec_fn=image_limit) as process:
                            try:
                                shutil.copyfileobj(source, process.stdin, 1024 * 1024)
                                process.stdin.close()
                                status = process.wait()
                                if status:
                                    raise subprocess.CalledProcessError(status, process.args)
                            except BaseException:
                                process.kill()
                                raise
                    else:
                        if member.size > MAX_IMAGE:
                            raise ValueError('S24 super image exceeds the extraction limit')
                        shutil.copyfileobj(source, destination, 1024 * 1024)
            ap.unlink()
            with super_image.open('rb') as stream:
                header = stream.read(28)
            if header[:4] == b'\x3a\xff\x26\xed':
                if len(header) != 28:
                    raise ValueError('Truncated S24 sparse image header')
                block_size, blocks = struct.unpack_from('<II', header, 12)
                logical_size = block_size * blocks
                if not 0 < logical_size <= MAX_IMAGE:
                    raise ValueError('Invalid S24 sparse image size')
                require_space(stage, logical_size)
                raw = stage / 'super.raw.img'
                subprocess.run([str(tools / 'simg2img'), str(super_image), str(raw)], check=True, preexec_fn=image_limit)
                super_image.unlink()
                super_image = raw
            software = stage / 'software'
            software.mkdir()
            require_space(stage, MAX_IMAGE)
            print('Extracting only the selected S24 software from its system image', flush=True)
            subprocess.run([str(tools / 'lpunpack'), '-p', 'system', str(super_image), str(stage)], check=True, preexec_fn=image_limit)
            image = stage / 'system.img'
            for name in FILES:
                destination = software / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                inside = name if name.startswith('system/') else 'system/' + name
                with destination.open('xb') as stream:
                    subprocess.run([str(tools / 'dump.erofs'), '--cat', '--path=/' + inside, str(image)], stdout=stream, check=True)
            image.unlink()
            super_image.unlink()
            validate_software(software)
            for name in (name for name in FILES if name.endswith(('.apk', '.jar'))):
                with zipfile.ZipFile(software / name) as component:
                    if component.testzip() is not None:
                        raise ValueError(f'Corrupt S24 software: {name}')
            manifest = {
                'source': 'https://samfw.com/firmware/SM-S921B/XXV/S921BXXS9BYH1',
                'archive': archive_path.name,
                'archive_bytes': archive_path.stat().st_size,
                'ap': ap.name,
                'ap_sha256': ap_checksum,
                'ap_odin_checksum_and_zip_crc_verified': True,
                'model': 'SM-S921B',
                'csc': 'XXV',
                'pda': 'S921BXXS9BYH1',
                'sdk': 35,
                'files': {},
            }
            for name in FILES:
                path = software / name
                with path.open('rb') as stream:
                    checksum = hashlib.file_digest(stream, 'sha256').hexdigest()
                manifest['files'][name] = {'bytes': path.stat().st_size, 'sha256': checksum}
            (software / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
            verify_imported_software(software)
            if output.exists() or output.is_symlink():
                raise FileExistsError(f'S24 software already exists: {output}')
            software.rename(output)
    return output


def main():
    parser = argparse.ArgumentParser(description='Extract pinned Android 15 S24 adaptive-colour software without importing its boot or vendor images')
    parser.add_argument('archive', type=Path)
    args = parser.parse_args()
    output = ROOT / 'out/fw/SM-S921B_XXV/software'
    try:
        extract_software(args.archive, output, ROOT / 'out/tools/bin')
    except (OSError, ValueError, zipfile.BadZipFile, tarfile.TarError, subprocess.SubprocessError) as error:
        parser.exit(1, f'{error}\n')
    print(f'S24 software verified at {output}; temporary images removed')


if __name__ == '__main__':
    main()
