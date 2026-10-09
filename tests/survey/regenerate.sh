#!/bin/bash
# Regenerates port/pathogenic/setup/drawn_sizes.tsv: runs the survey over the whole game (about 1.5
# hours on 8 cores, 2 runs at a time), then build/make_drawn_table.py merges the results.
# Usage: regenerate.sh <work folder>      Env as for run.sh (GODOT, GAMEDIR).
# Passes: level (7 levels x 4 seeds: every room and hall, bosses), enemies (every enemy scene),
# rooms (every room scene of the game), misc (effects, projectiles, props, pickups), parts (every
# bodypart on the player and in the body editor, and every body, for each parasite), bodymap
# (the level start map), ui (every UI scene).
set -u
S="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$S/../.." && pwd)"
W="$(realpath -m "${1:?work folder}")"; mkdir -p "$W"
jobs=()
jobs+=("parts0 2400 SV_MODE=parts SV_PARASITE=0")
jobs+=("enemies1 3000 SV_MODE=enemies SV_LEVEL=1")
jobs+=("rooms1 3600 SV_MODE=rooms SV_LEVEL=1")
jobs+=("misc1 3000 SV_MODE=misc SV_LEVEL=1")
jobs+=("ui 900 SV_MODE=ui")
for L in 1 2 3 4 5 6 7; do
  for sd in A B C D; do jobs+=("S$L$sd 900 SV_MODE=level SV_LEVEL=$L SV_SEED=SURVEY$sd"); done
  jobs+=("bodymap$L 300 SV_MODE=bodymap SV_LEVEL=$L")
done
for p in 1 2 3 4 5 6 7; do jobs+=("parts$p 900 SV_MODE=parts SV_PARASITE=$p"); done
n=0
for j in "${jobs[@]}"; do
  n=$((n + 1)); set -- $j
  echo "DISP=$((20 + n)) $S/run.sh $W/$1 $2 ${*:3}"
done | xargs -P "${PARALLEL:-2}" -I{} bash -c '{}'
python3 "$R/build/make_drawn_table.py" --out "$R/port/pathogenic/setup/drawn_sizes.tsv" "$W"/*/texk.json
