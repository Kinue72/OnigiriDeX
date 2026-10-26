#!/usr/bin/env python3
"""The boot hook writes misc, which recovery also uses: it may only touch its own cookie."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'onigiri/mods/settings/system/bin/onigiri-autoboot.sh'
RECOVERY = b'boot-recovery'.ljust(32, b'\0')
COOKIE = b'qmmi'.ljust(32, b'\0')


class CookieTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='autoboot-test-')
        root = Path(self.temp.name)
        self.misc = root / 'misc'
        self.cmdline = root / 'cmdline'
        self.props = root / 'props'
        self.props.mkdir()
        (root / 'battery').mkdir()
        self.capacity = root / 'battery/capacity'
        self.autoboot = root / 'autoboot'
        bin_dir = root / 'bin'
        bin_dir.mkdir()
        for name, body in {'getprop': 'cat "$PROPS/$1" 2>/dev/null || true',
                           'setprop': 'printf "%s" "$2" > "$PROPS/$1"'}.items():
            (bin_dir / name).write_text(f'#!/bin/sh\n{body}\n')
            (bin_dir / name).chmod(0o755)
        source = SCRIPT.read_text()
        for device, fake in {'/dev/block/by-name/misc': self.misc, '/proc/cmdline': self.cmdline,
                             '/sys/class/power_supply': root, '/cache/onigiri/autoboot': self.autoboot,
                             '/dev/kmsg': os.devnull}.items():
            source = source.replace(device, str(fake))
        self.script = root / 'autoboot.sh'
        self.script.write_text(source)
        self.env = dict(os.environ, PATH=f'{bin_dir}:{os.environ["PATH"]}', PROPS=str(self.props))

    def tearDown(self):
        self.temp.cleanup()

    def boot(self, autoboot, command, cmdline='lpcharge=0', capacity='80'):
        tail = bytes(range(256)) * 4
        self.misc.write_bytes(command + tail)
        self.autoboot.write_text(autoboot)
        self.cmdline.write_text(cmdline)
        self.capacity.write_text(capacity)
        subprocess.run(['sh', str(self.script)], env=self.env, check=True)
        data = self.misc.read_bytes()
        self.assertEqual(data[32:], tail)
        powerctl = self.props / 'sys.powerctl'
        return data[:32], powerctl.read_text() if powerctl.exists() else ''

    def test_cookie_on_every_boot_but_never_over_recovery_command(self):
        for autoboot in ('true', 'false'):
            self.assertEqual(self.boot(autoboot, bytes(32)), (COOKIE, ''))
            self.assertEqual(self.boot(autoboot, COOKIE), (COOKIE, ''))
            self.assertEqual(self.boot(autoboot, RECOVERY), (RECOVERY, ''))

    def test_charger_boot_through_cookie(self):
        charger = 'sec_qc_user_reset.boot_mode="charger" sec-battery.lpcharge=1'
        self.assertEqual(self.boot('true', COOKIE, charger), (COOKIE, 'reboot'))
        # Without autoboot, or below 5%, charger mode takes over again without the cookie.
        self.assertEqual(self.boot('false', COOKIE, charger), (bytes(32), 'shutdown'))
        self.assertEqual(self.boot('true', COOKIE, charger, '3'), (bytes(32), 'shutdown'))


if __name__ == '__main__':
    unittest.main()
