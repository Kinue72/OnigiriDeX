#!/usr/bin/env python3
"""ota_manifest.py: each model describes its own packages, and the manifest joins them."""
from pathlib import Path
import hashlib
import json
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ota_manifest import manifest, updates  # noqa: E402

NOTES = """## What's Changed
* feat(dex): record the DeX desktop. by @a in https://github.com/o/r/pull/1
* fix: keep the cover awake by @a in https://github.com/o/r/pull/2
* ci: build models side by side by @a in https://github.com/o/r/pull/3
"""


class ManifestTest(unittest.TestCase):
    def test_models_join_and_a_model_without_packages_is_left_out(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "Onigiri_OTA_aaaaaaa.zip").write_bytes(b"one")
            (root / "Onigiri_OTA_bbbbbbb.zip").write_bytes(b"chained")
            (root / "notes.md").write_text(NOTES)
            (root / "previous.json").write_text(json.dumps({"releases": [{"tag": "old"}, {"tag": "new"}]}))
            updates(root / "SM-F731B.updates.json", "SM-F731B",
                    [f"aaaaaaa:{root}/Onigiri_OTA_aaaaaaa.zip", f"bbbbbbb:{root}/Onigiri_OTA_bbbbbbb.zip"])
            updates(root / "SM-F731N.updates.json", "SM-F731N", [])
            manifest(root / "update.json", "new", "ccccccc", root / "notes.md", root / "previous.json",
                     [root / "SM-F731N.updates.json", root / "SM-F731B.updates.json"])
            result = json.loads((root / "update.json").read_text())
        self.assertEqual(result["updates"], {"SM-F731B": {
            "aaaaaaa": {"file": "Onigiri_OTA_aaaaaaa.zip", "size": 3, "sha256": hashlib.sha256(b"one").hexdigest()},
            "bbbbbbb": {"file": "Onigiri_OTA_bbbbbbb.zip", "size": 7, "sha256": hashlib.sha256(b"chained").hexdigest()}}})
        self.assertEqual([release["tag"] for release in result["releases"]], ["new", "old"])
        self.assertEqual(result["releases"][0]["new"], ["Record the DeX desktop"])
        self.assertEqual(result["releases"][0]["fixed"], ["Keep the cover awake"])


if __name__ == "__main__":
    unittest.main()
