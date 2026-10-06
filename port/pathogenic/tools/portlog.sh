# Diagnostics for bug reports, sourced by the launcher (log.txt) and by tools/patchscript (the
# setup log). Every line starts with "PORT:" so it stands out from the game's own output.
port_log() { echo "PORT: [$(date +%H:%M:%S)] $*"; }

# RAM and swap in MB
port_mem() {
  port_log "memory ($1): $(awk '/^(MemTotal|MemAvailable|SwapTotal|SwapFree):/ { printf "%s %d MB  ", $1, $2 / 1024 }' /proc/meminfo)"
}

# Kernel messages about processes killed for lack of memory, or failed GPU allocations
port_oom_lines() {
  dmesg 2>/dev/null | grep -iE "out of memory|oom-kill|killed process|oom_reaper|panfrost.*(fail|err)|mali.*(fail|err)"
}

# Which files a bug report needs; the launcher sets PORT_REPORT_FILES
port_report() {
  [ -n "$PORT_REPORT_FILES" ] && port_log "to report a problem, send these files: $PORT_REPORT_FILES"
  return 0
}

# Device, system and memory, written once at the top of each log. $1 names the log.
port_header() {
  local gpu="unknown"
  [ -e /dev/mali0 ] && gpu="Mali (vendor driver)"
  [ -d /sys/module/panfrost ] && gpu="Mali (Panfrost)"
  port_log "$1, $(date '+%Y-%m-%d %H:%M:%S %Z'), script $(basename "$0") md5 $(md5sum "$0" 2>/dev/null | cut -c1-8)"
  port_log "system: ${CFW_NAME:-unknown} ${CFW_VERSION:-} on ${DEVICE_NAME:-unknown} (cpu ${DEVICE_CPU:-?}, $(uname -m), ${DEVICE_RAM:-?} GB RAM), kernel $(uname -r), gpu $gpu"
  port_log "screen ${DISPLAY_WIDTH:-?}x${DISPLAY_HEIGHT:-?}, user $(id -u), PortMaster $(cat "$controlfolder/version" 2>/dev/null || echo unknown) at ${controlfolder:-?}"
  port_log "port folder $GAMEDIR, free space $(df -Ph "$GAMEDIR" 2>/dev/null | awk 'NR == 2 { print $4 }')"
  [ -n "$SDL_GAMECONTROLLERCONFIG" ] &&
    port_log "controller: $(printf '%s\n' "$SDL_GAMECONTROLLERCONFIG" | head -n 1)"
  port_mem start
  port_oom_seen=$(port_oom_lines | wc -l)
}

# Size and date of the files a port depends on, or that they are missing
port_files() {
  local f
  for f in "$@"; do
    if [ -e "$f" ]; then
      port_log "file $f: $(ls -lnL "$f" | awk '{print $5}') bytes, modified $(date -r "$f" '+%Y-%m-%d %H:%M')"
    else
      port_log "file $f: missing"
    fi
  done
}

# A runtime squashfs is mounted when the file it should provide is there
port_mounted() {
  if [ -e "$2" ]; then port_log "runtime $1 mounted"; else port_log "ERROR: runtime $1 is not mounted ($2 missing)"; fi
}

# After the game: how long it ran, memory and new kernel memory messages. Only when the game
# ended with an error does the log also name the files to send. westonwrap logs the exit code:
# 0 is a normal quit; 143 (SIGTERM) and 137 (SIGKILL) are how firmwares close a game from the
# hotkey. A kill for lack of memory is also 137, but then the kernel logs it (caught above).
port_exit() {
  local code oom
  port_log "game ended after ${SECONDS}s since launch"
  port_mem exit
  oom="$(port_oom_lines | tail -n +$((port_oom_seen + 1)))"
  [ -n "$oom" ] && printf '%s\n' "$oom" | sed 's/^/PORT: kernel: /'
  code="$(grep -o 'exited with exit code [0-9]*' "$GAMEDIR/log.txt" 2>/dev/null | tail -n 1 | grep -o '[0-9]*$')"
  if [ -n "$oom" ] || { case "${code:-0}" in 0|137|143) false ;; *) true ;; esac; }; then
    port_log "the game ended with an error (exit code ${code:-unknown}${oom:+, out of memory})"
    port_report
  fi
  return 0
}
