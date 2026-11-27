#!/usr/bin/env python3
"""Build the small adapters and extract checksum-pinned upstream payloads."""
import hashlib
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

R8_SHA256 = 'f24d7ae8332eecd5329906656aa687022c111b1e31992c04a154f649377be3f2'
# The upstream TEESimulator archive carries an AOSP software attestation keybox whose
# intermediate expired in January 2026, which fails every verdict on a fresh install. A
# third-party keybox is not published in this repository; keep it at
# onigiri/mods/essential/tee-keybox.xml (git-ignored). It has to last until a boot with network:
# a connected device replaces it, and an offline one keeps running whatever the image carried.
TEE_KEYBOX_REFRESH_WINDOW = timedelta(days=14)


def keybox_expiry(path):
    """The leaf's notAfter, read from the file so it cannot drift from the key itself."""
    data = path.read_bytes()
    # Structure is not advisory: a secret that is not a keybox must never reach an image.
    if b'<AndroidAttestation' not in data or b'<Keybox' not in data:
        raise ValueError(f'{path.name} is not a keybox')
    pem = re.search(rb'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', data, re.S)
    if pem is None:
        raise ValueError(f'{path.name} carries no certificate')
    try:
        listed = subprocess.run(['openssl', 'x509', '-noout', '-enddate'],
                                input=pem.group(0), capture_output=True, check=True).stdout
    except OSError:
        print('warning: openssl missing; cannot date-check tee-keybox.xml', file=sys.stderr)
        return None
    except subprocess.CalledProcessError:
        raise ValueError(f'{path.name} has a certificate openssl cannot read') from None
    value = ' '.join(listed.decode().strip().split('=', 1)[-1].split())
    return datetime.strptime(value, '%b %d %H:%M:%S %Y %Z').replace(tzinfo=timezone.utc)


def supplied_keybox(module):
    """The supplied keybox, or None when this checkout has none."""
    path = module / 'tee-keybox.xml'
    if not path.is_file():
        print('warning: no tee-keybox.xml; keeping the archive keybox, so fresh installs fail '
              'integrity checks', file=sys.stderr)
        return None
    expiry = keybox_expiry(path)
    if expiry is not None:
        remaining = expiry - datetime.now(timezone.utc)
        if remaining <= timedelta(0):
            print('warning: tee-keybox.xml has expired; devices refresh theirs at boot, but a '
                  'fresh offline install fails integrity checks', file=sys.stderr)
        elif remaining < TEE_KEYBOX_REFRESH_WINDOW:
            print(f'warning: tee-keybox.xml expires in {remaining.days} days; refresh it before '
                  'release', file=sys.stderr)
    return path


def build(src, work, r8):
    if hashlib.sha256(r8.read_bytes()).hexdigest() != R8_SHA256:
        raise ValueError('Unexpected R8 compiler; run build_dependencies')
    module = src / 'onigiri/mods/essential'
    supplied = supplied_keybox(module)
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
        checker = temp / 'KeyboxCheck.java'
        checker.write_text('''package moe.foss.onigiri;
import java.nio.file.*;
public final class KeyboxCheck {
 public static void main(String[] a) throws Exception {
  KeyboxUpdate.verify(Files.readAllBytes(Paths.get(a[0])), false);
 }
}
''')
        sources = sorted(module.glob('java/**/*.java'))
        subprocess.run(['javac', '--release', '8', '-d', str(classes), *map(str, sources),
                        str(runner), str(checker)], check=True)
        if supplied is not None:
            # The image must not carry a key the device's own rules would refuse. Expiry stays
            # advisory here; the chains, the pinned root and the private keys do not.
            checked = subprocess.run(['java', '-cp', str(classes), 'moe.foss.onigiri.KeyboxCheck',
                                      str(supplied)], capture_output=True, text=True)
            if checked.returncode != 0:
                raise ValueError(f'{supplied.name} is not a usable keybox:\n{checked.stderr.strip()}')
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
        # The payload always carries a keybox, because extract() never writes one from the
        # archive: a payload staged from the feed must not bring its own key. Without a
        # supplied file, the archive's expired key is all there is, as supplied_keybox warned.
        shipped = dest / 'tee/keybox.xml'
        if supplied is None:
            tee_archive = root / [a for a in assets if a['url'] == feed['tee.url']][0]['path']
            with zipfile.ZipFile(tee_archive) as archive:
                shipped.write_bytes(archive.read('keybox.xml'))
        else:
            shutil.copyfile(supplied, shipped)
        shipped.chmod(0o644)
        (dest / 'tee/version.properties').chmod(0o644)
        java_home = Path(shutil.which('javac')).resolve().parent.parent
        host_only = ('PayloadPackager.class', 'KeyboxCheck.class')
        runtime_classes = [p for p in classes.rglob('*.class') if p.name not in host_only]
        subprocess.run(['java', '-cp', str(r8), 'com.android.tools.r8.D8', '--release', '--min-api', '35',
                        '--lib', str(java_home), '--output', str(dex), *map(str, runtime_classes)], check=True)
        jar = work / 'system/system/framework/onigiri-essential.jar'
        jar.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(jar, 'w', zipfile.ZIP_DEFLATED) as output:
            for path in sorted(dex.glob('*.dex')):
                entry = zipfile.ZipInfo(path.name, (2008, 1, 1, 0, 0, 0))
                entry.compress_type = zipfile.ZIP_DEFLATED
                output.writestr(entry, path.read_bytes())
    hma_config = module / 'hma-oss.json'
    if json.loads(hma_config.read_text())['configVersion'] != 93:
        raise ValueError('HMA configuration is incompatible with adapter 3')
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
