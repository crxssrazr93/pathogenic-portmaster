# Porting notes: Pathogenic

A record of how this port was made, what was measured, and every approach that failed or was dropped, so the next Godot 4.7 port (or the next person) does not walk the same dead ends. Measurements are from one Anbernic RG35XX H (Knulli, H700, Mali G31, 1 GB RAM, 640x480) and a PC running the x86_64 build of PortMaster's `godot_4.7.1` runtime.

## 1. Survey

| Item | Finding |
|--|--|
| Store | Steam app 3808690, Aberrant Labs, published by Slug Disco. Native Linux x86_64 build (depot fetched with steamcmd). |
| Engine | Godot 4.7 stable, official export. PortMaster's `godot_4.7.1` runtime matches it. |
| Pack | `pathogenic.pck`, 1.44 GB, 12,248 files: 3,226 textures, 1,361 scenes, 848 scripts, 60 shaders, 4 mp4 videos |
| Renderer | No `rendering_method` in `project.godot`, so the export is Forward+ (Vulkan). Handhelds have no Vulkan. |
| Layout | 1920x1080, stretch mode canvas_items, aspect expand: on a 640x480 screen the UI is drawn at a third of its design size |
| Extensions | GodotSteam, GoZen (video, FFmpeg inside), LimboAI (enemy AI, essential), sentry-godot. Their `.gdextension` files list linux arm64 libraries, but the Steam build ships x86_64 only. |
| Mod support | The game contains Godot Mod Loader 7.0.1, and `--mods-path=<dir>` loads mod zips from any folder |

## 2. Getting it to start

* **Renderer.** `--rendering-method gl_compatibility --rendering-driver opengl3_es` runs the game on Mesa GLES on the PC: menus, intro video, the first level, movement and shooting. The only renderer warning is that the Compatibility renderer has no particle trails.
* **Extensions are not optional.** Without the libraries every script using their classes fails to compile and the game quits. LimboAI drives the enemies, and scripts call `SentrySDK` unconditionally even though Sentry is configured with `auto_init=false`, so all four must load.
* **Where Godot looks for them.** With `--main-pack`, Godot opens `res://addons/.../x.so` first as the relative path `addons/.../x.so` from the working directory (not through the pack), then as `<executable dir>/<file name>`. The port keeps the runtime on its squashfs, `cd`s to the port folder and places the arm64 libraries under `addons/`, at the paths the `.gdextension` files list. An early "mirror with symlinks" test failed only because the shell did not word split a loop variable, so the links pointed nowhere; the rule itself held.
* **Steam.** `steam.gd` checks `Engine.has_singleton("Steam")` and `SteamAPI_Init` fails without a client. The game carries on (one "Utils class not found" error, on device "no running instance of Steam"). No stub was needed.

### The arm64 libraries

| Library | Source |
|--|--|
| GodotSteam 4.19.1 and `libsteam_api.so` | Official GDExtension release, arm64 files extracted unchanged (`build/fetch_plugins.sh`) |
| LimboAI 1.8.0 | Official GDExtension release, arm64 file extracted unchanged (`build/fetch_plugins.sh`) |
| sentry-godot 1.6.0 | Built from source (`build/sentry/build.sh`) as the "noop" variant. The stock SConstruct selects the no-op SDK only for arm32 and rv64, so the script patches arm64 into that list. No crash reporting is wanted here. |
| GoZen (gde_gozen) b852674 | Built from source (`build/gozen/build.sh`) with FFmpeg 7.1 (release/7.1, 5a1f107b) |

Notes on the GoZen build:

* **Toolchain.** Ubuntu 20.04 with the aarch64 cross compiler (glibc 2.31 sysroot, so the library loads on old firmwares). Debian buster (glibc 2.28) was tried first and failed: its gcc 8.3 cannot compile godot-cpp (ambiguous `Array(Variant)` in `typed_array.hpp`) and it only has Python 3.7.
* **FFmpeg is decode only.** `--disable-everything` plus the MOV demuxer, H.264, HEVC and AAC decoders and parsers, the file protocol, swscale and swresample. No encoders, muxers, network, TLS, zlib, GPL or nonfree parts, so the LGPL applies (see `port/pathogenic/licenses/LICENSE.ffmpeg.txt`). Upstream passes `--disable-asm` for arm64; NEON assembly is kept because it needs no nasm and speeds decoding up.
* **Link line.** The upstream SConstruct links `tls ssl crypto vpx aom z` on Linux; the script removes them since FFmpeg is built without them.
* **Symbol binding.** FFmpeg's aarch64 NEON assembly is not PIC clean for preemptible symbols, so the library is linked with `-Wl,-Bsymbolic` and `-Wl,--exclude-libs,ALL`.

## 3. Screen size and input

* **Text.** The game's largest text tier raises small text to a floor of 28 design pixels, chosen for a 1280x800 Steam Deck. At 640x480 that is 9 screen pixels. The launcher sets `SteamDeck=1`, which makes a new install start on the largest tier (the game's own Steam Deck default; nothing else reads the variable). The mod's `text_scale_manager.gd` extension then makes the floor the design size that comes out at 12 screen pixels (36 at 640x480) and raises every UI text below it.
* **Boot splash.** Godot's "Keep" splash mode fits the height and cuts the sides off a 16:9 splash on 4:3 screens, so the launcher adds `boot_splash/stretch_mode=2` (Keep Width) to the game's own override file in `conf/` whenever it is missing.
* **Level start map.** `bodymap.gd` pans the map by the viewport height times a position keyed for 1080. On 4:3 (1920x1440) the map is pushed up, leaving black below. A script extension of `bodymap.gd` broke the level config preloads (it loads them before the game is ready), so the mod instead scales the animation's pan keys when the node is added.
* **Main menu.** The slime background simulates in a SubViewport shaped like the screen and its logo fills it, which cuts the logo at both sides on 4:3. The mod keeps it to a centred 16:9 band there, and on screens up to 720 high runs the feedback shader at a quarter of the UI resolution (it made the menu lag).
* **Camera.** The game's own Camera Zoom option is set once, on a new install, so the play area is as large as on an 800 wide screen: 1.25 at 640x480 (picked on the RG35XX H after trying 1.5 and 1.75), 1.11 at 720x720, unchanged from 800 wide up. Fewer objects are on screen too.
* **HUD.** On small screens the room minimap (top right) is drawn 1.75 times larger and more opaque, the body overview (top left) 1.4 times, and the DNA and health bars and the stamina wheel 1.5 times, each as a fraction of its design size on screen. The bars sit in a MarginContainer whose layout resets their scale, so it is set again after every sort. The minimap goes back to its own size while it is expanded to the full screen.
* **Cell selection.** The description box at the top is white text on a light panel: drawn 1.3 times larger, with a dark outline.
* **Buttons.** Knulli names buttons for games by position as SDL does (a is the bottom button, labelled B on these devices), the same for every port. The launcher leaves that as it is: Knulli has its own per game A/B swap, and swapping in the launcher as well flipped the buttons twice for players who use it, and the wrong way on devices whose bottom button is labelled A. Godot also numbers joypad buttons differently from SDL on pads that report extra keys, so the launcher renumbers the SDL mapping for Godot from the pad's key bitmap. gptokeyb only supplies the exit hotkey, since the game reads the pad itself.
* **Mapping on muOS.** Westonpack's `westonwrap.sh` sources PortMaster's `control.txt` again before it starts the game, and on muOS that exports the original `SDL_GAMECONTROLLERCONFIG` over the launcher's renumbered one. The launcher passes the mapping as a `VAR=value` argument to `westonwrap.sh` instead, as one line with the spaces in the pad's name replaced (`westonwrap.sh` evals its arguments; the GUID, not the name, is matched). The launcher also carries PortMaster's `# PORTMASTER: <zip>, <script>` line, which harbourmaster otherwise inserts into the script the first time it downloads a runtime, breaking a launcher that is running at that moment. Tested on an RG35XX H with muOS.

Pad actions in the game's input map, as Godot joypad buttons: A accept and interact, B cancel, X activate, Y select and second ability, R1 shoot and next tab, L1 dodge and previous tab, R2 secondary shot, L2 minimap, Select pause, Start editor, left stick move, right stick aim.

## 4. Memory

### 4.1 First attempts

| Attempt | Result |
|--|--|
| PC, 640x480, unmodified | Peak RSS 1.30 GB on the boot shader warm up screen, 1.0 to 1.25 GB in the first level (including Mesa's own memory) |
| Device, boot shader warm up | Out of memory killed at 6 % (727 MB RSS plus 92 MB swap) |
| Same, warm up caching removed by the mod | Killed again (anon-rss 150 MB, file-rss 524 MB: the Mali GPU buffers count as RSS). So textures, not scripts, are the limit. |

### 4.2 The boot warm up

The boot screen loads every shader and particle scene and keeps them referenced for the whole session so shaders are compiled before play. That alone runs out of memory on 1 GB. The mod's `shader_loader.gd` extension drops the caching but keeps the script pinning, which prevents a crash during threaded level loads. The pinning costs about 50 MB (241 against 166 MB at the menu on the PC), so it is not the main cost. With it the PC boot peak went from 1.30 GB to 814 MB.

The warm up is CPU bound: 9 s on an idle PC with the mod, but about 95 s on the H700 before the mods are ready, which is why boot takes about two minutes on 1 GB devices.

### 4.3 Textures

Census of the pack: 3,226 `.ctex` files. 974 are BPTC (BC7) only, which a Mali GPU cannot use, so Godot unpacks each to RGBA8 (2.9 GB for all at full size) and the import has no ETC2 fallback. The other 2,252 are lossless WebP, which also becomes RGBA8 on the GPU. 873 have a side of 512 or more, and the largest is 9000x3500, above the Mali limit of 8192. Of that, 716 Mpx are BPTC and 386 Mpx are WebP.

First fix: halve every texture with a side of 512 or more. First level measured on the PC at 485 MB of textures, and the device was killed while loading the first level (anon-rss 143 MB, file-rss 528 MB).

Better insight: the camera `base_zoom` is 0.3 to 0.36 in the level configs, so level art is drawn at about a third of its 1080p size, and at 640x480 that is a ninth. The setup (`port/pathogenic/setup/port_setup.gd`) therefore stores every texture at the size it is drawn at on this screen:

* UI art (`gfx/ui`, mutations, evolutions, addons) at `min(W/1920, H/1080)`, capped at 1;
* everything else at half that, which leaves room for the camera zooming in;
* sides below 32 px are kept, nothing goes below 16, nothing above 4096 is stored;
* each texture becomes a plain raw `.ctex` in `cache/textures/` (no mipmaps, the game's 2D filter never samples them), its `.import` remap in the pack is repointed there, and the header keeps the original size so sprite regions, atlases and frame grids, all in original pixels, stay correct.

The launcher passes the two scales and stores them in the setup stamp with the pck's size and time. A different screen converts again from the originals, which stay in the pack under `.godot/imported`. The setup is a plain `MainLoop` script (no autoloads, which would load most of the game) and writes `cache/.setup_ok` after its last step, since a `MainLoop` script cannot report a success exit code.

Result at 640x480 on the PC: cache 959 MB down to 147 MB, setup 14 s, first level textures 485 MB down to 147 MB, no visible loss. On the device: setup about 4 minutes, the level loads without being killed (textures 148 MB, RSS about 700 MB plus 39 MB swap). Larger screens store larger textures, hence "up to about 1 GB" of cache.

### 4.4 Measured drawn sizes

The blanket scales of 4.3 are right for most art but too small for some: the wall pattern the room shader tiles over every wall, the tiled backgrounds, explosion sheets, the player's body in the body editor. `setup/drawn_sizes.tsv` lists such textures with the largest size they are drawn at, measured in the game: "res://path<TAB>k", k being screen pixels per texture pixel at the 1920x1080 design size. A listed texture is stored at `min(1, max(default, min(k * ui scale, 1.5 * default)))`.

* **The survey.** The test only mod `tests/survey/` walks the game (every room of 7 levels with 4 seeds, every enemy, room, effect and UI scene, every body part of each parasite, the body editor and the level start map) and records, per texture, the largest k it is drawn at. `tests/survey/regenerate.sh` runs it all (about 1.5 hours on 8 cores) and `build/make_drawn_table.py` merges the results into the table (804 textures). Close-up views (the body editor, the level start map) count only for the player's art and the UI, since they draw level art far larger than play does. Some passes crash the game at a given item, so the runner resumes after it (`SV_FROM`, `tests/survey/sweep.sh`); four scenes that crash it on their own are skipped (`enemy_defaults`, `enemy_hp_bar`, `freeze_effect`, `ally_defaults`).
* **The cap.** The game loads a level's whole art set up front, so every listed texture of the level costs memory, not only the ones on screen. Texture memory at 640x480 on the PC (Godot's monitor, the first 5 rooms):

| Stored | Level 1 | Level 4 | Whole cache |
|--|--|--|--|
| Blanket scales only | 89 MB | 101 MB | 140 MB |
| Table, at most 1.5 times larger per side (shipped) | 104 MB | 115 MB | 178 MB |
| Table, at most 2 times | 123 MB | 133 MB | 215 MB |
| Table, no cap | 161 MB | 168 MB | 292 MB |

The uncapped table adds about 70 MB in a level, on a device whose first level already used about 700 MB RSS plus swap. The 1.5 cap costs about 15 MB. On the RG35XX H with the shipped table: setup 358 s (3226 textures, 178 MB), first level at 30 fps, 632 MB RSS plus 70 MB swap (peak 681 MB) after several minutes, against about 700 MB plus 39 MB before the table.
* **Setup.** The table is part of the setup stamp (by its `cksum`), and each cached texture's `.src` holds the original's MD5 and its stored size, so a port update that changes the table converts only the textures whose size changed.

### 4.5 Graphics defaults

The mod's `globals.gd` extension sets handheld defaults only for keys the player has not set: no lighting (section 5), environment and post processing low, physics accuracy off, no foreground parallax, a 30 fps cap and no HDR 2D (its 16-bit float buffers are slow on handheld GPUs, and there is no glow that needs it). Live action cutscenes are skipped by default because the 1080p HEVC videos are too heavy to decode on a handheld CPU. The player can turn them back on in the options.

Measured on the RG35XX H with cutscenes turned on: the main menu plays its live action background (720p H.264) at about 25 fps, but the game's RSS rises from 473 MB to 634 MB (available memory 344 MB to about 148 MB). The memory is freed when the menu is left. The 1080p HEVC drop cutscene opened and closed without a crash, but showed its first frame and then black for about 18 s. The default stays off; the slime background the game draws instead is its own fallback.

Log noise that is harmless: 182 RGBFloat and 48 RGBAFloat textures converted to half floats (Mali), 44 "Too many instances using shader instance variables" (`secret_text.gd`, a 1024 buffer on this GPU), and one "Cannot get class 'DisabledBreadcrumb'" from the no-op Sentry.

## 5. Frame rate

Measured on the RG35XX H with the test only probe mod (`tests/probe/`), which logs the frame time, script and physics time, draw calls and active physics bodies every 2 seconds. Once a level is up it runs phases of 8 seconds that hide part of the scene, stop a script or turn off a SubViewport, alternating with unchanged phases. Fights were measured with the game's own `--stress-test` harness (a seeded run with hordes of 12 to 35 enemies kept alive), which gives the same fight every time. The screen's vsync cannot be turned off on this device, so frame rates step between 30, 20 and 15 fps; a part shows up in a phase only when it moves the frame across one of those steps.

| Change | Where | Before | After |
|--|--|--|--|
| Main menu slime simulation at an eighth of the UI resolution, stepped every second frame (`slime_shader.gd`) | Main menu | 9.5 fps | 23 to 25 fps |
| SubViewports rendered at the size they are shown (below) | Body editor | 5 fps | 25 to 30 fps |
| No lighting by default | Quiet room | 17 fps | 26 fps |
| Minimaps redrawn every second frame | Quiet room | 26 fps | 30 fps (the cap) |
| At most 2 physics steps a frame | Stress test hordes | 5 fps | 15 fps |
| All of the above | First fight of a run | 9 to 15 fps (player report) | about 24 fps |

* **Lighting.** The light around the player, the one light left on the game's "player only" setting, cost about 20 ms a frame on the Compatibility renderer. The rooms look nearly the same without it. Installs that already had "player only" saved are moved to "none" once; the player can turn it back on.
* **Physics steps.** The game allows 6 physics steps a frame. In a big fight one step takes about as long as a tick, and the game settled at 6 steps every frame: 5 fps, still in real time. With at most 2 the same fight runs at 15 fps, in real time down to 15 fps and in slow motion only below that. Physics runs at 30 ticks a second instead of 60.
* **Minimaps.** The room map and the body overview each draw the whole level again through their own SubViewport (about 4 ms a frame). They are redrawn every second frame, every frame while the map is expanded, and not at all while hidden.
* **SubViewports.** Offscreen views (minimaps, the body editor, the DNA panels, the menu's CRT screen) render at their 1920x1080 or 1920x1440 design size and are then shown at a third of that. Each one shown through a SubViewportContainer now renders at the size it is shown: the container stretches it and divides its resolution by the screen's whole factor (3 at 640x480, 2 at 720x720), and `size_2d_override` keeps the content laid out at the design size, input included. Viewports with their own 3D camera keep their size, since `Camera3D.unproject_position` uses the override. They also drop HDR 2D.
* **Light motes.** The ambient light particles (`particle_light*.tscn`) are the largest group of emitters, about 135 in a level and each its own GPU pass: two of every three are removed.

Fight candidates, measured on the RG35XX H with the test only mod `tests/fight_ab/` during the game's own `--stress-test --gpu-ablate` horde (25 enemies held alive; the game's GPU timers read 0 on the device's GLES driver, so the mod measures the mean frame time in interleaved 2.5 s windows). Baseline windows 62.0 to 66.3 ms. Enemy cell (toon) material off: 62.1 and 62.7 ms. Hair hidden: 65.0 and 65.8 ms. Eager physics sleep (0.1 s, linear 10, angular 1): 62.9 and 62.8 ms. Each is at most about 2 ms of a 64 ms frame, inside the baseline's spread and far from the 50 ms that the next vsync step (20 fps) needs, so none is shipped. The horde's frame is 24 ms of render CPU (the game's own report) and the rest game logic and physics.

What did not move the frame rate in a quiet room: stopping `hair.gd`, `blood_stream.gd`, `connection.gd`, the vitals graphs or the parallax sprites, hiding the HUD, hiding all 182 particle emitters, 20 physics ticks a second, and the background mask viewport (about 2 ms). Switching off the player's CanvasGroup saves about 2 ms, but the game tints it for every hit flash and dodge, and `player.gd` declares a global class, which a script extension cannot replace, so it stays.

## 6. Results

| Item | Result |
|--|--|
| All four extensions on the device | Load (GodotSteam reports no running Steam, the game carries on) |
| Setup on the RG35XX H | About 4 minutes, then shown only when the pck or screen size changes |
| Boot on the RG35XX H | About 95 s to 2 minutes before the mods are ready |
| Gameplay on the RG35XX H | Quiet rooms at the 30 fps cap, the first fights at about 24 fps, the stress test hordes at 15 fps (section 5) |

## 7. What failed or was dropped, and why

1. **Libraries in `addons/` folders only.** Godot does not find them by `res://` path through the pack; the working directory relative path or the executable directory are the two places that work (section 2).
2. **Original boot warm up on the device.** Runs out of memory, see 4.1 and 4.2.
3. **Halving only the big textures.** Still 485 MB in the first level on the PC and not enough on the device. The scale has to follow the screen (4.3).
4. **A script extension of `bodymap.gd`.** It loads the level config preloads before the game is ready and broke them. The node is patched at runtime instead.
5. **Re-encoding the cutscene videos on the device** (bundled ffmpeg, 640x360 H.264, override through the mod). It would have worked but was not wanted: cutscenes stay off by default, and players can enable them.
6. **Lossless WebP for the cache.** About 4 times smaller files but about 3 times slower setup. The code keeps a `STORE_WEBP` switch, off.
7. **Using the stock Sentry library.** There is no arm64 build, and the no-op SDK is selected only for arm32 and rv64 until the script patches arm64 in.
8. **Debian buster as the build image.** Its gcc 8.3 and Python 3.7 cannot build godot-cpp (section 2).
9. **Counting the sampler's RSS as the whole story.** On Mali GPUs buffers are shared memory and appear as file-rss, so the device is judged by RSS plus swap and the video memory monitor together.
10. **A script extension of `editor.gd`.** The script declares a global class (`Editor`), and the extension broke other scripts that use the class ("hides a global script class"). The mod corrects the editor from its own `_physics_process` instead.
11. **Driving the player with injected stick events on the device.** Buttons injected into the controller's evdev node work, but the driver keeps reporting the real stick, so the probe holds input actions instead (`/tmp/probe_cmd`).
12. **Test harness pitfalls**: always pass `--resolution`, use `bwrap --die-with-parent` and `ulimit -c 0`, and give every harness its own display. Never run the game on a rootful Xwayland (`-decorate`): that is a window on the desktop. `tests/localtest.sh` uses Xvfb (software rendering) and stops when it is not up; the survey runs in gamescope's headless backend (on the GPU, about 10 times faster) with a private runtime folder, so the game cannot reach the desktop's display.
13. **The game's GPU timers for fight A/B tests** (`--gpu-ablate`, `viewport_get_measured_render_time_gpu`). They read 0 ms on Mali GLES; frame time windows are used instead.
14. **A script extension of `stress_test.gd`.** It fails to compile at mod load (its preloaded level configs cannot load that early), so `tests/fight_ab/` is a plain mod node.
15. **The drawn size table without a cap.** About 70 MB more textures in a level at 640x480 (4.4).

### Texture cache after game updates

Converted textures are named after Godot's imported file, which is named after the texture's path, so a game update that changes a texture kept the name and the old pixels were reused. Each cached texture now has `<name>.src` with the MD5 the pack's directory records for its original; a different MD5 converts it again. The launcher also runs the setup when `cache/textures/` is missing even though the stamp matches. Tested on the PC (a rerun reuses all 3226, five changed originals convert those five, a fresh copy of the same pck reuses all) and on the RG35XX H (`cache/textures/` removed: setup ran, 3226 converted in 295 s, title screen). Installs from older releases convert every texture once more on their next setup run, since their cache has no `.src` files.

## 8. Still to do

* A device with 2 GB of RAM or more has not been tested.
* Boot still takes about two minutes on the H700.
* Late levels and bosses have not been measured.
* Some text is still small in places.
