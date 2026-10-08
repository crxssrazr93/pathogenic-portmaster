#!/bin/bash
# PORTMASTER: pathogenic.zip, Pathogenic.sh

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/$directory/ports/pathogenic"
CONFDIR="$GAMEDIR/conf"
godot_runtime="godot_4.7.1"
godot_executable="godot471.$DEVICE_ARCH"
weston_runtime="weston_pkg_0.2"

# Godot opens the game's GDExtension libraries (res://addons/...) relative to the working
# directory, so the arm64 builds sit under addons/ in the port folder.
cd "$GAMEDIR"
# the previous run's log is kept as log.prev.txt
mv -f "$GAMEDIR/log.txt" "$GAMEDIR/log.prev.txt" 2>/dev/null
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1
# Device, system and memory details for bug reports (tools/portlog.sh)
# The files a bug report needs; named in log.txt and on screen only when something fails
export PORT_REPORT_FILES="ports/pathogenic/log.txt and setup_log.txt"
source "$GAMEDIR/tools/portlog.sh"
port_header "Pathogenic launcher"
mkdir -p "$CONFDIR"

# Godot's "Keep" boot splash mode fits the height on any landscape screen, which cuts the sides
# off the 16:9 splash on 4:3 screens; "Keep Width" shows all of it. The game keeps its own
# settings in this file too, so the key is added back whenever it is missing.
override="$CONFDIR/godot/app_userdata/Pathogenic/godot_settings_override.cfg"
mkdir -p "$(dirname "$override")"
grep -q "^boot_splash/stretch_mode" "$override" 2>/dev/null ||
  printf '\n[application]\n\nboot_splash/stretch_mode=2\n' >> "$override"
# Godot only flushes print() output at exit in release builds, so the FPS lines (--print-fps)
# would be lost when the firmware closes the game; flush every line instead.
grep -q "^run/flush_stdout_on_print" "$override" 2>/dev/null ||
  printf '\n[application]\n\nrun/flush_stdout_on_print=true\n' >> "$override"

if [ ! -f "$GAMEDIR/gamedata/pathogenic.pck" ]; then
  pm_message "Missing pathogenic.pck. Copy it from your Steam copy of Pathogenic into ports/pathogenic/gamedata/ (see README.md)."
  sleep 8
  pm_finish
  exit 1
fi

for runtime in "$godot_runtime" "$weston_runtime"; do
  if [ ! -f "$controlfolder/libs/${runtime}.squashfs" ]; then
    if [ ! -f "$controlfolder/harbourmaster" ]; then
      pm_message "This port requires the latest PortMaster to run, please go to https://portmaster.games/ for more info."
      sleep 5
      exit 1
    fi
    $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${runtime}.squashfs"
  fi
done

godot_dir=/tmp/godot
weston_dir=/tmp/weston
$ESUDO mkdir -p "$godot_dir" "$weston_dir"
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
  $ESUDO umount "$godot_dir" 2>/dev/null
  $ESUDO umount "$weston_dir" 2>/dev/null
fi
$ESUDO mount "$controlfolder/libs/${godot_runtime}.squashfs" "$godot_dir"
$ESUDO mount "$controlfolder/libs/${weston_runtime}.squashfs" "$weston_dir"
port_mounted "$godot_runtime" "$godot_dir/$godot_executable"
port_mounted "$weston_runtime" "$weston_dir/westonwrap.sh"

# Size and modification time of each file, as "stat -c '%s %Y'" prints them (muOS has no stat)
file_stamp() {
  if command -v stat >/dev/null; then stat -c '%s %Y' "$@" 2>/dev/null; return 0; fi
  local f
  for f in "$@"; do [ -e "$f" ] && echo "$(ls -lnL "$f" | awk '{print $5}') $(date -r "$f" +%s)"; done
  return 0
}
# First run (and again after the game updates its pck, or on another screen size): adapt the
# user's pck to this device's GPU, memory and screen. setup/port_setup.gd explains the step; it
# skips work already done, so an interrupted run just continues next time.
# Textures are stored at the size they are drawn at: the UI at the screen's scale of its 1920x1080
# design, the levels (camera zoomed out to about a third) at half that.
ui_scale="$(awk -v w="$DISPLAY_WIDTH" -v h="$DISPLAY_HEIGHT" 'BEGIN { s = w / 1920; if (h / 1080 < s) s = h / 1080; if (s > 1) s = 1; printf "%.4f", s }')"
world_scale="$(awk -v s="$ui_scale" 'BEGIN { printf "%.4f", s / 2 }')"
setup_stamp() { echo "$(file_stamp gamedata/pathogenic.pck) $ui_scale $world_scale"; }
# done: the stamp matches and the converted textures are still there
setup_done() { [ -d cache/textures ] && [ "$(cat cache/.setup_stamp 2>/dev/null)" = "$(setup_stamp)" ]; }
port_files gamedata/pathogenic.pck
if setup_done; then
  port_log "setup: up to date"
else
  port_log "setup: needed (first run, game update, other screen or textures missing; stamp '$(cat cache/.setup_stamp 2>/dev/null)', now '$(setup_stamp)', textures $([ -d cache/textures ] && echo present || echo missing))"
fi
if ! setup_done; then
  export GAMEDIR godot_dir godot_executable ui_scale world_scale controlfolder
  chmod +x "$GAMEDIR/tools/patchscript"
  export PATCHER_FILE="$GAMEDIR/tools/patchscript"
  export PATCHER_GAME="Pathogenic"
  export PATCHER_TIME="3 to 10 minutes"
  if [ -f "$controlfolder/utils/patcher.txt" ]; then
    port_log "running the setup (tools/patchscript), its log is setup_log.txt"
    source "$controlfolder/utils/patcher.txt"
  else
    pm_message "This port requires the latest version of PortMaster."
    sleep 5
    $ESUDO umount "$godot_dir" "$weston_dir" 2>/dev/null
    pm_finish
    exit 1
  fi
  # tools/patchscript writes the stamp only on success, from the pck as the setup left it
  if ! setup_done; then
    port_log "setup failed"
    port_report
    pm_message "Preparing the game failed, see ports/pathogenic/setup_log.txt. To report it, send $PORT_REPORT_FILES."
    sleep 8
    $ESUDO umount "$godot_dir" "$weston_dir" 2>/dev/null
    pm_finish
    exit 1
  fi
fi

# The input device a mapping line is for. By its SDL GUID first (bus, vendor, product and version,
# little endian; current SDL keeps a CRC of the name in bytes 2 and 3, so those are skipped): the
# mapping's name need not be the device's (muOS maps its "muOS-Keys" pad as "Deeplay-keys"). Only
# joysticks count, since key devices such as gpio-keys can report the same ids. Then by name, then
# the only joystick with buttons.
mapping_pad() {
  local guid="${1%%,*}" name="${1#*,}" ev id pads=()
  name="${name%%,*}"
  le16() { local v=$((16#$(cat "$1" 2>/dev/null || echo 0))); printf '%02x%02x' $((v & 255)) $((v >> 8 & 255)); }
  for ev in /sys/class/input/event*/device; do
    [ -d "$ev/id" ] && ls -d "$ev"/js* >/dev/null 2>&1 || continue
    id="$(le16 "$ev/id/bustype")0000$(le16 "$ev/id/vendor")0000$(le16 "$ev/id/product")0000$(le16 "$ev/id/version")0000"
    [ "${id:0:4}${id:8}" = "${guid:0:4}${guid:8}" ] && { echo "$ev"; return; }
  done
  for ev in /sys/class/input/event*/device; do
    [ "$(cat "$ev/name" 2>/dev/null)" = "$name" ] && { echo "$ev"; return; }
  done
  for ev in /sys/class/input/event*/device; do
    ls -d "$ev"/js* >/dev/null 2>&1 || continue
    [ -n "$(cat "$ev/capabilities/key" 2>/dev/null)" ] && pads+=("$ev")
  done
  [ ${#pads[@]} -eq 1 ] && echo "${pads[0]}"
}
# Godot numbers joypad buttons from BTN_JOYSTICK (0x120) upwards, then BTN_MISC to BTN_JOYSTICK,
# and skips lower key codes. SDL numbers every key code in ascending order, so on pads that also
# report keys like volume or Esc the SDL mapping's bN indices point at the wrong buttons in Godot.
# Renumber them using the pad's key bitmap.
godot_joy_mapping() {
  local mapping="$1" name="${1#*,}" dev="" ev wbits=64 n i b w code
  name="${name%%,*}"
  dev="$(mapping_pad "$mapping")"
  [ -n "$dev" ] || { echo "$mapping"; return; }
  case "$(uname -m)" in aarch64|x86_64) ;; *) wbits=32 ;; esac
  local words=($(cat "$dev/capabilities/key")) codes=()
  n=${#words[@]}
  for ((i = 0; i < n; i++)); do
    w=$((16#${words[n-1-i]}))
    for ((b = 0; b < wbits; b++)); do
      (( (w >> b) & 1 )) && codes+=($((i * wbits + b)))
    done
  done
  local -A godot_idx=()
  local g=0 sdl=0 out="" f
  for code in "${codes[@]}"; do (( code >= 0x120 )) && godot_idx[$code]=$((g++)); done
  for code in "${codes[@]}"; do (( code >= 0x100 && code < 0x120 )) && godot_idx[$code]=$((g++)); done
  local -A sdl_to_godot=()
  for code in "${codes[@]}"; do
    [ -n "${godot_idx[$code]}" ] && sdl_to_godot[$sdl]=${godot_idx[$code]}
    sdl=$((sdl + 1))
  done
  IFS=, read -ra fields <<< "$mapping"
  for f in "${fields[@]}"; do
    if [[ "$f" =~ ^([^:]+):b([0-9]+)$ ]]; then
      [ -n "${sdl_to_godot[${BASH_REMATCH[2]}]}" ] || continue
      f="${BASH_REMATCH[1]}:b${sdl_to_godot[${BASH_REMATCH[2]}]}"
    fi
    out+="$f,"
  done
  echo "$out"
}

# The game reads the pads itself (Godot joypad input), each pad as its own player. The built in pad
# gets PortMaster's mapping for the device, renumbered for Godot's button order; other pads use
# Godot's own controller database. The mapping goes to the game as a westonwrap VAR=value argument:
# westonwrap sources PortMaster's control.txt again, which on some firmwares (muOS) exports the
# original mapping over anything exported here. westonwrap evals its arguments, so the mapping is
# one line and the spaces in its name (only the GUID is matched) become dots.
godot_mapping=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  godot_mapping="$(godot_joy_mapping "$line")"
  break
done <<< "$SDL_GAMECONTROLLERCONFIG"
godot_mapping="$(printf '%s' "$godot_mapping" | tr ' ' '.')"

if [ "$CFW_NAME" = "muOS" ] && [ -n "$GPTOKEYB2" ]; then
  $GPTOKEYB2 "$godot_executable" -c "$GAMEDIR/pathogenic.gptk" &
else
  $GPTOKEYB "$godot_executable" -c "$GAMEDIR/pathogenic.gptk" &
fi
pm_platform_helper "$godot_dir/$godot_executable"
port_log "controller mapping for the game: ${godot_mapping:-none}"

port_log "starting the game, texture scales ui $ui_scale world $world_scale"
# The game is built for Vulkan (Forward+); handhelds run it on the Compatibility renderer.
# SteamDeck=1 makes a new install start on the game's largest text size, which the port mod in
# mods/ sizes for the screen; the mod also skips the live action cutscenes by default.
# westonwrap replaces XDG_RUNTIME_DIR; pass the real one on so ALSA can reach PipeWire for sound.
REAL_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
$ESUDO env $weston_dir/westonwrap.sh headless noop kiosk crusty_x11egl \
  LD_PRELOAD= ${godot_mapping:+SDL_GAMECONTROLLERCONFIG="$godot_mapping"} XDG_DATA_HOME="$CONFDIR" XDG_RUNTIME_DIR="$REAL_XDG_RUNTIME_DIR" SteamDeck=1 \
  "$godot_dir/$godot_executable" --resolution "${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}" -f \
  --rendering-method gl_compatibility --rendering-driver opengl3_es --audio-driver ALSA --print-fps \
  --main-pack "$GAMEDIR/gamedata/pathogenic.pck" --mods-path="$GAMEDIR/mods"

port_exit
$ESUDO $weston_dir/westonwrap.sh cleanup
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
  $ESUDO umount "$godot_dir"
  $ESUDO umount "$weston_dir"
fi
pm_finish
