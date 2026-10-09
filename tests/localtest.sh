#!/bin/bash
# Local device-like test of Pathogenic on the PortMaster x86_64 Godot 4.7.1 runtime (Compatibility
# renderer on OpenGL ES, as on the device):
# an offscreen X server (Xvfb, never a window on the desktop) at a handheld resolution, scripted virtual gamepad, RSS sampling.
# Usage: localtest.sh <WxH> "<vpad script>" [tag]
# Env: GODOT (path to godot471.x86_64 from PortMaster's godot_4.7.1 runtime),
#      GAMEDIR (folder holding pathogenic.pck, e.g. the Steam Linux install or a prepared copy),
#      DISP (X display number, default 5), FRESH=1 (fresh user data), EXTRA (more Godot arguments, e.g.
#      --mods-path=<folder with the port mod zip>; tests/probe is a test only mod that logs memory monitors).
set -u
ulimit -c 0  # no core dumps, so a forced stop never reaches the desktop crash reporter
S="$(cd "$(dirname "$0")" && pwd)"; G="${GAMEDIR:?set GAMEDIR to the folder holding pathogenic.pck}"
RES="${1:-640x480}"; SCRIPT="$2"; TAG="${3:-run}"
GODOT="${GODOT:?set GODOT to godot471.x86_64 from the godot_4.7.1 runtime}"; PCK="${PCK:-pathogenic.pck}"
OUT="$S/out/$TAG"; mkdir -p "$OUT"; rm -f "$OUT"/*.png "$OUT"/*.mp4 "$OUT"/diag.log "$OUT"/rss.log
# a previous server on this display may still be shutting down; then wait until the new one answers
while [ -e "/tmp/.X${DISP:-5}-lock" ]; do sleep 0.5; done
unset WAYLAND_DISPLAY; export SDL_VIDEODRIVER=x11 XDG_RUNTIME_DIR=/tmp/xdg-offscreen; mkdir -p -m 700 /tmp/xdg-offscreen; Xvfb :${DISP:-5} -screen 0 "${RES}x24" -nolisten tcp >/dev/null 2>&1 & XPID=$!
for i in $(seq 40); do DISPLAY=:${DISP:-5} xdpyinfo >/dev/null 2>&1 && break; sleep 0.5; done
DISPLAY=:${DISP:-5} xdpyinfo >/dev/null 2>&1 || { echo "offscreen X server :${DISP:-5} did not start"; kill $XPID 2>/dev/null; exit 1; }
before=$(ls /dev/input/)
REC_CMD="ffmpeg -y -loglevel error -f x11grab -framerate 30 -video_size $RES -i :${DISP:-5} -c:v libx264 -preset ultrafast $OUT/{name}.mp4" \
SHOT_CMD="DISPLAY=:${DISP:-5} import -window root $OUT/{name}.png 2>/dev/null" \
  python3 "$S/vpad.py" "wait 2; $SCRIPT" & VPID=$!
sleep 2
new=$(comm -13 <(echo "$before" | sort) <(ls /dev/input/ | sort))
binds=(); for n in $new; do binds+=(--dev-bind "/dev/input/$n" "/dev/input/$n"); done
cd "$G"
# isolated user data (like PortMaster's XDG_DATA_HOME=$GAMEDIR/conf); FRESH=1 starts from nothing
export XDG_DATA_HOME="${XDG_HOME:-$S/out/home-$TAG}"; [ "${FRESH:-0}" = 1 ] && rm -rf "$XDG_DATA_HOME"; mkdir -p "$XDG_DATA_HOME"
env -u WAYLAND_DISPLAY DISPLAY=:${DISP:-5} bwrap --die-with-parent --dev-bind / / --tmpfs /dev/input "${binds[@]}" \
  "$GODOT" --main-pack "$PCK" --rendering-method gl_compatibility --rendering-driver opengl3_es --resolution "$RES" --position 0,0 ${EXTRA:-} \
  > "$OUT/game.log" 2>&1 & GPID=$!
( while kill -0 $GPID 2>/dev/null; do
    P=$(pgrep -P $GPID -f "main-pack" || true)
    [ -n "$P" ] && awk -v t="$SECONDS" '/VmRSS/{r=$2}/VmSwap/{s=$2}/VmHWM/{h=$2}END{print t"s rss+swap="int((r+s)/1024)"MB rss="int(r/1024)"MB hwm="int(h/1024)"MB"}' /proc/$P/status 2>/dev/null
    sleep 3; done > "$OUT/rss.log" ) &
wait $VPID
P=$(pgrep -P $GPID -f "main-pack")
PEAK=$(awk '/VmHWM/{print int($2/1024)}' /proc/$P/status 2>/dev/null)
ALIVE=$(kill -0 $GPID 2>/dev/null && echo yes || echo no)
# stop Godot itself first and wait for it, only then the X server (Godot dies on a lost X connection)
[ -n "$P" ] && kill $P 2>/dev/null; for i in $(seq 20); do kill -0 $GPID 2>/dev/null || break; sleep 0.5; done
kill -9 $GPID $P 2>/dev/null; wait $GPID 2>/dev/null; kill $XPID 2>/dev/null; wait $XPID 2>/dev/null
echo "alive=$ALIVE peakRSS=${PEAK}MB files: $(ls "$OUT" | grep -E 'png|mp4' | tr '\n' ' ')"
