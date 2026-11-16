# The build environment of .github/workflows/release.yml: Debian 13 like the build machine
# (Ubuntu 24.04's libfmt is too old for android-tools), as the runner's user so the host can
# still clean up.
FROM debian:trixie
RUN apt-get update && apt-get install -y --no-install-recommends \
    attr bc bison brotli build-essential ca-certificates clang cmake cpio curl \
    device-tree-compiler dwarves e2fsprogs file flex gawk gh git golang-go gperf kmod lld llvm \
    lz4 meson ninja-build openjdk-21-jdk-headless pcre2-utils perl pkg-config protobuf-compiler \
    python3 python3-dev python3-pip python3-venv python3-protobuf python3-pyelftools \
    python3-jinja2 rsync secilc swig unzip wget xxd xz-utils zip zstd libbrotli-dev libdw-dev \
    libelf-dev libfmt-dev libgmock-dev libgtest-dev liblz4-dev libncurses-dev libpcre2-dev \
    libprotobuf-dev libsepol-dev libssl-dev libudev-dev libunwind-dev libusb-1.0-0-dev \
    libzstd-dev && rm -rf /var/lib/apt/lists/*
RUN useradd -m -u 1001 runner
# depmod and debugfs live in sbin; Java needs a UTF-8 locale for non-ASCII file names.
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin LANG=C.UTF-8 LC_ALL=C.UTF-8
