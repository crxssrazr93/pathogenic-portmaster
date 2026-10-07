extends "res://scn/ui/start_menus/slime_shader.gd"
# The main menu background (used when live action cutscenes are skipped) simulates in a
# SubViewport that follows the screen shape, and its logo fills that viewport: on screens
# narrower than 16:9 the logo is cut at both sides. There the background is kept to a centred
# 16:9 band (the space above and below stays black, like the rest of the menu).
# On screens up to 720 pixels high the simulation runs at an eighth of the UI resolution instead
# of half (240x135 instead of 960x540) and steps every second frame. Each simulated pixel reads
# the previous state 9 times per step of a loop, plus a copy of the whole buffer: at a quarter
# resolution every frame it alone held the menu at 9.5 fps on an H700 (30 without it).
const SMALL_SCREEN_SHRINK := 8
var _small := false
var _frame := 0


func _ready() -> void:
	super()
	_small = get_window().size.y <= 720
	if _small:
		$SubViewportContainer.stretch_shrink = SMALL_SCREEN_SHRINK
	_letterbox()
	get_viewport().size_changed.connect(_letterbox)


func _process(delta: float) -> void:
	super(delta)
	if not _small:
		return
	_frame += 1
	var sim: SubViewport = $SubViewportContainer/SubViewport
	sim.render_target_update_mode = SubViewport.UPDATE_ONCE if _frame % 2 == 0 else SubViewport.UPDATE_DISABLED



func _letterbox() -> void:
	var screen := get_viewport_rect().size
	var band := minf(screen.y, screen.x * 9.0 / 16.0)
	offset_top = (screen.y - band) / 2.0
	offset_bottom = -offset_top
