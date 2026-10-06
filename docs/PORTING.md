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
* **Buttons.** Knulli names buttons for games by position as SDL does (a is the bottom button, labelled B on these devices), the same for every port. The launcher leaves that as it is: Knulli has its own per game A/B swap, and swapping in the launcher as well flipped the buttons twice for players who use it, and the wrong way on devices whose bottom button is labelled A. Godot also numbers joypad buttons differently from SDL on pads that report extra keys, so the launcher renumbers the SDL mapping for Godot from the pad's key bitmap. gptokeyb only supplies the exit hotkey, since the game reads the pad itself.

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

### 4.4 Graphics defaults

The mod's `globals.gd` extension sets handheld defaults only for keys the player has not set: lighting on the player only, environment and post processing low, physics accuracy off, no foreground parallax, a 30 fps cap and no HDR 2D (its 16-bit float buffers are slow on handheld GPUs, and there is no glow that needs it). Live action cutscenes are skipped by default because the 1080p HEVC videos are too heavy to decode on a handheld CPU. The player can turn them back on in the options.

Log noise that is harmless: 182 RGBFloat and 48 RGBAFloat textures converted to half floats (Mali), 44 "Too many instances using shader instance variables" (`secret_text.gd`, a 1024 buffer on this GPU), and one "Cannot get class 'DisabledBreadcrumb'" from the no-op Sentry.

## 5. Results

| Item | Result |
|--|--|
| All four extensions on the device | Load (GodotSteam reports no running Steam, the game carries on) |
| Setup on the RG35XX H | About 4 minutes, then shown only when the pck or screen size changes |
| Boot on the RG35XX H | About 95 s to 2 minutes before the mods are ready |
| Gameplay on the RG35XX H | Runs, but levels lag. 2 GB of RAM or more is recommended. |

## 6. What failed or was dropped, and why

1. **Libraries in `addons/` folders only.** Godot does not find them by `res://` path through the pack; the working directory relative path or the executable directory are the two places that work (section 2).
2. **Original boot warm up on the device.** Runs out of memory, see 4.1 and 4.2.
3. **Halving only the big textures.** Still 485 MB in the first level on the PC and not enough on the device. The scale has to follow the screen (4.3).
4. **A script extension of `bodymap.gd`.** It loads the level config preloads before the game is ready and broke them. The node is patched at runtime instead.
5. **Re-encoding the cutscene videos on the device** (bundled ffmpeg, 640x360 H.264, override through the mod). It would have worked but was not wanted: cutscenes stay off by default, and players can enable them.
6. **Lossless WebP for the cache.** About 4 times smaller files but about 3 times slower setup. The code keeps a `STORE_WEBP` switch, off.
7. **Using the stock Sentry library.** There is no arm64 build, and the no-op SDK is selected only for arm32 and rv64 until the script patches arm64 in.
8. **Debian buster as the build image.** Its gcc 8.3 and Python 3.7 cannot build godot-cpp (section 2).
9. **Counting the sampler's RSS as the whole story.** On Mali GPUs buffers are shared memory and appear as file-rss, so the device is judged by RSS plus swap and the video memory monitor together.
10. **Test harness pitfalls**: always pass `--resolution`, stop Godot before Xwayland, use `bwrap --die-with-parent` and `ulimit -c 0`, and give every harness its own display.

## 7. Still to do

* A device with 2 GB of RAM or more has not been tested.
* Performance on the H700: levels lag. A frame time breakdown was not done.
* Some text is still small in places.
