# cross-build-trixie-arm64

OCI container image for cross-compiling **C++23** applications with **GCC 14** targeting **Debian Trixie aarch64** (glibc 2.41).

## Purpose

Sibling of [`cross-build-bookworm-arm64`](https://github.com/daixtrose/cross-build-bookworm-arm64) with the sysroot bumped to Debian Trixie (glibc 2.41) for the Raspberry Pi 5 / Revolution Pi 5 deployment platform.

When cross-compiling on Ubuntu 24.04 (glibc 2.39) with `g++-14-aarch64-linux-gnu`, the cross-compiler ships its own aarch64 libc headers (glibc 2.39).  By pointing `--sysroot=/opt/trixie-arm64-sysroot` and (optionally) linking with `-static-libstdc++ -static-libgcc`, the resulting binaries:

- Use **C++23** features (`std::format`, `std::print`, …) from GCC 14
- Link against **glibc 2.41** symbols (Trixie-native)
- Run on Trixie-based systems (Raspberry Pi OS Trixie, Revolution Pi Trixie images, …)

## Contents

| Component | Version | Path |
|---|---|---|
| GCC 14 aarch64 cross-compiler | 14.x (Ubuntu 24.04) | `aarch64-linux-gnu-g++-14` |
| GCC 14 native compiler | 14.x (Ubuntu 24.04) | `g++-14` |
| Trixie aarch64 sysroot | glibc 2.41 | `/opt/trixie-arm64-sysroot` |
| CMake | 4.2.3 | `cmake` |
| Autotools | autoconf, automake, libtool | — |
| Packaging | dpkg-dev, rpm | — |
| QEMU user-mode | aarch64-static | `/usr/bin/qemu-aarch64-static` (for `ctest`) |

## Usage

### Pull the image

```bash
# Docker
docker pull ghcr.io/daixtrose/cross-build-trixie-arm64:latest

# Podman
podman pull ghcr.io/daixtrose/cross-build-trixie-arm64:latest
```

### Use in GitHub Actions

```yaml
jobs:
  build-aarch64-trixie:
    runs-on: ubuntu-24.04
    container:
      image: ghcr.io/daixtrose/cross-build-trixie-arm64:latest
    steps:
      - uses: actions/checkout@v4
      - name: Configure
        run: cmake -S . -B build -GNinja \
               -DCMAKE_TOOLCHAIN_FILE=$PWD/cmake/toolchain-linux-aarch64.cmake \
               -DCMAKE_BUILD_TYPE=Release
      - name: Build
        run: cmake --build build --parallel
      - name: Test (cross-built binaries via qemu-aarch64-static)
        run: ctest --test-dir build --output-on-failure
```

### CMake toolchain file

```cmake
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(CMAKE_C_COMPILER   aarch64-linux-gnu-gcc-14)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++-14)
set(CMAKE_STRIP        aarch64-linux-gnu-strip)

set(CMAKE_SYSROOT /opt/trixie-arm64-sysroot)

# Let ctest run cross-built binaries under QEMU on x86_64 hosts.
set(CMAKE_CROSSCOMPILING_EMULATOR /usr/bin/qemu-aarch64-static)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
```

### Compile a test program

```bash
docker run --rm -v "$PWD:/workspace" ghcr.io/daixtrose/cross-build-trixie-arm64:latest \
  aarch64-linux-gnu-g++-14 -std=c++23 \
    --sysroot=/opt/trixie-arm64-sysroot \
    -o /workspace/hello /workspace/hello.cpp
```

## Building locally

```bash
# With Buildah (OCI native)
buildah bud --format oci -t cross-build-trixie-arm64:latest -f Containerfile .

# With Docker
docker build -t cross-build-trixie-arm64:latest -f Containerfile .

# With Podman
podman build --format oci -t cross-build-trixie-arm64:latest -f Containerfile .
```

Requires QEMU user-mode (`qemu-user-static`) on the host kernel so `debootstrap` can execute arm64 package scripts during sysroot creation.

## Schedule

The image is automatically rebuilt monthly (1st of each month) to pick up security updates from the Ubuntu 24.04 base image and from the Trixie sysroot.

## License

[MIT](LICENSE)
