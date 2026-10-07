# Pathogenic for PortMaster

A [PortMaster](https://portmaster.games/) port of [Pathogenic](https://store.steampowered.com/app/3808690/Pathogenic/) (Aberrant Labs, published by Slug Disco, 2026), a cellular roguelike twin stick shooter, for Linux handhelds.

The port runs the game's own `pathogenic.pck` on PortMaster's stock Godot 4.7.1 runtime. No game files are included: you supply the pck from your Steam copy, and the first start adapts it on your device so it fits in memory.

| | |
|--|--|
| Status | Boots, menus, controls and levels work on an Anbernic RG35XX H (Knulli, H700, Mali G31, 1 GB RAM), where it is slow: boot about 2 minutes, levels lag |
| Target | aarch64 PortMaster devices (Knulli, muOS, ROCKNIX, ArkOS and others) with 2 GB RAM or more |
| Runtimes | `godot_4.7.1`, Westonpack (`weston_pkg_0.2`) |
| Tested game version | Steam Linux build, pck 1.44 GB (Godot 4.7 stable) |
| First start | about 4 minutes on the RG35XX H, shown on PortMaster's patcher screen |

## For players

1. Buy the game on Steam.
2. In Steam, open Pathogenic's Manage menu and choose Browse local files. Copy `pathogenic.pck` into `ports/pathogenic/gamedata/` on your device.
3. Start **Pathogenic** from the Ports menu. The first start prepares the game on PortMaster's patcher screen (press A to begin, and again to start the game when it is done). It takes a few minutes and needs up to about 1 GB of free space. Later starts are quick.

Controls and notes are in [port/README.md](port/README.md), the file that ships with the port.

## How it works

```
Pathogenic.sh (PortMaster launcher)
  ├ first start only: PortMaster patcher screen → tools/patchscript
  │     └ godot --headless --script res://setup/port_setup.gd   (patches the pck in place)
  └ westonwrap.sh headless noop kiosk crusty_x11egl                      (Weston + Xwayland, GLES)
      └ godot471 (stock PortMaster godot_4.7.1 runtime) --main-pack pathogenic.pck --mods-path=mods
          ├ addons/       the four GDExtensions the game needs, built for arm64
          ├ mods/         PortMaster-Handheld.zip, a Godot Mod Loader mod (the game ships the loader)
          └ cache/        textures stored at the screen's scale
```

The game is a Forward+ (Vulkan) export, which handhelds cannot run, so the launcher starts it on the Compatibility renderer (OpenGL ES). The rest:

* **GDExtensions.** The game needs GodotSteam, LimboAI (enemy AI), GoZen (video) and sentry-godot, and ships only x86_64 builds. The port carries arm64 builds: official releases of GodotSteam 4.19.1 and LimboAI 1.8.0, Sentry 1.6.0 built as the no-op variant, and GoZen (commit b852674) built with FFmpeg 7.1 for decoding only. Godot opens them relative to the working directory, so they sit under `addons/` in the port folder.
* **First start setup** (`port/pathogenic/setup/port_setup.gd`) rewrites all 3226 textures into a cache at the size they are drawn at on your screen (the UI at the screen's scale of its 1920x1080 design, the levels at half that) and repoints the pack's `.import` entries to them. The pack is patched in place, so nothing from the game leaves your device.
* **Port mod** (`mod/`, zipped into `mods/` by `build/package.sh`): text sized for small screens, graphics defaults set to the cheapest options, live action cutscenes off by default, no boot shader caching, and a fix for the level start map on 4:3 screens.
* **Controller mapping** (in the launcher): Godot numbers joypad buttons differently from SDL on pads that also report keys such as volume or Esc, so the launcher renumbers PortMaster's SDL mapping for Godot. Buttons work by position (A is the bottom button); on Knulli the A/B layout is set per game in the ports list.

The full story, with measurements and every approach that failed, is in [docs/PORTING.md](docs/PORTING.md).

## Repository layout

| Path | Contents |
|--|--|
| `port/` | Exactly what ships to `ports/` on the device (the arm64 libraries and the mod zip are added by the build scripts) |
| `mod/` | Source of the Godot Mod Loader mod |
| `build/` | `fetch_plugins.sh`, the Sentry and GoZen builds, `package.sh` |
| `tests/` | `localtest.sh`, a virtual gamepad (`vpad.py`) and a test only memory probe mod |
| `docs/` | Porting notes |

## Building

Requirements: Docker (for Sentry and GoZen), curl, unzip, zip.

```
build/fetch_plugins.sh       # official GodotSteam 4.19.1 and LimboAI 1.8.0 arm64 libraries
build/sentry/build.sh        # sentry-godot 1.6.0, noop variant, arm64
build/gozen/build.sh         # GoZen b852674 with FFmpeg 7.1 decode only, arm64 (takes a while)
build/package.sh             # pathogenic.zip, ready to unzip into ports/
```

`package.sh` needs `port/screenshot.png` and `port/cover.png`, and stops with a message if one is missing. It builds the mod with `cd mod && zip -r -X <out> mods-unpacked`.

## Testing on a PC

`tests/localtest.sh` runs the game on the x86_64 build of PortMaster's `godot_4.7.1` runtime, on a private Xwayland server at a handheld resolution, driven by a virtual gamepad. Requirements: Xwayland, xdpyinfo, bubblewrap, ImageMagick, ffmpeg, Python 3 with `python-evdev`, write access to `/dev/uinput`.

```
export GODOT=/path/to/godot_4.7.1/godot471.x86_64 GAMEDIR=/path/to/folder/with/pathogenic.pck
tests/localtest.sh 640x480 "wait 30; shot menu; press A; wait 20; shot level" menu
```

Each run prints whether the game was still alive and its peak memory, and writes screenshots, the game log and a memory trace to `tests/out/<tag>/`. `tests/vpad.py` documents the step syntax. `tests/probe/` is a test only mod that logs Godot's memory monitors (zip its `mods-unpacked` folder and pass `EXTRA="--mods-path=<folder>"`).

## Known limitations

* Online features (Steam) are unavailable.
* On 1 GB devices (H700) boot takes about two minutes and levels lag. 2 GB or more is recommended.
* Live action cutscenes are off by default because the 1080p HEVC videos are too heavy.
* Particle trails are not supported by the Compatibility renderer.
* The title logo is cut at the sides on 4:3 screens.
* ROCKNIX needs Panfrost (as for every Westonpack port).

## Credits and licenses

* Pathogenic by Aberrant Labs, published by Slug Disco. Not affiliated; buy the game to play it.
* [Godot Engine](https://godotengine.org/) (MIT), [GodotSteam](https://godotsteam.com/) (MIT), [LimboAI](https://github.com/limbonaut/limboai) (MIT), [sentry-godot](https://github.com/getsentry/sentry-godot) (MIT), [GoZen](https://codeberg.org/gozen/gde_gozen) (LGPL 2.1) with [FFmpeg](https://ffmpeg.org/) 7.1 (LGPL 2.1, built without GPL or nonfree parts and statically linked; the build in `build/gozen/build.sh` can be rerun to rebuild and relink), and Valve's Steamworks redistributable `libsteam_api.so`.
* `setup/pck_patcher.gd` follows the pack patching approach of Knifethrower's [PM Porting Tools](https://github.com/Knifethrower/PM-Porting-Tools) (0BSD).
* [Westonpack](https://github.com/binarycounter/Westonpack) by binarycounter, the PortMaster team.
* Everything written for this port (launcher, setup, mod, scripts, docs) is MIT licensed, see [LICENSE](LICENSE). The port package carries all notices in `port/pathogenic/licenses/`.
