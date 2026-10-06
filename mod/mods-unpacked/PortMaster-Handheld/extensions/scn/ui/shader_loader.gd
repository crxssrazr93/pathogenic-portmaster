extends "res://scn/ui/shader_loader.gd"
# The boot screen loads every shader and particle scene and keeps them referenced for the whole
# session, so their shaders are compiled before play. On a 1 GB handheld that alone runs out of
# memory, so only the script pinning (which prevents a crash during level loads) is kept; shaders
# compile when first used instead.


func start() -> void:
	set_process(true)
	_script_paths_to_pin = _collect_pin_paths()
	_pin_total = _script_paths_to_pin.size()
