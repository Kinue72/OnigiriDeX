#!/usr/bin/env python3
"""Focused host tests. Android loading, Binder hooks and device SELinux still need hardware."""
from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'onigiri/mods/essential/system/bin/onigiri-essential.sh'


class BootStateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='essential-boot-test-')
        self.root = Path(self.temp.name)
        self.data = self.root / 'data/system/onigiri-essential'
        self.rom = self.root / 'system/etc/onigiri-essential'
        self.props = self.root / 'props'
        self.props.mkdir()
        (self.root / 'data/misc').mkdir(parents=True)
        for component in ('hma', 'tee', 'brene'):
            (self.rom / component).mkdir(parents=True)
            (self.rom / component / 'version.properties').write_text('version=builtin\ncode=1\nadapter=1\n')
            (self.data / component / 'releases').mkdir(parents=True)
        (self.rom / 'hma-oss.json').write_text('{"configVersion":93,"user":"default"}')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for name, body in {
            'getprop': 'cat "$PROPS/$1" 2>/dev/null || true',
            'setprop': 'printf "%s" "$2" > "$PROPS/$1"',
            'restorecon': ':', 'chown': ':', 'sync': ':',
        }.items():
            p = self.bin / name
            p.write_text('#!/bin/sh\n' + body + '\n')
            p.chmod(0o755)
        log = self.root / 'system/bin/log'
        log.parent.mkdir(parents=True)
        log.write_text('#!/bin/sh\nexit 0\n')
        log.chmod(0o755)
        source = re.sub(r'/(data|system)/', lambda m: str(self.root) + m[0], SCRIPT.read_text())
        self.script = self.root / 'runtime.sh'
        self.script.write_text(source)
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}', PROPS=str(self.props))

    def tearDown(self):
        self.temp.cleanup()

    def prop(self, name, value=None):
        path = self.props / name
        if value is not None:
            path.write_text(value)
        return path.read_text() if path.exists() else ''

    def prepare(self):
        subprocess.run(['bash', str(self.script), 'prepare'], env=self.env, check=True, capture_output=True)

    def test_fresh_boot_and_existing_config_are_preserved(self):
        config = self.root / 'data/misc/hide_my_applist_existing/config.json'
        config.parent.mkdir()
        original = '{"configVersion":93,"apps":["com.grabtaxi.driver2"]}'
        config.write_text(original)
        self.prepare()
        self.assertEqual(self.prop('sys.onigiri.hma.state'), 'loading')
        self.assertEqual(self.prop('sys.onigiri.hma.enabled'), 'true')
        self.assertEqual(config.read_text(), original)
        # Switch writes affect desired state only, never the current boot snapshot.
        self.prop('persist.sys.onigiri.hma', 'false')
        self.assertEqual(self.prop('sys.onigiri.hma.enabled'), 'true')

    def test_existing_module_choices_default_off(self):
        module = self.root / 'data/adb/modules/hma_oss_zygisk'
        module.mkdir(parents=True)
        self.prepare()
        self.assertEqual(self.prop('sys.onigiri.hma.state'), 'off')
        self.prop('persist.sys.onigiri.hma', 'true')
        self.prepare()
        self.assertEqual(self.prop('sys.onigiri.hma.state'), 'unavailable')
        self.assertFalse((self.data / 'hma/guard').exists())
        (module / 'disable').touch()
        self.prepare()
        self.assertEqual(self.prop('sys.onigiri.hma.state'), 'loading')
        self.assertTrue((module / 'disable').exists())

    def test_completed_legacy_install_is_not_silently_reenabled(self):
        legacy = self.root / 'data/adb/onigiri/rootmods'
        legacy.mkdir(parents=True)
        (legacy / 'hma_oss_zygisk').touch()
        self.prepare()
        self.assertEqual(self.prop('persist.sys.onigiri.hma'), 'false')

    def test_brene_config_is_read_as_data_without_running_shell(self):
        config = self.root / 'data/adb/brene/config.sh'
        config.parent.mkdir(parents=True)
        content = 'config_hide_custom_rom_paths=0\nconfig_hide_addon_d="1"\nconfig_usb_debugging=\nexit 88\n'
        config.write_text(content)
        self.prepare()
        self.assertEqual(self.prop('sys.onigiri.brene.rom_paths'), 'false')
        self.assertEqual(self.prop('sys.onigiri.brene.addon_d'), 'true')
        self.assertEqual(config.read_text(), content)

    def test_guard_disables_retry_without_deleting_configuration(self):
        (self.data / 'hma/guard').touch()
        self.prop('persist.sys.onigiri.hma', 'true')
        self.prepare()
        self.assertEqual(self.prop('persist.sys.onigiri.hma'), 'false')
        self.assertEqual(self.prop('sys.onigiri.hma.state'), 'unavailable')
        self.assertEqual(self.prop('sys.onigiri.hma.enabled'), 'false')
        self.assertFalse((self.data / 'hma/guard').exists())

    def test_interrupted_activation_recovers_at_each_boundary(self):
        old, new = 'a' * 64, 'b' * 64
        component = self.data / 'hma'
        for digest in (old, new):
            release = component / 'releases' / digest
            release.mkdir()
            (release / 'version.properties').write_text(f'version={digest[:1]}\ncode=2\nadapter=1\n')
        self.prop('persist.sys.onigiri.hma', 'false')
        for active in (old, new):
            with self.subTest(active=active):
                (component / 'active').write_text(active)
                (component / 'previous').write_text(old)
                (component / 'pending').write_text(new)
                (component / 'trial').touch()
                (component / 'guard').touch()
                self.prepare()
                self.assertEqual((component / 'active').read_text().strip(), old)
                self.assertFalse((component / 'trial').exists())
                self.assertFalse((component / 'pending').exists())
                self.assertTrue((component / 'releases' / new).is_dir())

    def test_update_selects_payload_while_off_and_defers_runtime_validation(self):
        component = self.data / 'hma'
        digest = 'b' * 64
        release = component / 'releases' / digest
        release.mkdir()
        (release / 'version.properties').write_text('version=new\ncode=2\nadapter=1\n')
        (component / 'pending').write_text(digest)
        self.prop('persist.sys.onigiri.hma', 'false')
        self.prepare()
        self.assertFalse((component / 'pending').exists())
        self.assertEqual(self.prop('sys.onigiri.hma.version'), 'new')
        self.assertEqual(self.prop('sys.onigiri.hma.state'), 'off')
        self.assertTrue((component / 'trial').exists())
        self.prop('persist.sys.onigiri.hma', 'true')
        self.prepare()
        self.assertEqual((component / 'active').read_text().strip(), digest)
        self.assertTrue((component / 'trial').exists())
        self.assertEqual(self.prop('sys.onigiri.hma.state'), 'loading')

    def test_trial_without_previous_override_returns_to_rom(self):
        component = self.data / 'hma'
        (component / 'previous').write_text('')
        (component / 'active').write_text('b' * 64)
        (component / 'trial').touch()
        (component / 'guard').touch()
        self.prop('persist.sys.onigiri.hma', 'false')
        self.prepare()
        self.assertFalse((component / 'active').exists())
        self.assertEqual(self.prop('sys.onigiri.hma.version'), 'builtin')

    def test_recovery_marker_prevents_loading(self):
        (self.data / 'disable').touch()
        self.prepare()
        self.assertEqual(self.prop('sys.onigiri.hma.state'), 'unavailable')
        self.assertFalse((self.data / 'hma/guard').exists())

    def test_failed_brene_probe_rolls_back_on_next_boot(self):
        component = self.data / 'brene'
        old, new = 'a' * 64, 'b' * 64
        for digest, code in ((old, 2), (new, 3)):
            release = component / 'releases' / digest
            release.mkdir()
            (release / 'version.properties').write_text(f'version={code}\ncode={code}\nadapter=1\n')
        probe = component / 'releases' / new / 'susfs'
        probe.write_text('#!/bin/sh\nexit 42\n')
        probe.chmod(0o755)
        (component / 'active').write_text(old)
        (component / 'pending').write_text(new)
        self.prepare()
        result = subprocess.run(['bash', str(self.script), 'brene'], env=self.env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.prop('sys.onigiri.brene.state'), 'unavailable')
        self.assertTrue((component / 'guard').exists())
        self.prepare()
        self.assertEqual((component / 'active').read_text().strip(), old)
        self.assertFalse((component / 'trial').exists())
        self.assertFalse((component / 'guard').exists())
        self.assertEqual(self.prop('sys.onigiri.brene.enabled'), 'false')

    def assert_manager_rollback(self, previous):
        component = self.data / 'hma'
        old, new = 'a' * 64, 'b' * 64
        (self.rom / 'hma/manager.apk').write_text('1')
        for digest, code in ((old, 2), (new, 3)):
            release = component / 'releases' / digest
            release.mkdir()
            (release / 'version.properties').write_text(f'version={code}\ncode={code}\nadapter=1\n')
            (release / 'manager.apk').write_text(str(code))
        installed = self.root / 'installed.apk'
        installed.write_text('2' if previous else '1')
        self.env['INSTALLED_APK'] = str(installed)
        pm = self.bin / 'pm'
        pm.write_text('''#!/bin/sh
case "$1" in
    path) printf 'package:%s\n' "$INSTALLED_APK";;
    install)
        shift
        downgrade=false
        for arg in "$@"; do
            case "$arg" in -d) downgrade=true;; -r) ;; *) apk=$arg;; esac
        done
        if [ "$(cat "$apk")" -lt "$(cat "$INSTALLED_APK")" ] && [ "$downgrade" != true ]; then
            echo 'Failure [INSTALL_FAILED_VERSION_DOWNGRADE]'
            exit 1
        fi
        cp "$apk" "$INSTALLED_APK"
        echo install >> "$INSTALLED_APK.log"
        echo Success;;
esac
''')
        pm.chmod(0o755)
        # Keep the real monitor loop, but skip wall-clock delays in this manager-sync test.
        (self.bin / 'sleep').write_text('#!/bin/sh\nexit 0\n')
        (self.bin / 'sleep').chmod(0o755)
        for name in ('tee', 'brene'):
            self.prop(f'persist.sys.onigiri.{name}', 'false')
        config = self.root / 'data/misc/hide_my_applist_existing/config.json'
        config.parent.mkdir()
        original = '{"configVersion":93,"apps":["com.grabtaxi.driver2"]}'
        config.write_text(original)
        if previous:
            (component / 'active').write_text(old)
        (component / 'pending').write_text(new)
        self.prepare()

        def boot_complete():
            subprocess.run(['bash', str(self.script), 'boot-complete'], env=self.env,
                           check=True, capture_output=True, timeout=30)

        boot_complete()
        self.assertEqual(installed.read_text(), '3')
        self.assertEqual(self.prop('sys.onigiri.hma.state'), 'ready')
        # No loader reports Active: the trial fails and its guard must remain armed.
        self.assertTrue((component / 'guard').exists())
        self.prepare()
        self.assertFalse((component / 'trial').exists())
        self.assertEqual(self.prop('sys.onigiri.hma.enabled'), 'false')
        self.prop('persist.sys.onigiri.hma', 'true')
        self.prepare()
        self.assertEqual(self.prop('sys.onigiri.hma.state'), 'loading')
        boot_complete()
        self.assertEqual(installed.read_text(), '2' if previous else '1')
        self.assertEqual(self.prop('sys.onigiri.hma.state'), 'ready')
        self.assertEqual(config.read_text(), original)
        # The next boot leaves an identical manager in place.
        self.prop('sys.onigiri.hma.state', 'loading')
        boot_complete()
        self.assertEqual(Path(str(installed) + '.log').read_text().splitlines(), ['install', 'install'])

    def test_hma_rollback_restores_previous_manager(self):
        self.assert_manager_rollback(previous=True)

    def test_hma_rollback_restores_bundled_manager(self):
        self.assert_manager_rollback(previous=False)

    def test_update_marks_checking_even_when_java_cannot_start(self):
        launcher = self.root / 'system/bin/app_process'
        launcher.write_text('#!/bin/sh\n[ "$(getprop sys.onigiri.hma.update)" = checking ] || exit 99\nexit 41\n')
        launcher.chmod(0o755)
        for _ in range(2):
            self.prop('sys.onigiri.hma.update', 'requested')
            result = subprocess.run(['bash', str(self.script), 'update', 'hma'], env=self.env, capture_output=True)
            self.assertEqual(result.returncode, 41)
            # Init can now turn checking into error when this service stops.
            self.assertEqual(self.prop('sys.onigiri.hma.update'), 'checking')


if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='essential-javac-') as classes:
        sources = sorted((ROOT / 'onigiri/mods/essential/java').glob('**/*.java'))
        subprocess.run(['javac', '--release', '8', '-Xlint:-options', '-d', classes, *map(str, sources),
                        str(ROOT / 'scripts/tests/EssentialUpdateTest.java')], check=True)
        subprocess.run(['java', '-ea', '-cp', classes, 'moe.foss.onigiri.EssentialUpdateTest', str(ROOT)], check=True)
    unittest.main()
