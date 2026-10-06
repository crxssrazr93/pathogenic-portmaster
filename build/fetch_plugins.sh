#!/bin/bash
# Downloads the official GodotSteam 4.19.1 and LimboAI 1.8.0 GDExtension releases and extracts
# their arm64 libraries to the paths Pathogenic.sh expects under port/pathogenic/addons/.
# (Sentry and GoZen have no arm64 release: build them with build/sentry/build.sh and build/gozen/build.sh.)
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
A="$R/port/pathogenic/addons"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

GODOTSTEAM_URL="https://codeberg.org/godotsteam/godotsteam/releases/download/v4.19.1-gde/godotsteam-4.19.1-gdextension-plugin-4.4.zip"
LIMBOAI_URL="https://github.com/limbonaut/limboai/releases/download/v1.8.0/limboai%2Bv1.8.0.gdextension-4.6.zip"

curl -fL --retry 3 -o "$work/gs.zip" "$GODOTSTEAM_URL"
curl -fL --retry 3 -o "$work/limbo.zip" "$LIMBOAI_URL"

mkdir -p "$A/godotsteam/linuxarm64" "$A/limboai/bin"
unzip -j -o -q "$work/gs.zip" \
  addons/godotsteam/linuxarm64/libgodotsteam.linux.template_release.arm64.so \
  addons/godotsteam/linuxarm64/libsteam_api.so -d "$A/godotsteam/linuxarm64"
unzip -j -o -q "$work/limbo.zip" addons/limboai/bin/liblimboai.linux.template_release.arm64.so -d "$A/limboai/bin"
find "$A/godotsteam" "$A/limboai" -type f -exec ls -la {} +
