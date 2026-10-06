#!/usr/bin/env bash
# Build GoZen (gde_gozen b852674, FFmpeg 7.1) for linux arm64 (Ubuntu 20.04 toolchain, glibc 2.31 sysroot).
# Usage: ./build.sh        (needs docker + network; output: out/libgozen.linux.template_release.arm64.so)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/gde_gozen"
# Upstream repository (or a local checkout of it: GOZEN_REPO=/path/to/gde_gozen ./build.sh)
GOZEN_REPO="${GOZEN_REPO:-https://codeberg.org/gozen/gde_gozen.git}"

if [ "${1:-}" != "--inner" ]; then
  # 1. Sources: gozen at b852674 (from GOZEN_REPO), submodules at the commits it pins.
  [ -d "$SRC/.git" ] || git clone -q "$GOZEN_REPO" "$SRC"
  git -C "$SRC" cat-file -e b852674 2>/dev/null || git -C "$SRC" fetch -q origin b852674
  git -C "$SRC" checkout -q -f b852674 -- src SConstruct build.py || true
  fetch() { # dir url sha
    [ -d "$SRC/$1/.git" ] && return
    mkdir -p "$SRC/$1"; git -C "$SRC/$1" init -q; git -C "$SRC/$1" remote add origin "$2"
    git -C "$SRC/$1" fetch -q --depth 1 origin "$3"; git -C "$SRC/$1" checkout -q FETCH_HEAD
  }
  fetch ffmpeg    https://github.com/FFmpeg/FFmpeg.git            5a1f107b4c78318f318897900acad1b6c6aa3f9d   # release/7.1
  fetch godot_cpp https://github.com/godotengine/godot-cpp.git    b0e3b1e4b78a606f48d162898afb5eeda533d2a9

  # 2. Build image: ubuntu:20.04 (glibc 2.31, gcc 9.4 cross). debian:buster (glibc 2.28) was tried first but its
  #    gcc 8.3 cannot compile godot-cpp (ambiguous Array(Variant) in typed_array.hpp) and has Python 3.7 only.
  #    The resulting .so is checked afterwards for the highest GLIBC_ symbol version it really needs.
  docker build -q -t gozen-focal - <<'DOCKER'
FROM ubuntu:20.04
RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu binutils-aarch64-linux-gnu gcc libc6-dev make pkg-config git \
    python3 python3-pip python3-setuptools python3-wheel ca-certificates \
 && pip3 install -q scons
DOCKER
  # 3. Run the real build inside it as the current user.
  docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$HERE:/work" -w /work gozen-focal ./build.sh --inner
  # 4. Install where the launcher expects it (and where build/package.sh picks it up).
  dest="$HERE/../../port/pathogenic/addons/gde_gozen/bin"
  mkdir -p "$dest"; cp "$HERE/out/libgozen.linux.template_release.arm64.so" "$dest/"
  echo "installed: $dest/libgozen.linux.template_release.arm64.so"
  exit
fi

# ---- inside the container ----
cd /work/gde_gozen
export PATH="$HOME/.local/bin:$PATH"
J=$(nproc)

# FFmpeg: decode-only, mp4/mov + H.264 + HEVC + AAC, static, no network/TLS/zlib/AOM/VPX.
# (upstream passes --disable-asm for arm64; NEON asm is kept here since it needs no nasm and speeds decoding up)
FFMPEG_FLAGS=(
  --prefix=/work/gde_gozen/ffmpeg/bin
  --enable-cross-compile --cross-prefix=aarch64-linux-gnu- --arch=aarch64 --target-os=linux
  --cc=aarch64-linux-gnu-gcc --pkg-config=false
  --disable-shared --enable-static --enable-pic --extra-cflags=-fPIC
  --disable-everything --disable-autodetect --disable-network
  --disable-programs --disable-doc --disable-debug
  --disable-avdevice --disable-avfilter --disable-postproc
  --disable-encoders --disable-muxers --disable-hwaccels
  --disable-zlib --disable-bzlib --disable-lzma --disable-iconv
  --enable-pthreads --enable-swscale --enable-swresample
  --enable-demuxer=mov
  --enable-decoder=h264 --enable-decoder=hevc --enable-decoder=aac
  --enable-parser=h264 --enable-parser=hevc --enable-parser=aac
  --enable-protocol=file
)
if [ ! -f ffmpeg/bin/lib/libavcodec.a ]; then   # delete ffmpeg/bin to force a rebuild
  cd ffmpeg
  [ -f ffbuild/config.mak ] && make distclean >/dev/null 2>&1 || true
  ./configure "${FFMPEG_FLAGS[@]}" --quiet
  make -j"$J" && make install
  cd ..
fi

# SConstruct (our copy, reset from git first): drop tls/ssl/crypto/vpx/aom/z from the linux link line.
git checkout -q b852674 -- SConstruct
python3 - <<'PY'
p = "SConstruct"; s = open(p).read()
n = s.count('    env.Append(LIBS=["tls", "ssl", "crypto", "vpx", "aom"])\n')
assert n == 3
s = s.replace('    env.Append(LIBS=["tls", "ssl", "crypto", "vpx", "aom"])\n', '', 1)
s = s.replace('    if arch != "arm64":\n        env.Append(LIBS=["z"])\n', '', 1)
# FFmpeg's aarch64 NEON asm is not PIC-clean for preemptible symbols: bind locally and keep FFmpeg symbols private.
s = s.replace('LINKFLAGS=["-static-libstdc++"]', 'LINKFLAGS=["-static-libstdc++", "-Wl,-Bsymbolic", "-Wl,--exclude-libs,ALL"]', 1)
open(p, "w").write(s)
PY

scons platform=linux arch=arm64 target=template_release jobs="$J" -j"$J"

mkdir -p /work/out
cp test_room/addons/gde_gozen/bin/libgozen.linux.template_release.arm64.so /work/out/
aarch64-linux-gnu-strip --strip-unneeded /work/out/libgozen.linux.template_release.arm64.so
