extends Node
# Test only: logs memory every 5 s and a frame time breakdown every 2 s (push_error reaches the
# log; print from mods does not). Every 20 s it also lists the node classes in the scene and the
# scripts that run every frame, which is where CPU time goes.
# PROBE_PHYS=<n> sets the physics tick rate (default: the game's), for A/B tests.
# Unless PROBE_PHASES=0: once a level is up (over 3000 nodes), switch candidate costs off one at a time
# for PHASE_SECS each, with the baseline between them, and tag the frame reports with the phase.
# Phase names: base | hidep:<path under Main/World> | k:<name, class or script file, + separated>
# (hides those nodes in the player) | x:minimaps_off | x:mask_off | x:pcg_off | x:pbones | x:light_none
# | proc:<script files> | hud | particles | phys20. Under the game's --stress-test the reports are
# tagged with the harness state instead. Remote commands: see CMD_FILE.
var _frames := 0
var _sum := {}
var _worst := 0.0
var _vp: RID

func _ready() -> void:
	var t := Timer.new()
	t.wait_time = 5.0
	t.autostart = true
	t.timeout.connect(_probe)
	add_child(t)
	var f := Timer.new()
	f.wait_time = 2.0
	f.autostart = true
	f.timeout.connect(_frame_report)
	add_child(f)
	var c := Timer.new()
	c.wait_time = 20.0
	c.autostart = true
	c.timeout.connect(_census)
	add_child(c)
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	var phys := OS.get_environment("PROBE_PHYS")
	if phys.is_valid_int():
		Engine.physics_ticks_per_second = phys.to_int()
		push_error("PROBE physics ticks set to %s" % phys)
	process_priority = 1000

func _add(k: String, v: float) -> void:
	_sum[k] = _sum.get(k, 0.0) + v

# Remote control for device tests: lines in /tmp/probe_cmd, read once a second.
#   act <action> <seconds> [strength]   holds an input action (left, right, up, down, shoot, ...)
#   shot   logs the player position
const CMD_FILE := "/tmp/probe_cmd"
var _cmd_t := 0.0
var _held: Dictionary = {}

func _cmd_tick(delta: float) -> void:
	for a in _held.keys():
		_held[a] -= delta
		if _held[a] <= 0.0:
			Input.action_release(a)
			_held.erase(a)
	_cmd_t += delta
	if _cmd_t < 1.0:
		return
	_cmd_t = 0.0
	if not FileAccess.file_exists(CMD_FILE):
		return
	var text := FileAccess.get_file_as_string(CMD_FILE)
	DirAccess.remove_absolute(CMD_FILE)
	for line in text.split("\n", false):
		var w := line.strip_edges().split(" ", false)
		if w.size() >= 3 and w[0] == "act":
			Input.action_press(w[1], float(w[3]) if w.size() > 3 else 1.0)
			_held[w[1]] = float(w[2])
		if w.size() >= 1 and w[0] == "invul":
			get_tree().root.get_node("G").player.invulnerability = 100000.0
		if w.size() >= 3 and w[0] == "eng":
			Engine.set(w[1], int(w[2]))
			push_error("PROBE eng %s = %s" % [w[1], Engine.get(w[1])])
		if w.size() >= 2 and w[0] == "warp":
			var lg := get_tree().root.get_node("Main/World/LevelGenerator")
			var room: Node2D = lg.get_node_or_null(w[1])
			var target: Vector2 = room.global_position
			var tp := room.get_node_or_null("TeleportPos")
			if tp:
				target = tp.global_position
			var info := []
			for ch in room.get_children():
				if ch is Node2D:
					info.append("%s@%s" % [ch.name, ch.global_position])
			push_error("PROBE room %s at %s: %s" % [room.name, room.global_position, ", ".join(info)])
			var pl = get_tree().root.get_node("G").player
			var off: Vector2 = target - pl.center_body.global_position
			for rb in pl.softbody.get_rigid_bodies():
				var b: RigidBody2D = rb.rigidbody
				var t := b.global_transform
				t.origin += off
				PhysicsServer2D.body_set_state(b.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, t)
				b.global_position += off
		if w.size() >= 1 and w[0] == "rooms":
			for r in get_tree().root.get_node("Main/World/LevelGenerator").get_children():
				if r is Node2D:
					push_error("PROBE room %s %s at %s tp=%s" % [r.name, r.get_script().resource_path.get_file() if r.get_script() else "", r.global_position, r.has_node("TeleportPos")])
		if w.size() >= 1 and w[0] == "mmshot":
			var cl := get_tree().root.get_node_or_null("Main/World/CanvasLayer2")
			for nm in ["Minimap", "PlayerMinimap"]:
				var m: Control = cl.get_node(nm)
				var vp: SubViewport = m.find_children("*", "SubViewport", true, false)[0]
				vp.get_texture().get_image().save_png("/tmp/mm_%s.png" % nm)
				push_error("PROBE mm %s vis=%s mode=%d size=%s scale=%s" % [nm, m.is_visible_in_tree(), vp.render_target_update_mode, vp.size, m.scale])
		push_error("PROBE cmd " + line)

func _process(delta: float) -> void:
	_cmd_tick(delta)
	_phase_tick(delta)
	_menu_tick(delta)
	_frames += 1
	_worst = maxf(_worst, delta)
	_add("frame", delta * 1000.0)
	_add("proc", Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_add("phys", Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_add("rcpu", RenderingServer.viewport_get_measured_render_time_cpu(_vp) + RenderingServer.get_frame_setup_time_cpu())
	_add("rgpu", RenderingServer.viewport_get_measured_render_time_gpu(_vp))
	_add("draws", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_add("objs", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))

const PHASE_SECS := 8.0
var PHASES := ["base", "proc:hair.gd", "base", "proc:blood_stream.gd", "base", "proc:connection.gd", "base", "proc:vitals_graph.gd,player_measure_graph.gd", "base", "proc:parallax_sprite.gd", "base", "hud", "base", "particles", "base", "phys20", "base"]
var _phase := -1
var _phase_t := 0.0
var _wait_t := 0.0
var _hidden: Array = []
var _disabled: Array = []

const MENU_PHASES := ["base", "slime_nohdr", "base", "blur", "base", "slime_off", "base", "crt", "base", "menu_all", "base"]
var _mphase := -1
var _mphase_t := 0.0
var _mrestore: Array = []

# In the main menu: switch its effects off one at a time (PROBE_MENU=1 or always when no level ran)
func _menu_tick(delta: float) -> void:
	if OS.get_environment("PROBE_MENU") != "1" or _mphase >= MENU_PHASES.size():
		return
	var menu := get_tree().root.get_node_or_null("MainMenu")
	if not menu:
		return
	_mphase_t += delta
	if _mphase < 0:
		if _mphase_t < 20.0:
			return
		_mphase = 0
		_mphase_t = 0.0
		push_error("PROBE menu phases start")
		return
	if _mphase_t < PHASE_SECS:
		return
	_mphase_t = 0.0
	for r in _mrestore:
		if is_instance_valid(r[0]):
			r[0].set(r[1], r[2])
	_mrestore.clear()
	_mphase += 1
	if _mphase >= MENU_PHASES.size():
		push_error("PROBE menu phases done")
		return
	var what: String = MENU_PHASES[_mphase]
	for n in menu.find_children("*", "", true, false):
		var path := str(n.get_path())
		if what in ["slime_nohdr", "menu_all"] and n is SubViewport and "SlimeShader" in path:
			_mrestore.append([n, "use_hdr_2d", n.use_hdr_2d]); n.use_hdr_2d = false
		if what in ["slime_off", "menu_all"] and n is SubViewport and "SlimeShader" in path:
			_mrestore.append([n, "render_target_update_mode", n.render_target_update_mode]); n.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if n is CanvasItem and n.visible and n.material is ShaderMaterial and n.material.shader:
			var sp: String = n.material.shader.resource_path
			if (what in ["blur", "menu_all"] and sp.ends_with("blur.gdshader")) or (what in ["crt", "menu_all"] and sp.ends_with("crt.gdshader")):
				_mrestore.append([n, "material", n.material]); n.material = null
	push_error("PROBE menu phase %s: %d changes" % [what, _mrestore.size()])

func _phase_tick(delta: float) -> void:
	if OS.get_environment("PROBE_PHASES") == "0" or _phase >= PHASES.size():
		return
	if _phase < 0:
		# a level is up and the level start map (Bodymap) is gone, for 15 s
		_phase_t += delta
		if _phase_t < 1.0:
			return
		_wait_t += _phase_t
		_phase_t = 0.0
		if Performance.get_monitor(Performance.OBJECT_NODE_COUNT) < 3000 or get_tree().root.find_child("Bodymap", true, false) != null:
			_wait_t = 0.0
			return
		if _wait_t < 15.0:
			return
		_phase = 0
		var world := get_tree().root.get_node_or_null("Main/World")
		if world and OS.get_environment("PROBE_WORLD") != "0":
			# each part of the level hidden in turn, then the offscreen views and the player's CanvasGroup
			var list := ["base"]
			for ch in world.get_children():
				if ch.get("visible") == true:
					list.append("hidep:" + str(ch.name))
					list.append("base")
			list.append_array(["x:minimaps_off", "base", "x:mask_off", "base", "x:pcg_off", "base", "k:PointLight2D", "base"])
			PHASES = list
		push_error("PROBE phases start: " + ", ".join(PHASES))
		return
	_phase_t += delta
	if _phase_t < PHASE_SECS:
		return
	_phase_t = 0.0
	_restore()
	_phase += 1
	if _phase >= PHASES.size():
		push_error("PROBE phases done")
		return
	_apply(PHASES[_phase])

var _stopped: Array = []

func _restore() -> void:
	for u in _undo:
		u.call()
	_undo.clear()
	for v in _stopped:
		if is_instance_valid(v[0]):
			v[0].set_process(v[1])
			v[0].set_physics_process(v[2])
	_stopped.clear()
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = true
	for v in _disabled:
		if is_instance_valid(v[0]):
			v[0].render_target_update_mode = v[1]
	_hidden.clear()
	_disabled.clear()
	Engine.physics_ticks_per_second = 30

func _dump(n: Node, d: int, maxd: int) -> void:
	var info := "%s%s [%s]" % ["  ".repeat(d), n.name, n.get_class()]
	var sc: Script = n.get_script()
	if sc:
		info += " " + sc.resource_path.get_file()
	if n is CanvasItem:
		info += " vis=%s z=%d" % [n.visible, n.z_index]
		if n.material is ShaderMaterial and n.material.shader:
			info += " shader=" + n.material.shader.resource_path.get_file()
		if n is CanvasGroup:
			info += " CANVASGROUP"
		if n.clip_children != 0:
			info += " CLIP"
	var cnt := 0
	var st: Array[Node] = [n]
	while not st.is_empty():
		var x: Node = st.pop_back()
		cnt += 1
		st.append_array(x.get_children())
	info += " sub=%d" % cnt
	push_error("PROBE tree " + info)
	if d < maxd:
		for ch in n.get_children():
			_dump(ch, d + 1, maxd)

var _undo: Array[Callable] = []

func _apply(what: String) -> void:
	if what.begins_with("k:"):
		var key := what.trim_prefix("k:")
		var st: Array[Node] = [get_tree().root.get_node("Main/World/GreenBacteria2")]
		while not st.is_empty():
			var x: Node = st.pop_back()
			st.append_array(x.get_children())
			if not (x is CanvasItem) or not x.visible:
				continue
			var sf: String = x.get_script().resource_path.get_file() if x.get_script() else ""
			var hit := false
			if key == "bodypart":
				hit = x.get_parent() and x.get_parent().get_parent() is Node2D and x.get_parent().get_parent().get_script() != null and x.get_parent().get_parent().get_script().resource_path.ends_with("slot.gd") and x.get_parent().name.begins_with("@")
			else:
				hit = str(x.name) in key.split("+") or (sf != "" and sf in key.split("+")) or x.get_class() == key
			if hit:
				x.visible = false
				_hidden.append(x)
		push_error("PROBE phase %s: %d hidden" % [what, _hidden.size()])
		return
	if what.begins_with("x:"):
		var w := get_tree().root.get_node_or_null("Main/World")
		var pl := w.get_node_or_null("GreenBacteria2")
		match what:
			"x:pcg_off":
				pl.set_canvas_group_active(false)
				_undo.append(func(): pl.set_canvas_group_active(true))
			"x:psoft_mat":
				var sb: CanvasItem = pl.get_node("CanvasGroup/SoftBody2D")
				var m := sb.material
				sb.material = null
				_undo.append(func(): sb.material = m)
			"x:pbones":
				for ch in pl.get_node("CanvasGroup/SoftBody2D").get_children():
					if ch is RigidBody2D and ch.visible:
						ch.visible = false
						_hidden.append(ch)
			"x:pbones_children":
				for ch in pl.get_node("CanvasGroup/SoftBody2D").get_children():
					if ch is RigidBody2D:
						for g in ch.get_children():
							if g is CanvasItem and g.visible:
								g.visible = false
								_hidden.append(g)
			"x:light_none":
				var g = get_tree().root.get_node("G")
				var old_lm = g.lighting_mode
				g.lighting_mode = 2
				g.get_node("/root/SignalBus").lighting_mode_changed.emit()
				_undo.append(func():
					g.lighting_mode = old_lm
					g.get_node("/root/SignalBus").lighting_mode_changed.emit())
			"x:all_cheap":
				pl.set_canvas_group_active(false)
				_undo.append(func(): pl.set_canvas_group_active(true))
				for nm in ["CanvasLayer2/PlayerMinimap", "CanvasLayer2/Minimap", "Background/Mask"]:
					var st: Array[Node] = [w.get_node(nm)]
					while not st.is_empty():
						var x: Node = st.pop_back()
						st.append_array(x.get_children())
						if x is SubViewport:
							var vp: SubViewport = x
							var old_mode := vp.render_target_update_mode
							vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
							_undo.append(func(): vp.render_target_update_mode = old_mode)
			"x:minimaps_off", "x:mask_off":
				var names := ["CanvasLayer2/PlayerMinimap", "CanvasLayer2/Minimap"] if what == "x:minimaps_off" else ["Background/Mask"]
				for nm in names:
					var st: Array[Node] = [w.get_node(nm)]
					while not st.is_empty():
						var x: Node = st.pop_back()
						st.append_array(x.get_children())
						if x is SubViewport:
							var vp: SubViewport = x
							var old_mode := vp.render_target_update_mode
							vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
							_undo.append(func(): vp.render_target_update_mode = old_mode)
		push_error("PROBE phase %s: %d undo" % [what, _undo.size()])
		return
	if what.begins_with("hidep:"):
		var tn := get_tree().root.get_node_or_null("Main/World/" + what.trim_prefix("hidep:"))
		if tn:
			tn.visible = false
			_hidden.append(tn)
		push_error("PROBE phase %s: %d hidden" % [what, _hidden.size()])
		return
	var scripts := what.trim_prefix("proc:").split(",") if what.begins_with("proc:") else PackedStringArray()
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var path := str(node.get_path())
		var nsc: Script = node.get_script()
		if nsc and nsc.resource_path.get_file() in scripts:
			_stopped.append([node, node.is_processing(), node.is_physics_processing()])
			node.set_process(false)
			node.set_physics_process(false)
		if what.begins_with("hide") and node.get_parent() and node.get_parent().get_path() == NodePath("/root/Main/World") \
				and (what.ends_with(":" + str(node.name)) or what == "hide:*") and node.get("visible") == true:
			node.visible = false
			_hidden.append(node)
		if what == "hud" and node is CanvasLayer and node.name == "UICanvasLayer" and node.visible:
			node.visible = false
			_hidden.append(node)
		if node is CanvasItem and node.visible:
			var hide := false
			if what in ["particles", "all"] and node is GPUParticles2D:
				hide = true
			if what in ["grass", "all"] and node.material is ShaderMaterial and node.material.shader and node.material.shader.resource_path.ends_with("grass.gdshader"):
				hide = true
			if what in ["canvasgroups", "all"] and node is CanvasGroup:
				hide = true
			if what in ["multimesh", "all"] and node is MultiMeshInstance2D:
				hide = true
			if hide:
				node.visible = false
				_hidden.append(node)
		if node is SubViewport and node.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			if (what in ["minimaps", "all"] and "Minimap" in path) or (what in ["bgviewports", "all"] and "/Background/" in path):
				_disabled.append([node, node.render_target_update_mode])
				node.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if what in ["phys30", "all"]:
		Engine.physics_ticks_per_second = 30
	if what == "phys20":
		Engine.physics_ticks_per_second = 20
	push_error("PROBE phase %s: %d hidden, %d viewports off, %d stopped" % [what, _hidden.size(), _disabled.size(), _stopped.size()])

func _frame_report() -> void:
	if _frames == 0:
		return
	var n := float(_frames)
	var tag: String = PHASES[_phase] if _phase >= 0 and _phase < PHASES.size() else ("menu:" + MENU_PHASES[_mphase] if _mphase >= 0 and _mphase < MENU_PHASES.size() else "-")
	var stn := get_tree().root.get_node_or_null("StressTest")
	if stn:
		tag = "st:ka%d,fire%d,pool%d,tick%d,max%d" % [stn.get("_keep_alive"), int(stn.get("_firing")), (stn.get("_spawn_pool") as Array).size() if stn.get("_spawn_pool") is Array else -1, Engine.physics_ticks_per_second, Engine.max_physics_steps_per_frame]
	push_error(("PROBE frame [%s] " % tag) + "fps=%.1f frame=%.1fms worst=%.0fms proc=%.1fms phys=%.1fms render_cpu=%.1fms render_gpu=%.1fms draws=%d objs=%d nodes=%d phys_active=%d pairs=%d" % [
		n / (_sum["frame"] / 1000.0), _sum["frame"] / n, _worst * 1000.0, _sum["proc"] / n, _sum["phys"] / n,
		_sum["rcpu"] / n, _sum["rgpu"] / n, int(_sum["draws"] / n), int(_sum["objs"] / n),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
		Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)])
	_frames = 0
	_sum.clear()
	_worst = 0.0

func _census() -> void:
	var classes := {}
	var proc := {}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var cls := node.get_class()
		if node is CanvasItem and not node.is_visible_in_tree():
			cls += "(hidden)"
		classes[cls] = classes.get(cls, 0) + 1
		var sc: Script = node.get_script()
		if sc and (node.is_processing() or node.is_physics_processing()):
			var k := "%s%s%s" % [sc.resource_path.get_file(), " P" if node.is_processing() else "", " F" if node.is_physics_processing() else ""]
			proc[k] = proc.get(k, 0) + 1
	push_error("PROBE classes " + _top(classes, 25))
	push_error("PROBE per frame scripts " + _top(proc, 25))
	_gpu_census()

# What the GPU draws besides the screen: every SubViewport (size, update mode, HDR), the shaders
# on visible items (screen reading ones need a back buffer copy), lights and CanvasGroups.
func _gpu_census() -> void:
	var vps := PackedStringArray()
	var shaders := {}
	var heavy := {}
	var parts := {}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is SubViewport:
			var vp: SubViewport = node
			var par = vp.get_parent()
			var pinfo := ""
			if par is Control:
				pinfo = " parent=%s size=%s gscale=%s" % [par.get_class(), par.size, par.get_global_transform_with_canvas().get_scale()]
				if par is SubViewportContainer:
					pinfo += " stretch=%s shrink=%d" % [par.stretch, par.stretch_shrink]
			vps.append("%s %dx%d upd=%d hdr=%s override=%s%s" % [_short(vp), vp.size.x, vp.size.y, vp.render_target_update_mode, vp.use_hdr_2d, vp.size_2d_override, pinfo])
		if node is CanvasItem and node.is_visible_in_tree():
			var m = node.material
			if m is ShaderMaterial and m.shader:
				var code: String = m.shader.code
				var k: String = m.shader.resource_path.get_file()
				if k == "":
					k = "inline:" + _short(node)
				if "SCREEN_TEXTURE" in code or "hint_screen_texture" in code:
					k += "[screen]"
				shaders[k] = shaders.get(k, 0) + 1
			if node is GPUParticles2D:
				var src := ""
				var up: Node = node
				while up and src == "":
					var sc: Script = up.get_script()
					src = up.scene_file_path.get_file() if up.scene_file_path != "" else (sc.resource_path.get_file() if sc else "")
					up = up.get_parent()
				var key := "%s%s" % [src, "" if node.emitting else "(idle)"]
				parts[key] = parts.get(key, 0) + 1
			for cls in ["PointLight2D", "DirectionalLight2D", "LightOccluder2D", "CanvasGroup", "BackBufferCopy", "GPUParticles2D", "CPUParticles2D", "Line2D", "Polygon2D", "MeshInstance2D", "MultiMeshInstance2D"]:
				if node.is_class(cls):
					heavy[cls] = heavy.get(cls, 0) + 1
	push_error("PROBE particles " + _top(parts, 20))
	push_error("PROBE subviewports " + " | ".join(vps))
	push_error("PROBE shaders " + _top(shaders, 30))
	push_error("PROBE heavy " + _top(heavy, 15))

func _short(n: Node) -> String:
	var path := str(n.get_path())
	return path.right(70) if path.length() > 70 else path

func _top(d: Dictionary, n: int) -> String:
	var keys := d.keys()
	keys.sort_custom(func(a, b): return d[a] > d[b])
	var out := PackedStringArray()
	for k in keys.slice(0, n):
		out.append("%s=%d" % [k, d[k]])
	return ", ".join(out)

func _probe() -> void:
	push_error("PROBE t=%d tex=%dMB vid=%dMB buf=%dMB static=%dMB objs=%d res=%d" % [
		Time.get_ticks_msec() / 1000,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576,
		Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576,
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)])
