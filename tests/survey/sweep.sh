#!/bin/bash
# Runs an enemies or misc survey to the end although some scenes crash the game: after a crash it
# starts again one past the scene that crashed (SV_FROM), each part in <out>_<n>/, and lists the
# scenes it skipped in <out>.skipped.
# Usage: sweep.sh <out> <timeout s per part> SV_MODE=enemies|misc [KEY=VALUE ...]   Env as for run.sh.
set -u
S="$(cd "$(dirname "$0")" && pwd)"; OUT="$(realpath -m "$1")"; TMO="$2"; shift 2
from=0; part=0; : > "$OUT.skipped"
while [ $part -lt 20 ]; do
  part=$((part + 1))
  "$S/run.sh" "${OUT}_$part" "$TMO" SV_FROM=$from "$@"
  [ -e "${OUT}_$part/done.txt" ] && { echo "$(basename "$OUT"): complete in $part parts"; exit 0; }
  last="$(grep -a -o 'SV item [0-9]* [^ ]*' "${OUT}_$part/game.log" | tail -n 1)"
  [ -n "$last" ] || { echo "$(basename "$OUT"): part $part ended before its first scene"; exit 1; }
  n="$(echo "$last" | awk '{print $3}')"
  echo "$last" | awk '{print $4}' >> "$OUT.skipped"
  from=$((n + 1))
done
echo "$(basename "$OUT"): gave up after $part parts"; exit 1
