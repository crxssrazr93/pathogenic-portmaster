extends "res://scn/globals.gd"
# Handheld defaults, used until the player changes them in the options. Set here, before the main
# menu and the levels read them.
# * Live action cutscenes skipped: the 1080p videos are too heavy to decode on a handheld CPU.
# * The cheapest graphics options (lighting on the player only, low environment and post
#   processing quality, low physics accuracy, no foreground parallax layer) and a 30 fps cap.
# * No HDR 2D: its 16-bit float buffers are slow on handheld GPUs, and with post processing low
#   there is no glow that would need it.

const HANDHELD_SETTINGS := {
	"skip_live_action_cutscenes": true,
	"foreground_parallax_visible": false,
}
const HANDHELD_LOCAL_SETTINGS := {
	"lighting_mode": LightingMode.PLAYER_ONLY,
	"environment_quality": EnvironmentQuality.LOW,
	"postprocessing_quality": PostprocessingQuality.LOW,
	"physics_accuracy": false,
}
const HANDHELD_MAX_FPS := 30


func _ready() -> void:
	for key in HANDHELD_SETTINGS:
		if SaveManager.read_setting(key, null) == null:
			SaveManager.save_setting(key, HANDHELD_SETTINGS[key])
			set(key, HANDHELD_SETTINGS[key])
	for key in HANDHELD_LOCAL_SETTINGS:
		if SaveManager.read_local_setting(key, null) == null:
			SaveManager.save_local_setting(key, HANDHELD_LOCAL_SETTINGS[key])
			set(key, HANDHELD_LOCAL_SETTINGS[key])
	var override := ConfigFile.new()
	override.load(ProjectSettings.get_setting("application/config/project_settings_override"))
	if not override.has_section_key("application", "run/max_fps"):
		SaveManager.save_project_setting("application", "run/max_fps", HANDHELD_MAX_FPS)
		Engine.max_fps = HANDHELD_MAX_FPS
	get_tree().root.use_hdr_2d = false
	super()
