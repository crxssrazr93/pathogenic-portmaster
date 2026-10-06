extends "res://scn/text_scale_manager.gd"
# The largest text size raises small text to a floor of 28 design pixels, chosen for a 1280x800
# Steam Deck. The UI is designed for 1920x1080 and scaled to the screen, so on a 640x480
# handheld 28 comes out at 9 screen pixels (14 px chosen on a 3.5 inch 640x480 screen). Here the floor of the largest size is the design size
# that comes out at PORT_MIN_PX screen pixels (never below the game's own floor), and every UI
# text below it is raised to it (the game scales text designed below 20 in proportion, which left
# hints and button labels at 7 to 10 screen pixels).

const PORT_MIN_PX := 14.0


func scaled_size(base: int, world := false) -> int:
	if size_index != FACTORS.size() - 1:
		return super(base, world)
	var screen := Vector2(DisplayServer.window_get_size())
	var ui_scale := minf(screen.x / 1920.0, screen.y / 1080.0)
	var floor_px := maxi(FLOORS[size_index], ceili(PORT_MIN_PX / ui_scale))
	if world:
		if base * WORLD_ZOOM >= floor_px:
			return base
		return ceili(floor_px / WORLD_ZOOM)
	return maxi(base, floor_px)
