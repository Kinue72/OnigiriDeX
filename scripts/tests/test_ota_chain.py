#!/usr/bin/env python3
"""ota_chain.py: hops keep their own files, run in order once each, and chains of chains flatten."""
from pathlib import Path
import re
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ota_chain import MISC, SCRIPT, main  # noqa: E402

META = ("META-INF/com/android/metadata", "META-INF/com/android/metadata.pb",
        "META-INF/com/google/android/update-binary", "META-INF/com/android/otacert")


def package(path, tag):
    with zipfile.ZipFile(path, "w") as z:
        for name in META:
            z.writestr(name, f"{name} {tag}")
        z.writestr("system.patch.dat", f"patch {tag}")
        z.writestr("system.transfer.list", f"list {tag}")
        z.writestr(SCRIPT, f'ui_print("{tag}");\nshow_progress(0.500000, 0);\n'
                           f'block_image_update(map_partition("system"), package_extract_file("system.transfer.list"), '
                           f'"system.new.dat", "system.patch.dat") || abort("E1001: system.patch.dat");\n')
    return path


class ChainTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ota-chain-test-")
        self.dir = Path(self.temp.name)
        self.a, self.b, self.c = (package(self.dir / f"{t}.zip", t) for t in "abc")

    def tearDown(self):
        self.temp.cleanup()

    def chain(self, name, *packages):
        main(str(self.dir / name), [str(p) for p in packages])
        return zipfile.ZipFile(self.dir / name)

    def test_hops_run_in_order_once(self):
        z = self.chain("ab.zip", self.a, self.b)
        hops = z.read("hops").decode().split()
        script = z.read(SCRIPT).decode()
        self.assertEqual(z.read(f"{hops[1]}/system.patch.dat"), b"patch b")
        self.assertEqual(z.read(META[0]), f"{META[0]} b".encode(), "metadata of the last hop")
        # Only names of the hop's own files move into its directory.
        self.assertIn(f'package_extract_file("{hops[0]}/system.transfer.list"), "system.new.dat", '
                      f'"{hops[0]}/system.patch.dat") || abort("E1001: system.patch.dat")', script)
        self.assertEqual(script.count("show_progress(0.250000, 0)"), 2)
        guards = re.findall(r"^if (.*) then$", script, re.M)
        self.assertEqual(guards[0], " && ".join(f'get_stage("{MISC}") != "onigiri:{h}"' for h in hops))
        self.assertEqual(guards[1], f'get_stage("{MISC}") != "onigiri:{hops[1]}"')
        self.assertLess(script.index('ui_print("a")'), script.index(f'"onigiri:{hops[0]}");'))
        self.assertTrue(script.endswith(f'set_stage("{MISC}", "");\n'))

    def test_chain_of_chain_flattens(self):
        ab = self.chain("ab.zip", self.a, self.b)
        abc = self.chain("abc.zip", self.dir / "ab.zip", self.c)
        direct = self.chain("abc-direct.zip", self.a, self.b, self.c)
        self.assertEqual(abc.read("hops"), direct.read("hops"))
        self.assertEqual(abc.read(SCRIPT), direct.read(SCRIPT))
        self.assertEqual(abc.read("hops").decode().split()[:2], ab.read("hops").decode().split())

    def test_repeated_hop_is_refused(self):
        with self.assertRaises(SystemExit):
            self.chain("aa.zip", self.a, self.a)


if __name__ == "__main__":
    unittest.main()
