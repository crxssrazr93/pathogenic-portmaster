extends "res://scn/globals.gd"
# Handheld defaults, used until the player changes them in the options. Set here, before the main
# menu and the levels read them.
# * Live action cutscenes skipped: the 1080p videos are too heavy to decode on a handheld CPU.
# * The cheapest graphics options (no lighting, low environment and post processing quality, low
#   physics accuracy, no foreground parallax layer) and a 30 fps cap. Lighting matters most: on
#   the Compatibility renderer the light around the player alone cost about 20 ms a frame on an
#   H700 (17 fps in a quiet room, 26 fps without it), and the rooms look nearly the same without
#   it. Installs from before this change had "player only" saved; they are moved to "none" once
#   (HANDHELD_DEFAULTS_VERSION), after that the player's own choice is kept.
# * No HDR 2D: its 16-bit float buffers are slow on handheld GPUs, and with post processing low
#   there is no glow that would need it.
# * The camera zoomed in on small screens (the game's own Camera Zoom option, 1.25 at 640x480,
#   1.11 at 720x720, see mod_main.gd handheld_zoom): the player and the play area are larger,
#   and fewer objects are on screen.
# * Physics at 30 ticks a second instead of 60, and at most 2 physics steps a frame instead of 6.
#   The game interpolates physics for drawing. In a big fight a step takes about as long as a tick
#   on an H700, and with 6 steps allowed the game settled at 6 steps every frame: 5 fps, in real
#   time. With 2 the same fight runs at 15 fps (the game's own --stress-test hordes: 5 to 15 fps),
#   still in real time down to 15 fps, and in slow motion only below that.

const HANDHELD_SETTINGS := {
	"skip_live_action_cutscenes": true,
	"foreground_parallax_visible": false,
}
const HANDHELD_LOCAL_SETTINGS := {
	"lighting_mode": LightingMode.NONE,
	"environment_quality": EnvironmentQuality.LOW,
	"postprocessing_quality": PostprocessingQuality.LOW,
	"physics_accuracy": false,
}
const HANDHELD_DEFAULTS_VERSION := 2
const HANDHELD_MAX_FPS := 30
const HANDHELD_PHYSICS_TICKS := 30
const HANDHELD_PHYSICS_STEPS := 2
const PortMod := preload("res://mods-unpacked/PortMaster-Handheld/mod_main.gd")


func _ready() -> void:
	for key in HANDHELD_SETTINGS:
		if SaveManager.read_setting(key, null) == null:
			SaveManager.save_setting(key, HANDHELD_SETTINGS[key])
			set(key, HANDHELD_SETTINGS[key])
	for key in HANDHELD_LOCAL_SETTINGS:
		if SaveManager.read_local_setting(key, null) == null:
			SaveManager.save_local_setting(key, HANDHELD_LOCAL_SETTINGS[key])
			set(key, HANDHELD_LOCAL_SETTINGS[key])
	if SaveManager.read_local_setting("handheld_defaults_version", 1) < 2:
		if SaveManager.read_local_setting("lighting_mode", null) == LightingMode.PLAYER_ONLY:
			SaveManager.save_local_setting("lighting_mode", LightingMode.NONE)
			lighting_mode = LightingMode.NONE
		SaveManager.save_local_setting("handheld_defaults_version", HANDHELD_DEFAULTS_VERSION)
	var override := ConfigFile.new()
	override.load(ProjectSettings.get_setting("application/config/project_settings_override"))
	if not override.has_section_key("application", "run/max_fps"):
		SaveManager.save_project_setting("application", "run/max_fps", HANDHELD_MAX_FPS)
		Engine.max_fps = HANDHELD_MAX_FPS
	if SaveManager.read_setting("camera_zoom_scale", null) == null:
		var zoom: float = PortMod.handheld_zoom(get_tree())
		SaveManager.save_setting("camera_zoom_scale", zoom)
		camera_zoom_scale = zoom
	Engine.physics_ticks_per_second = HANDHELD_PHYSICS_TICKS
	Engine.max_physics_steps_per_frame = HANDHELD_PHYSICS_STEPS
	get_tree().root.use_hdr_2d = false
	super()
