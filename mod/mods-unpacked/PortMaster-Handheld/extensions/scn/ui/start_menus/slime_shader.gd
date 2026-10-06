extends "res://scn/ui/start_menus/slime_shader.gd"
# The main menu background (used when live action cutscenes are skipped) simulates in a
# SubViewport that follows the screen shape, and its logo fills that viewport: on screens
# narrower than 16:9 the logo is cut at both sides. There the background is kept to a centred
# 16:9 band (the space above and below stays black, like the rest of the menu).
# On screens up to 720 pixels high the simulation runs at a quarter of the UI resolution instead
# of half (480x270): it is a full screen feedback shader every frame and made the menu lag.


func _ready() -> void:
	super()
	if get_window().size.y <= 720:
		$SubViewportContainer.stretch_shrink = 4
	_letterbox()
	get_viewport().size_changed.connect(_letterbox)



func _letterbox() -> void:
	var screen := get_viewport_rect().size
	var band := minf(screen.y, screen.x * 9.0 / 16.0)
	offset_top = (screen.y - band) / 2.0
	offset_bottom = -offset_top
