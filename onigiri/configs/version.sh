ROM_VERSION="$(git -C "$SRC_DIR" rev-parse --short HEAD)"
# Named after the kernel's own inputs rather than the ROM commit, so ROM-only releases reuse
# the kernel and their OTAs leave boot, vendor_boot and the module partitions untouched.
KERNEL_VERSION="$({ git -C "$SRC_DIR" rev-parse :external/kernel; cat "$SRC_DIR"/external/patches/kernel/*.patch; } | sha256sum | cut -c1-7)"
KERNEL_RELEASE="5.15.216-android13-8-onigiri-$KERNEL_VERSION"
ROM_CODENAME="Onigiri"
ROM_IS_OFFICIAL=false
