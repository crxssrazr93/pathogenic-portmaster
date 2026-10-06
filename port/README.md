## Installation

Buy Pathogenic on [Steam](https://store.steampowered.com/app/3808690/Pathogenic/) (the Linux build). In Steam choose Manage, then Browse local files, and copy `pathogenic.pck` into `ports/pathogenic/gamedata/`.

The first start prepares the game for your device from your own pck. It takes a few minutes and needs up to about 1 GB of free space (about 150 MB at 640x480, more on bigger screens). Press A to begin, and A again when it finishes. It runs again by itself if the pck or the screen size changes.

## Controls

Buttons are named as the game's prompts show them. They work by position, as SDL lays them out: A is the bottom button (labelled B on Anbernic devices). On Knulli you can swap them per game: long press X on the game in the ports list and change its A/B layout setting.

| Button | Action |
|--|--|
| Left stick | Move |
| Right stick | Aim |
| R1 | Shoot |
| L1 | Dodge |
| R2 / X / Y | Secondary shot / activate / second ability |
| L2 | Minimap |
| A / B | Confirm / back |
| Select / Start | Pause / editor |
| Select + Start | Quit |

## Notes

* Needs a device with 2 GB of RAM or more for smooth play. On 1 GB H700 devices it runs, but boot takes about two minutes and levels lag.
* Live action cutscenes are off by default (they can be enabled in the options, but are heavy).
* Textures are stored at the screen's scale on the first run, and graphics default to the cheapest options.
* No game files are included. All changes are made on your device.

## Reporting problems

Please send `ports/pathogenic/log.txt` and `ports/pathogenic/setup_log.txt`. `log.txt` is rewritten on every start and the run before it is kept as `log.prev.txt` (the setup log likewise), so send both if the game was started again after the problem. Lines starting with `PORT:` list the device, firmware, screen, memory and swap, the state of the setup, and at the end how long the game ran and whether the system ran out of memory.

## Thanks

Aberrant Labs and Slug Disco for the game, the Godot Engine, GodotSteam, LimboAI, Sentry and GoZen developers, Knifethrower for the PM Porting Tools, and the PortMaster team.
