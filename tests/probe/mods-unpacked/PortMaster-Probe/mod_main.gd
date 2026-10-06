extends Node
# Test only: logs memory every 5 s (push_error reaches the log; print from mods does not).
func _ready() -> void:
	var t := Timer.new()
	t.wait_time = 5.0
	t.autostart = true
	t.timeout.connect(_probe)
	add_child(t)

func _probe() -> void:
	push_error("PROBE t=%d tex=%dMB vid=%dMB buf=%dMB static=%dMB objs=%d res=%d" % [
		Time.get_ticks_msec() / 1000,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576,
		Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576,
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)])
