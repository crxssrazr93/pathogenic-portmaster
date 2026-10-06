#!/usr/bin/env bash
# Build the sentry-godot 1.6.0 "noop" GDExtension for Linux arm64 (old glibc).
# Output: build/sentry/libsentry.linux.release.arm64.so
# Needs: docker, git, network. Compiles in ubuntu:20.04.
set -euo pipefail
cd "$(dirname "$0")"
HERE="$PWD"

# 1. Fetch sentry-godot 1.6.0 and only the godot-cpp submodule.
if [ ! -d src/.git ]; then
  git clone -q --depth 1 --branch 1.6.0 https://github.com/getsentry/sentry-godot.git src
fi
git -C src submodule update --init --depth 1 modules/godot-cpp

# 2. Force the noop SDK for arm64 too (stock SConstruct only does arm32/rv64).
sed -i 's/if arch in \["arm32", "rv64"\]:/if arch in ["arm32", "rv64", "arm64"]:/' src/SConstruct
grep -q '"arm64"\]:' src/SConstruct

# 3. Cross compile in ubuntu:20.04 (glibc 2.31 sysroot; buster's python 3.7 is too old for godot-cpp).
docker run --rm -v "$HERE/src:/src" -w /src ubuntu:20.04 bash -euxc '
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu python3 python3-pip git ca-certificates
  pip3 install scons
  # godot-cpp ignores CC/CXX, so shadow the native tool names with the cross ones.
  for t in gcc g++ cpp ar ranlib ld strip; do
    ln -sf "$(command -v aarch64-linux-gnu-$t)" /usr/local/bin/$t
  done
  # Build only the library (default targets also want the gdUnit4 submodule).
  scons platform=linux arch=arm64 target=template_release -j"$(nproc)" \
    project/addons/sentry/bin/noop/libsentry.linux.release.arm64.so
'

# 4. Collect the library under the name the .gdextension expects.
cp src/project/addons/sentry/bin/noop/libsentry.linux.release.arm64.so \
   "$HERE/libsentry.linux.release.arm64.so"

# 5. Install where the launcher expects it (and where build/package.sh picks it up).
dest="$HERE/../../port/pathogenic/addons/sentry/bin/linux/arm64"
mkdir -p "$dest"; cp "$HERE/libsentry.linux.release.arm64.so" "$dest/"
echo "installed: $dest/libsentry.linux.release.arm64.so"
