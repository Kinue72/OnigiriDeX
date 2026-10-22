#!/usr/bin/env python3
"""Build the small adapters and extract checksum-pinned upstream payloads."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

R8_SHA256 = 'f24d7ae8332eecd5329906656aa687022c111b1e31992c04a154f649377be3f2'


def build(src, work, r8):
    if hashlib.sha256(r8.read_bytes()).hexdigest() != R8_SHA256:
        raise ValueError('Unexpected R8 compiler; run build_dependencies')
    module = src / 'onigiri/mods/essential'
    root = src / 'prebuilts/rootmods'
    feed = dict(line.split('=', 1) for line in (root / 'bundled.properties').read_text().splitlines()
                if line and not line.startswith('#'))
    assets = json.loads((root / 'manifest.json').read_text())['assets']
    # Keystore's linker permits framework payloads, but not /system/etc libraries.
    dest = work / 'system/system/framework/onigiri-essential'
    dest.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='onigiri-essential-') as temp:
        temp = Path(temp)
        classes, dex = temp / 'classes', temp / 'dex'
        classes.mkdir()
        dex.mkdir()
        runner = temp / 'PayloadPackager.java'
        runner.write_text('''package moe.foss.onigiri;
import java.nio.file.*;
public final class PayloadPackager {
 public static void main(String[] a) throws Exception {
  EssentialUpdate.extract(a[0], Paths.get(a[1]), Paths.get(a[2]), EssentialUpdate.readProperties(Paths.get(a[3])));
 }
}
''')
        sources = sorted(module.glob('java/**/*.java'))
        subprocess.run(['javac', '--release', '8', '-d', str(classes), *map(str, sources), str(runner)], check=True)
        for component in ('hma', 'tee', 'brene'):
            url = feed[f'{component}.url']
            asset, = [a for a in assets if a['url'] == url]
            archive = root / asset['path']
            if archive.is_symlink() or hashlib.sha256(archive.read_bytes()).hexdigest() != asset['sha256']:
                raise ValueError(f'Invalid pinned archive: {archive}')
            if asset['sha256'] != feed[f'{component}.sha256'] or asset['bytes'] != int(feed[f'{component}.bytes']):
                raise ValueError(f'Bundled release differs from build manifest: {component}')
            subprocess.run(['java', '-cp', str(classes), 'moe.foss.onigiri.PayloadPackager', component,
                            str(archive), str(dest / component), str(root / 'bundled.properties')], check=True)
            # Properties.store emits a timestamp; normalize build metadata for repeatable OTAs.
            version = dest / component / 'version.properties'
            version.chmod(0o644)
            version.write_text('\n'.join(sorted(line for line in version.read_text().splitlines()
                                               if line and not line.startswith('#'))) + '\n')
        java_home = Path(shutil.which('javac')).resolve().parent.parent
        runtime_classes = [p for p in classes.rglob('*.class') if p.name != 'PayloadPackager.class']
        subprocess.run(['java', '-cp', str(r8), 'com.android.tools.r8.D8', '--release', '--min-api', '35',
                        '--lib', str(java_home), '--output', str(dex), *map(str, runtime_classes)], check=True)
        jar = work / 'system/system/framework/onigiri-essential.jar'
        jar.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(jar, 'w', zipfile.ZIP_DEFLATED) as output:
            for path in sorted(dex.glob('*.dex')):
                entry = zipfile.ZipInfo(path.name, (2008, 1, 1, 0, 0, 0))
                entry.compress_type = zipfile.ZIP_DEFLATED
                output.writestr(entry, path.read_bytes())
    hma_config = src / 'onigiri/mods/rootmods/hma-oss.json'
    if json.loads(hma_config.read_text())['configVersion'] != 93:
        raise ValueError('HMA configuration is incompatible with adapter 1')
    shutil.copyfile(hma_config, dest / 'hma-oss.json')
    manager = work / 'system/system/app/HMAOSS/HMAOSS.apk'
    manager.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(dest / 'hma/manager.apk', manager)
    # Keep the upstream APK signature; never decode or platform-sign the manager.
    with (work / 'configs/fs_config-system').open('a') as fs, (work / 'configs/file_context-system').open('a') as contexts:
        for path in [dest, *sorted(dest.rglob('*')), jar, manager.parent, manager]:
            mode = 755 if path.is_dir() or path.name in ('susfs', 'inject', 'libTEESimulator.so') else 644
            path.chmod(int(str(mode), 8))
            rel = path.relative_to(work / 'system').as_posix()
            fs.write(f'{rel} 0 0 {mode} capabilities=0x0\n')
            label = 'onigiri_essential_file' if path == dest or dest in path.parents else 'system_file'
            contexts.write('/' + rel.replace('.', r'\.') + f' u:object_r:{label}:s0\n')


if __name__ == '__main__':
    build(*(Path(arg).resolve() for arg in sys.argv[1:]))
