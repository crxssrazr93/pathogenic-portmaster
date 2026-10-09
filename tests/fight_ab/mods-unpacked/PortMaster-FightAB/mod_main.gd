extends Node
# Test only. Run the game with --stress-test --gpu-ablate: the harness holds a steady horde of 25
# enemies for about 37 s before its own on/off tests begin (their GPU timers read 0 on handheld
# GLES drivers). In that time this measures the mean frame time in interleaved windows with one
# candidate switched off each: the enemy cell (toon) material, the hair, and eager physics sleep.
const WINDOW := 2.5
const PHASES := ["base", "toon_off", "base", "hair_off", "base", "sleep_eager",
	"base", "toon_off", "base", "hair_off", "base", "sleep_eager", "base"]
var _phase := -1
var _t := 0.0
var _frames: Array[float] = []
var _undo: Array[Callable] = []

func _process(delta: float) -> void:
	if _phase >= PHASES.size():
		return
	if _phase < 0:
		var n := get_tree().get_nodes_in_group("enemy").size()
		if n < 15 or get_tree().root.get_node_or_null("StressTest") == null:
			return
		push_error("FIGHTAB start, %d enemies" % n)
		_phase = 0
		_t = 0.0
		return
	_frames.append(delta * 1000.0)
	_t += delta
	if _t < WINDOW:
		return
	var s := 0.0
	for f in _frames:
		s += f
	push_error("FIGHTAB %s mean=%.1fms frames=%d enemies=%d" % [PHASES[_phase], s / _frames.size(),
		_frames.size(), get_tree().get_nodes_in_group("enemy").size()])
	_frames.clear()
	_t = 0.0
	for u in _undo:
		u.call()
	_undo.clear()
	_phase += 1
	if _phase < PHASES.size():
		_apply(PHASES[_phase])
	else:
		push_error("FIGHTAB done")

func _apply(what: String) -> void:
	match what:
		"toon_off":
			for e in get_tree().get_nodes_in_group("enemy"):
				if "softbody" in e and is_instance_valid(e.softbody) and e.softbody.material != null:
					var sb = e.softbody
					var m = sb.material
					sb.material = null
					_undo.append(func(): if is_instance_valid(sb): sb.material = m)
		"hair_off":
			for h in get_tree().get_nodes_in_group("hair"):
				if is_instance_valid(h) and h.visible:
					h.visible = false
					_undo.append(func(): if is_instance_valid(h): h.visible = true)
		"sleep_eager":
			var space := get_viewport().world_2d.space
			var keys := [PhysicsServer2D.SPACE_PARAM_BODY_TIME_TO_SLEEP,
				PhysicsServer2D.SPACE_PARAM_BODY_LINEAR_VELOCITY_SLEEP_THRESHOLD,
				PhysicsServer2D.SPACE_PARAM_BODY_ANGULAR_VELOCITY_SLEEP_THRESHOLD]
			var eager := [0.1, 10.0, 1.0]
			for i in keys.size():
				var k = keys[i]
				var old := PhysicsServer2D.space_get_param(space, k)
				PhysicsServer2D.space_set_param(space, k, eager[i])
				_undo.append(func(): PhysicsServer2D.space_set_param(space, k, old))
