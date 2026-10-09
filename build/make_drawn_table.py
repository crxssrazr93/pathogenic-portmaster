#!/usr/bin/env python3
"""Builds port/pathogenic/setup/drawn_sizes.tsv from drawn size surveys.

Usage: make_drawn_table.py [--out FILE] [--min-area PX] [--screens 640x480,720x720] survey.json [survey.json ...]

Surveys of the body editor and the level start map count only for the player's art and the UI
(their close-up views draw the level art far larger than play does).

Each input is a texk.json written by the survey mod (tests/survey/): for every texture drawn
while it ran, the largest size it was drawn at, as screen pixels per texture pixel at the
1920x1080 design size ("k"), and the largest on-screen area it covered. The table keeps, per
texture, the maximum k over all inputs.

Only textures drawn larger than the setup's default scale already stores them at are listed
(k above 0.5 for level art, which is stored at half the UI scale, and above 1.0 for the UI art
directories), since a smaller k changes nothing: the setup stores a listed texture at
min(1, max(default, min(k * ui_scale, GAIN_MAX * default))). The script also prints what the table costs in
stored texture memory on the given screens.
"""
import argparse
import fnmatch
import os
import json
import math
import sys

UI_DIRS = ("res://gfx/ui/", "res://gfx/player/mutations/", "res://gfx/player/evolutions/", "res://addons/")
KEEP_BELOW = 32
MAX_SIDE = 4096
GAIN_MAX = 1.5  # DRAWN_GAIN_MAX in port_setup.gd


def default_k(path):
    """k at which the default scale (ui scale for UI art, half of it for the rest) is exact."""
    return 1.0 if path.startswith(UI_DIRS) else 0.5


def stored_px(w, h, scale):
    """Pixels stored for a texture, as port_setup.gd works them out."""
    longest = max(w, h)
    if longest < KEEP_BELOW:
        scale = 1.0
    scale = min(max(scale, KEEP_BELOW / 2.0 / longest), MAX_SIDE / longest)
    scale = min(scale, 1.0)
    return max(1, math.ceil(w * scale)) * max(1, math.ceil(h * scale))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("surveys", nargs="+")
    ap.add_argument("--out", default="port/pathogenic/setup/drawn_sizes.tsv")
    ap.add_argument("--min-area", type=float, default=16.0, help="ignore textures never drawn over this many screen pixels")
    ap.add_argument("--screens", default="640x480,720x720")
    ap.add_argument("--closeup", default="parts*,bodymap*", help="survey folders of close-up views (player art and UI only)")
    ap.add_argument("--coverage", action="store_true", help="also print what the surveys visited")
    args = ap.parse_args()

    tex = {}
    levels = {}  # level -> {"pool": set of room resources, "seen": set, "bosses": set, "rooms": n, "halls": n}
    other = {"enemy scenes": set(), "room scenes": set(), "misc scenes": set(), "ui scenes": set(), "bodyparts": set(), "bodies": set(), "bodymaps": set()}
    for p in args.surveys:
        data = json.load(open(p))
        for c in data.get("cover", []):
            w = c.get("where", "")
            if "pool" in c:
                lv = levels.setdefault(c["level"], {"pool": set(), "seen": set(), "bosses": set(), "rooms": 0, "base_zoom": c["base_zoom"]})
                lv["pool"].update(r for r, _ in c["pool"])
            elif "scene" in c:
                lv = levels.setdefault(int(w.split()[0][1:]), {"pool": set(), "seen": set(), "bosses": set(), "rooms": 0, "base_zoom": 0})
                scene = c["scene"] or w.split()[1]  # some boss rooms carry no scene path
                lv["seen"].add(scene)
                lv["rooms"] += 1
                if w.endswith("BOSS"):
                    lv["bosses"].add(scene.split("/")[-1])
            elif "enemy_scene" in c:
                other["enemy scenes"].add(c["enemy_scene"])
            elif "room_scene" in c:
                other["room scenes"].add(c["room_scene"])
            elif "misc_scene" in c:
                other["misc scenes"].add(c["misc_scene"])
            elif w.startswith("ui "):
                other["ui scenes"].add(w)
            elif "bodymap_seen" in c:
                if c["bodymap_seen"]:
                    other["bodymaps"].add(w)
            elif "parts" in c:
                other["bodyparts"].update(c["parts"])
            elif "body" in c:
                other["bodies"].add(c["body"])
        # The body editor and the level start map show the player and the map zoomed far in; level art
        # behind them is drawn 4 to 5 times larger than in play. Those surveys only count for the
        # player's own art and the UI.
        # (recognised by the survey's folder name, as tests/survey/regenerate.sh names them)
        closeup = any(fnmatch.fnmatch(os.path.basename(os.path.dirname(os.path.abspath(p))), g)
                      for g in args.closeup.split(","))
        for path, t in data["tex"].items():
            if closeup and not path.startswith(("res://gfx/player/",) + UI_DIRS):
                continue
            cur = tex.setdefault(path, {"w": t["w"], "h": t["h"], "k": 0.0, "area": 0.0})
            cur["k"] = max(cur["k"], t["k"])
            cur["area"] = max(cur["area"], t["area"])

    if args.coverage:
        for lv in sorted(levels):
            d = levels[lv]
            print(f"level {lv}: {d['rooms']} room visits over all seeds, {len(d['seen'])} of {len(d['pool'])} pool rooms, bosses seen: {', '.join(sorted(d['bosses'])) or 'none'}")
        for k, v in other.items():
            print(f"{k}: {len(v)}")

    rows = []
    for path, t in sorted(tex.items()):
        if t["area"] < args.min_area or t["k"] <= default_k(path):
            continue
        rows.append((path, math.ceil(t["k"] * 100) / 100, t["w"], t["h"]))

    with open(args.out, "w") as f:
        f.write("# Drawn sizes of textures, measured in the game (docs/PORTING.md, build/make_drawn_table.py).\n")
        f.write("# res://path, TAB, k: screen pixels per texture pixel at the 1920x1080 design size.\n")
        for path, k, _, _ in rows:
            f.write(f"{path}\t{k:.2f}\n")

    print(f"{len(tex)} textures measured, {len(rows)} listed in {args.out}")
    for scr in args.screens.split(","):
        w, h = (int(v) for v in scr.split("x"))
        ui = min(1.0, w / 1920, h / 1080)
        base = new = 0
        for path, k, tw, th in rows:
            d = ui if path.startswith(UI_DIRS) else ui / 2
            base += stored_px(tw, th, d)
            new += stored_px(tw, th, min(1.0, max(d, min(k * ui, GAIN_MAX * d))))
        print(f"{scr}: listed textures {base * 4 / 2**20:.1f} MB by default, {new * 4 / 2**20:.1f} MB with the table (+{(new - base) * 4 / 2**20:.1f} MB, RGBA8 worst case)")


if __name__ == "__main__":
    sys.exit(main())
