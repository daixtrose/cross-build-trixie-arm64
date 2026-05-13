# OCI container image for cross-compiling C++23 (GCC 14) targeting
# Debian Trixie aarch64 (glibc 2.41).
#
# Mirror of the cross-build-bookworm-arm64 image at
# https://github.com/daixtrose/cross-build-bookworm-arm64, with the
# sysroot bumped from Bookworm (glibc 2.36) to Trixie (glibc 2.41).
# Trixie's glibc is newer than the Ubuntu 24.04 host (glibc 2.39),
# so cross-built binaries pick up the newer libc symbols directly
# from the sysroot.
#
# The image provides:
#   - GCC 14 aarch64-linux-gnu cross-compiler (C++23, std::format, std::print)
#   - GCC 14 native x86_64 compiler (for host tools)
#   - Debian Trixie arm64 sysroot at /opt/trixie-arm64-sysroot
#   - CMake, autotools, pkg-config, CPack helpers (dpkg-dev, rpm)
#   - qemu-aarch64-static (so ctest can run cross-built aarch64 tests)
#
# Used by the RevolutionPi 5 / Raspberry Pi 5 deployment of the
# Smarcel Core firmware (smarcel-core-status, smarcel-core-controller).

FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# ── Host toolchain & build essentials ─────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        # GCC 14 cross-compiler for aarch64
        g++-14-aarch64-linux-gnu \
        gcc-14-aarch64-linux-gnu \
        binutils-aarch64-linux-gnu \
        # GCC 14 native (for host-side tools during build)
        g++-14 \
        gcc-14 \
        # Build systems
        make \
        ninja-build \
        # Autotools
        autoconf \
        automake \
        libtool \
        # Package config
        pkg-config \
        # Packaging
        dpkg-dev \
        rpm \
        file \
        # SCM & networking
        git \
        wget \
        ca-certificates \
        # Sysroot creation
        debootstrap \
        qemu-user-static \
    && rm -rf /var/lib/apt/lists/*

# ── CMake 4.2.3 ──────────────────────────────────────────────────────
ARG CMAKE_VERSION=4.2.3
RUN wget -qO- "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz" \
    | tar xz -C /opt \
    && ln -s /opt/cmake-${CMAKE_VERSION}-linux-x86_64/bin/cmake  /usr/local/bin/cmake \
    && ln -s /opt/cmake-${CMAKE_VERSION}-linux-x86_64/bin/ctest  /usr/local/bin/ctest \
    && ln -s /opt/cmake-${CMAKE_VERSION}-linux-x86_64/bin/cpack  /usr/local/bin/cpack \
    && cmake --version

# ── Trixie aarch64 sysroot ──────────────────────────────────────────
# Full Debian Trixie arm64 sysroot with C library development files.
# This provides glibc 2.41 headers and libraries so that cross-compiled
# binaries are compatible with Trixie-based systems (RevolutionPi 5,
# Raspberry Pi OS Trixie, …).
#
# Requires binfmt_misc + qemu-aarch64-static on the HOST kernel so
# debootstrap can execute arm64 package scripts via QEMU emulation.
# In CI, this is set up via docker/setup-qemu-action before the build.
RUN debootstrap \
        --arch=arm64 \
        --variant=minbase \
        --include=libc6-dev,linux-libc-dev \
        trixie \
        /opt/trixie-arm64-sysroot \
        http://deb.debian.org/debian

# ── Remove host's glibc 2.39 aarch64 headers ─────────────────────────
# The GCC 14 cross-compiler ships its own /usr/aarch64-linux-gnu/include/
# (from the libc6-dev-arm64-cross package, glibc 2.39).  That path is
# NOT affected by --sysroot and takes precedence.  Even though host
# (2.39) is OLDER than target (2.41), letting the sysroot's 2.41
# headers be authoritative keeps the build self-consistent and lets
# code pick up symbols newer than 2.39 if it wants to.
# Keep the c++/ subdirectory (libstdc++ headers from GCC 14).
RUN find /usr/aarch64-linux-gnu/include/ -maxdepth 1 \
        -not -name include -not -name c++ -exec rm -rf {} +

# ── Verification ──────────────────────────────────────────────────────
RUN ls /opt/trixie-arm64-sysroot/usr/lib/aarch64-linux-gnu/libc.so.6 \
    && echo "✓ Sysroot contains aarch64 libc.so.6 (runtime)" \
    || (echo "✗ aarch64 libc.so.6 not found in sysroot" && exit 1)
RUN ls /opt/trixie-arm64-sysroot/usr/lib/aarch64-linux-gnu/libc.so \
    && echo "✓ Sysroot contains aarch64 libc.so (linker script)" \
    || (echo "✗ aarch64 libc.so linker script not found in sysroot" && exit 1)
RUN ls /opt/trixie-arm64-sysroot/usr/lib/aarch64-linux-gnu/crt1.o \
    && echo "✓ Sysroot contains aarch64 crt1.o (C runtime startup)" \
    || (echo "✗ aarch64 crt1.o not found in sysroot" && exit 1)
RUN grep -q '__GLIBC_MINOR__.*41' /opt/trixie-arm64-sysroot/usr/include/features.h \
    && echo "✓ Sysroot headers report glibc 2.41" \
    || (echo "✗ Sysroot headers do not report glibc 2.41" && exit 1)
RUN test ! -f /usr/aarch64-linux-gnu/include/features.h \
    && echo "✓ Host glibc 2.39 headers removed (no shadowing)" \
    || (echo "✗ Host glibc 2.39 headers still present" && exit 1)

# ── Default compiler symlinks ─────────────────────────────────────────
# Ensure 'gcc' / 'g++' point to version 14
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 100 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-14 100

# ── Labels ────────────────────────────────────────────────────────────
LABEL org.opencontainers.image.title="cross-build-trixie-arm64"
LABEL org.opencontainers.image.description="GCC 14 cross-compilation environment targeting Debian Trixie aarch64 (glibc 2.41)"
LABEL org.opencontainers.image.source="https://github.com/daixtrose/cross-build-trixie-arm64"
LABEL org.opencontainers.image.licenses="MIT"

WORKDIR /workspace
