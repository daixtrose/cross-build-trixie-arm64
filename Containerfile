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

# ── Extra host-side tooling (Java codegen, protoc, comfort tools) ────
# Requested by Java-using consumers of the image who want a full host
# build environment without having to install these packages every
# time they spin up the container.  All packages are HOST x86_64 —
# the aarch64 cross-compiler still uses the sysroot for runtime.
RUN apt-get update && apt-get install -y --no-install-recommends \
        # Meta + build helpers
        build-essential \
        socat \
        # Host protobuf/gRPC (for protoc + protoc-gen-grpc on x86_64,
        # used to generate proto bindings before the cross-compile step)
        libprotobuf-dev \
        protobuf-compiler \
        libgrpc++-dev \
        protobuf-compiler-grpc \
        # JVM toolchain for Java grpc-commander builds
        openjdk-25-jdk \
        gradle \
        # Comfort tools so people can poke around inside the container
        btop \
        emacs-nox \
        tcsh \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 24 (for Forgejo / Gitea Actions JS actions) ──────────────
# Forgejo's act-runner executes JavaScript actions (actions/checkout,
# actions/cache, actions/upload-artifact, …) via `docker exec node …`
# *inside* this container.  Without node here, `actions/checkout@v4`
# fails immediately with "exec: node: executable file not found in
# $PATH".  GitHub Actions sidesteps this by running JS actions on the
# runner host instead of the workflow container; act-runner does not.
#
# Node 24 LTS picked to match FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true
# in consumer release.yml files.  Installed from nodejs.org's official
# tarball (no extra apt source) so it stays decoupled from Ubuntu's
# nodejs package and only adds ~80 MB.
RUN set -eux; \
    apt-get update && apt-get install -y --no-install-recommends xz-utils \
        && rm -rf /var/lib/apt/lists/*; \
    NODE_VERSION="24.15.0"; \
    wget -q -O /tmp/node.tar.xz \
        "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz"; \
    mkdir -p /opt/nodejs; \
    tar -xJf /tmp/node.tar.xz --strip-components=1 -C /opt/nodejs; \
    ln -s /opt/nodejs/bin/node /usr/local/bin/node; \
    ln -s /opt/nodejs/bin/npm  /usr/local/bin/npm; \
    ln -s /opt/nodejs/bin/npx  /usr/local/bin/npx; \
    rm -f /tmp/node.tar.xz; \
    node --version && npm --version

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
#
# Pre-installed dev packages in the sysroot (saves ~20 min of
# cross-built FetchContent per CI run downstream):
#   - libgrpc++-dev / libprotobuf-dev: gRPC + protobuf C++ libs + headers,
#     so smarcel-core-{status,controller}/grpc-service/CMakeLists.txt's
#     `find_package(gRPC CONFIG QUIET)` succeeds and the FetchContent
#     fallback never runs.  Trixie ships gRPC 1.71 (matches our pin in
#     spirit; minor version drift is fine for the callback API + the
#     wire protocol).
#   - libsystemd-dev / libssl-dev: typical transitive deps for grpc
#     and other server libs.
RUN debootstrap \
        --arch=arm64 \
        --variant=minbase \
        --include=libc6-dev,linux-libc-dev,libgrpc++-dev,libprotobuf-dev,libssl-dev,libsystemd-dev,zlib1g-dev \
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

# ── QEMU sysroot prefix ───────────────────────────────────────────────
# qemu-aarch64-static needs to resolve the dynamic linker
# (/lib/ld-linux-aarch64.so.1) against the Trixie sysroot, not the
# host's empty / .  QEMU_LD_PREFIX is the standard env var for this.
# Setting it here means every `qemu-aarch64-static <binary>` inside
# the container — including ctest's CMAKE_CROSSCOMPILING_EMULATOR
# invocations — picks up the sysroot automatically, no per-call flag.
ENV QEMU_LD_PREFIX=/opt/trixie-arm64-sysroot

# ── Labels ────────────────────────────────────────────────────────────
LABEL org.opencontainers.image.title="cross-build-trixie-arm64"
LABEL org.opencontainers.image.description="GCC 14 cross-compilation environment targeting Debian Trixie aarch64 (glibc 2.41)"
LABEL org.opencontainers.image.source="https://github.com/daixtrose/cross-build-trixie-arm64"
LABEL org.opencontainers.image.licenses="MIT"

WORKDIR /workspace
