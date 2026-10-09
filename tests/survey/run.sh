#!/bin/bash
# Runs the drawn size survey mod once and leaves its result in <out>/texk.json.
# Usage: run.sh <out folder> <timeout s> [KEY=VALUE ...]
# Env: GODOT (godot471.x86_64 from PortMaster's godot_4.7.1 runtime), GAMEDIR (folder holding the
#      untouched Steam pathogenic.pck, so textures are at full size), PCK (default pathogenic.pck),
#      XSERVER (gamescope or xvfb), DISP (X display number for Xvfb, default 21), RES (default 1280x720; the
#      measured k does not depend on it, a 16:9 screen just shows the most world).
# KEY=VALUE: SV_MODE = level | parts | enemies | rooms | misc | ui | bodymap, SV_LEVEL (1 to 7),
#      SV_SEED (level seed), SV_PARASITE (0 to 7, for parts), SV_ZS (Camera Zoom option, default 1.25
#      like the port), SV_ROOMS (limit rooms, for a quick test). See tests/survey/mods-unpacked/PortMaster-Survey/mod_main.gd.
# The game runs in gamescope's headless backend on the GPU (XSERVER=xvfb: a private Xvfb with software
# rendering, much slower); neither opens a window on your desktop. The game is stopped
# with SIGKILL, as a normal exit of this game raises a crash dialog.
set -u
S="$(cd "$(dirname "$0")" && pwd)"
OUT="$(realpath -m "${1:?out folder}")"; TMO="${2:?timeout seconds}"; shift 2
GODOT="${GODOT:?set GODOT to godot471.x86_64}"; G="${GAMEDIR:?set GAMEDIR}"; PCK="${PCK:-pathogenic.pck}"
D="${DISP:-21}"; RES="${RES:-1280x720}"
MODS="$(mktemp -d)"; trap 'rm -rf "$MODS"' EXIT
(cd "$S" && zip -qr "$MODS/survey.zip" mods-unpacked)
[ -f "${PORT_MOD:-}" ] && cp "$PORT_MOD" "$MODS/"   # the port's own mod (PortMaster-Handheld.zip), for the same UI changes
rm -rf "$OUT"; mkdir -p "$OUT"
export SV_OUT="$OUT" SteamDeck=1
for kv in "$@"; do export "$kv"; done
ulimit -c 0
export XDG_DATA_HOME="$OUT/home"; mkdir -p "$XDG_DATA_HOME"
cd "$G"
W="${RES%x*}"; H="${RES#*x}"
GAME=("$GODOT" --main-pack "$PCK" --rendering-method gl_compatibility --rendering-driver opengl3_es
  --resolution "$RES" --position 0,0 --mods-path="$MODS")
if [ "${XSERVER:-gamescope}" = gamescope ]; then
  # gamescope's headless backend: the game renders on the GPU into a nested X server that has no
  # window anywhere (an order of magnitude faster than Xvfb's software rendering)
  # a private runtime folder: the game can only reach gamescope's own sockets, never the desktop's
  XR="$(mktemp -d)"; chmod 700 "$XR"
  setsid env -u WAYLAND_DISPLAY -u DISPLAY XDG_RUNTIME_DIR="$XR" gamescope --backend headless -W "$W" -H "$H" -w "$W" -h "$H" -- "${GAME[@]}" > "$OUT/game.log" 2>&1 & GPID=$!
else
  # Xvfb: an offscreen X server with software rendering, never a window on the desktop
  while [ -e "/tmp/.X${D}-lock" ]; do sleep 0.5; done
  export SDL_VIDEODRIVER=x11 XDG_RUNTIME_DIR=/tmp/xdg-offscreen; mkdir -p -m 700 /tmp/xdg-offscreen
  Xvfb ":$D" -screen 0 "${RES}x24" -nolisten tcp >/dev/null 2>&1 & XPID=$!
  for i in $(seq 40); do DISPLAY=":$D" xdpyinfo >/dev/null 2>&1 && break; sleep 0.5; done
  DISPLAY=":$D" xdpyinfo >/dev/null 2>&1 || { echo "offscreen X server :$D did not start"; kill $XPID; exit 1; }
  env -u WAYLAND_DISPLAY DISPLAY=":$D" setsid "${GAME[@]}" > "$OUT/game.log" 2>&1 & GPID=$!
fi
t=0
while [ $t -lt "$TMO" ] && [ ! -e "$OUT/done.txt" ] && kill -0 $GPID 2>/dev/null; do sleep 2; t=$((t + 2)); done
# SIGKILL the whole session (a normal exit of this game raises a crash dialog)
kill -9 -- -$GPID 2>/dev/null; wait $GPID 2>/dev/null; [ -n "${XR:-}" ] && rm -rf "$XR"; [ -n "${XPID:-}" ] && { kill $XPID 2>/dev/null; wait $XPID 2>/dev/null; }
grep -a "SV \|SCRIPT ERROR" "$OUT/game.log" | sed 's/^ERROR: //' > "$OUT/sv.log"
echo "$(basename "$OUT"): $t s, finished=$([ -e "$OUT/done.txt" ] && echo yes || echo no)"
