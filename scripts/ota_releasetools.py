# Device hooks for Samsung's ota_from_target_files (scripts/make_ota.sh passes this file with -s).
# Stock non-A/B OTA code only patches boot; the Flip5 kernel also lives in these images. They
# are small, so a changed one is shipped whole.
import filecmp
import os

import common
import edify_generator

IMAGES = ("init_boot", "vendor_boot", "dtbo", "vbmeta")

# Recovery reports Samsung's own Android 13 recovery fingerprint, and every Onigiri build keeps
# the stock one anyway, so the check can never pass or mean anything. The block hashes the
# script verifies before changing anything are what pin the source build.
edify_generator.EdifyGenerator.AssertSomeFingerprint = lambda self, *fingerprints: None


def IncrementalOTA_InstallEnd(info):
    for name in IMAGES:
        target = os.path.join(info.target_tmp, "IMAGES", name + ".img")
        if filecmp.cmp(target, os.path.join(info.source_tmp, "IMAGES", name + ".img"), shallow=False):
            continue
        common.ZipWrite(info.output_zip, target, name + ".img")
        info.script.Print("Writing %s..." % name)
        # A bare package_extract_file() call ignores a failed write; abort so it isn't reported as installed.
        info.script.AppendExtra('package_extract_file("%s.img", "/dev/block/bootdevice/by-name/%s") || '
                                'abort("E9001: Failed to write %s.");' % (name, name, name))
