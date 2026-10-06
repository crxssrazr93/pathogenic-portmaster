#!/bin/bash
# Builds the port mod from mod/ and zips port/ into pathogenic.zip, laid out the way PortMaster's
# tools/build_release.py builds it (port.json, gameinfo.xml, screenshot.png and cover.png moved
# into the port folder, README.md renamed to pathogenic.md).
set -e
R="$(cd "$(dirname "$0")/.." && pwd)"
src="$R/port"
A="$src/pathogenic/addons"
missing=0
for f in godotsteam/linuxarm64/libgodotsteam.linux.template_release.arm64.so godotsteam/linuxarm64/libsteam_api.so \
         limboai/bin/liblimboai.linux.template_release.arm64.so \
         sentry/bin/linux/arm64/libsentry.linux.release.arm64.so gde_gozen/bin/libgozen.linux.template_release.arm64.so; do
  [ -f "$A/$f" ] || { echo "missing addons/$f"; missing=1; }
done
[ $missing = 0 ] || { echo "run build/fetch_plugins.sh, build/sentry/build.sh and build/gozen/build.sh first"; exit 1; }
for f in screenshot.png cover.png; do
  [ -f "$src/$f" ] || { echo "missing port/$f (every port ships screenshot.png and cover.png)"; exit 1; }
done
# The port mod: Godot Mod Loader loads zips from mods/
mkdir -p "$src/pathogenic/mods"
rm -f "$src/pathogenic/mods/PortMaster-Handheld.zip"
(cd "$R/mod" && zip -r -q -X "$src/pathogenic/mods/PortMaster-Handheld.zip" mods-unpacked)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp "$src/Pathogenic.sh" "$stage/"
cp -r "$src/pathogenic" "$stage/"
rm -rf "$stage"/pathogenic/gamedata/*.pck "$stage/pathogenic/cache" "$stage/pathogenic/conf" \
  "$stage/pathogenic/log.txt" "$stage/pathogenic/setup_log.txt" \
  "$stage/pathogenic/log.prev.txt" "$stage/pathogenic/setup_log.prev.txt"
cp "$src/port.json" "$src/gameinfo.xml" "$src/screenshot.png" "$src/cover.png" "$stage/pathogenic/"
cp "$src/README.md" "$stage/pathogenic/pathogenic.md"
rm -f "$R/pathogenic.zip"
(cd "$stage" && zip -9 -r -q -X "$R/pathogenic.zip" .)
ls -la "$R/pathogenic.zip"
