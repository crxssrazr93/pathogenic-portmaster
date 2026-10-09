extends Node
# Test only: drawn size survey. For every texture drawn anywhere it visits, records the largest
# size it is drawn at, as screen pixels per texture pixel at the 1920x1080 design size ("k").
# Env: SV_OUT (folder), SV_MODE = level | parts | ui, SV_LEVEL (1 to 7), SV_ZS (camera zoom option,
# the port sets 1.25), SV_PARASITE (0 to 7), SV_ROOMS (limit, 0 = all).
# Results: <SV_OUT>/texk.json {path: {w,h,k,area,n,src:{class:k}, where:[..]}}, <SV_OUT>/done.txt

var out := ""
var mode := "level"
var level := 1
var zs := 1.25
var parasite := 0
var texk := {}
var cover := []
var where := ""
var skipped := {}
var unknown_shaders := {}
var lock_pos = null
var lock_zoom := 0.0
var busy_flag := false

func _log(s: String) -> void:
	push_error("SV " + s)

func _env(n: String, d: String) -> String:
	var v := OS.get_environment(n)
	return v if v != "" else d

func _ready() -> void:
	out = _env("SV_OUT", "/tmp/sv")
	mode = _env("SV_MODE", "level")
	level = int(_env("SV_LEVEL", "1"))
	zs = float(_env("SV_ZS", "1.25"))
	parasite = int(_env("SV_PARASITE", "0"))
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100000
	process_physics_priority = 100000
	DirAccess.make_dir_recursive_absolute(out)
	_log("ready mode=%s level=%d zs=%s parasite=%d" % [mode, level, zs, parasite])
	_boot.call_deferred()

func _sleep(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _boot() -> void:
	await _frames(3)
	if mode == "ui":
		_ui_survey.call_deferred()
		return
	G.selected_parasite = parasite
	G.skip_bodymap_anim = mode != "bodymap"
	RunSaveManager.is_loading_run = false
	G.reset()
	G.god_mode = true
	G.rng_seed = _env("SV_SEED", "SURVEY01")
	G.level_number = level
	get_tree().change_scene_to_file("res://scn/main.tscn")
	if mode == "bodymap":
		_bodymap_sampler.call_deferred()
	await SignalBus.run_started
	await _sleep(2.5)
	var rt := get_tree().root
	_log("run started level=%d size=%s final=%s canvas=%s mode=%d factor=%s cs_size=%s" % [G.level_number, rt.size, rt.get_final_transform(), rt.get_canvas_transform(), rt.content_scale_mode, rt.content_scale_factor, rt.content_scale_size])
	if mode == "bodymap":
		return
	if mode == "level":
		await _level_survey()
	elif mode == "parts":
		await _parts_survey()
	elif mode == "enemies":
		await _enemies_survey()
	elif mode == "rooms":
		await _rooms_survey()
	elif mode == "misc":
		await _misc_survey()
	_finish()

func _finish() -> void:
	_save()
	var f := FileAccess.open(out.path_join("done.txt"), FileAccess.WRITE)
	f.store_string("done\n")
	f.close()
	_log("done textures=%d" % texk.size())

func _save() -> void:
	var jf := FileAccess.open(out.path_join("texk.json"), FileAccess.WRITE)
	jf.store_string(JSON.stringify({"tex": texk, "cover": cover, "skipped": skipped, "unknown_shaders": unknown_shaders}))
	jf.close()

# ---- camera lock ----
func _process(_d: float) -> void:
	_apply_lock()

func _physics_process(_d: float) -> void:
	_apply_lock()
	if mode != "ui" and G.player != null and is_instance_valid(G.player):
		var p = G.player
		if p.dead:
			p.dead = false
		if p.hp < p.max_hp:
			p.hp = p.max_hp

func _apply_lock() -> void:
	if lock_pos == null:
		return
	var cam: Camera2D = get_viewport().get_camera_2d()
	if not cam:
		return
	cam.position_smoothing_enabled = false
	cam.global_position = lock_pos
	cam.offset = Vector2.ZERO
	cam.zoom = Vector2.ONE * lock_zoom
	cam.force_update_scroll()

# ---- zoom the game would use while the player is in a room ----
func _room_zoom(room) -> float:
	var az: float = room.auto_zoom if room != null and "auto_zoom" in room else 1.0
	if az != 1.0:
		return az * 0.36 * zs
	return G.get_level_config().base_zoom.x * zs

# ---- level survey ----
func _level_survey() -> void:
	var gen = G.level_generator
	var rooms: Array = []
	for r in gen.rooms:
		if is_instance_valid(r) and not rooms.has(r):
			rooms.append(r)
	if is_instance_valid(gen.boss_room) and not rooms.has(gen.boss_room):
		rooms.append(gen.boss_room)
	var limit := int(_env("SV_ROOMS", "0"))
	_log("rooms=%d halls=%d boss=%s" % [rooms.size(), gen.halls.size(), gen.boss_room])
	var pool := []
	for rr in G.get_level_config().get_room_pool():
		pool.append([rr.resource_path, int(rr.type)])
	cover.append({"pool": pool, "level": level, "base_zoom": G.get_level_config().base_zoom.x})
	# the start room first (the player is in it), the boss last
	var boss = gen.boss_room
	rooms.erase(boss)
	rooms.append(boss)
	var idx := 0
	for room in rooms:
		if not is_instance_valid(room):
			continue
		if limit > 0 and idx >= limit:
			break
		idx += 1
		var is_boss: bool = room == boss
		var rtype := str(room.res.type) if room.res != null else "?"
		var rname: String = room.get_room_name() if room.has_method("get_room_name") else str(room.name)
		where = "L%d %s%s" % [level, rname, " BOSS" if is_boss else ""]
		var z := _room_zoom(room)
		G.player.teleport(Transform2D(0.0, room.global_position))
		G.main.reset_camera_pos()
		lock_pos = room.global_position
		lock_zoom = z
		await _frames(20)
		if is_instance_valid(room):
			room.enter()
		await _sleep(2.0 if not is_boss else 3.0)
		var n0 := texk.size()
		_census()
		var pts := [room.global_position]
		for i in 2:
			if room.has_method("get_random_point"):
				pts.append(room.get_random_point())
		for p in pts:
			lock_pos = p
			await _frames(25)
			_census()
		if is_boss:
			for i in 4:
				await _sleep(2.0)
				_census()
		var enemies := get_tree().get_nodes_in_group("enemy").size()
		cover.append({"where": where, "rtype": rtype, "zoom": z, "enemies": enemies, "new_textures": texk.size() - n0, "scene": room.res.resource_path if room.res != null else room.scene_file_path})
		_log("room %s type=%s zoom=%.3f enemies=%d textures=%d (+%d)" % [where, rtype, z, enemies, texk.size(), texk.size() - n0])
		for e in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e):
				e.queue_free()
		for g in ["enemy_bullets", "bullets", "player_bullets", "gib"]:
			for b in get_tree().get_nodes_in_group(g):
				if is_instance_valid(b):
					b.queue_free()
		_save()
	# halls
	var hn := 0
	for h in gen.halls:
		if not is_instance_valid(h):
			continue
		if limit > 0 and hn >= limit:
			break
		hn += 1
		where = "L%d hall" % level
		var pos: Vector2 = h.global_position
		var line := h.get_node_or_null("BgLine") as Line2D
		if line and line.points.size() > 1:
			pos = h.to_global(line.points[line.points.size() / 2])
		G.player.teleport(Transform2D(0.0, pos))
		G.main.reset_camera_pos()
		lock_pos = pos
		lock_zoom = G.get_level_config().base_zoom.x * zs
		await _frames(25)
		_census()
		if hn % 4 == 0:
			_save()
	lock_pos = null

# ---- bodyparts and parasites ----
func _parts_survey() -> void:
	where = "parts p%d" % parasite
	lock_zoom = 0.36 * zs
	lock_pos = G.player.center_body.global_position
	await _sleep(1.0)
	_census()
	await _editor_census()
	if parasite != 0:
		return
	var ids: Array = G.bodyparts_by_id.keys()
	ids.sort()
	_log("bodyparts=%d" % ids.size())
	var ext: Array = []
	var inn: Array = []
	for id in ids:
		var res = G.bodyparts_by_id[id]
		var path: String = res.resource_path
		(inn if path.contains("/internal/") else ext).append(id)
	_log("external=%d internal=%d" % [ext.size(), inn.size()])
	# swap the body for the long one with many slots
	var pos = G.player.center_body.global_position
	var parent = G.player.get_parent()
	G.player.queue_free()
	var np = load("res://scn/player/evolutions/player_2_long.tscn").instantiate()
	parent.add_child(np)
	G.player = np
	await _frames(3)
	var eslots := []
	var islots := []
	for s in np.slots:
		(islots if str(s.name).begins_with("I") else eslots).append(s)
	_log("slots e=%d i=%d" % [eslots.size(), islots.size()])
	np.teleport(Transform2D(0.0, pos))
	G.main.reset_camera_pos()
	lock_pos = np.center_body.global_position
	for rarity in [3]:
		await _attach_batches(np, ext, eslots, rarity)
		await _attach_batches(np, inn, islots, rarity)
	# every body the player can evolve into
	for path in _scenes("res://scn/player"):
		if not path.contains("/evolutions/") and not path.contains("player_"):
			continue
		var ps = load(path)
		if ps == null:
			continue
		var old = G.player
		var par = old.get_parent()
		var posn = old.center_body.global_position
		old.queue_free()
		var nn = ps.instantiate()
		if not ("slots" in nn):
			nn.queue_free()
			G.player = old
			continue
		par.add_child(nn)
		G.player = nn
		await _frames(4)
		nn.teleport(Transform2D(0.0, posn))
		G.main.reset_camera_pos()
		lock_pos = nn.center_body.global_position
		where = "body " + path.get_file()
		await _frames(10)
		_census()
		await _editor_census()
		lock_pos = nn.center_body.global_position
		_log("body %s textures=%d" % [path.get_file(), texk.size()])
	

func _attach_batches(np, ids: Array, slots: Array, rarity: int) -> void:
	var i := 0
	while i < ids.size():
		for s in slots:
			if is_instance_valid(s.bodypart):
				s.bodypart.queue_free()
		await _frames(2)
		var batch := []
		for s in slots:
			if i >= ids.size():
				break
			var id: String = ids[i]
			i += 1
			batch.append(id)
			np._attach_loadout_entry(s, {"bodypart": id, "rarity": rarity})
		await _frames(6)
		lock_pos = np.center_body.global_position
		where = "parts " + ",".join(batch)
		_census()
		await _editor_census()
		lock_pos = np.center_body.global_position
		_log("parts batch %d/%d textures=%d" % [i, ids.size(), texk.size()])
		if i % 20 == 0:
			_save()

func _bodymap_sampler() -> void:
	where = "bodymap L%d" % level
	var t := 0.0
	var seen := false
	while t < 60.0:
		await _sleep(0.25)
		t += 0.25
		if G.ui != null and is_instance_valid(G.ui.bodymap) and G.ui.bodymap.is_inside_tree():
			seen = true
			_census()
		elif seen:
			break
	_log("bodymap sampled t=%.1f textures=%d" % [t, texk.size()])
	_finish()

func _editor_census() -> void:
	var saved = lock_pos
	lock_pos = null
	G.editor.animate_open(true)
	await _sleep(2.4)
	_census()
	G.editor.animate_close(true)
	await _sleep(1.6)
	lock_pos = saved

func _scenes(dir: String) -> Array:
	var res := []
	var d := DirAccess.open(dir)
	if d == null:
		return res
	for f in d.get_files():
		var n := f.trim_suffix(".remap")
		if n.ends_with(".tscn") or n.ends_with(".scn"):
			res.append(dir.path_join(n.get_basename() + ".tscn"))
	for sub in d.get_directories():
		res.append_array(_scenes(dir.path_join(sub)))
	return res

# ---- every room scene of the game, one at a time, away from the level ----
func _rooms_survey() -> void:
	var gen = G.level_generator
	var far := Vector2(260000.0, 0.0)
	var idx := 0
	var total := G.all_rooms.size()
	_log("room resources=%d" % total)
	for rr in G.all_rooms:
		idx += 1
		var inst = rr.instantiate()
		if inst == null:
			continue
		where = "room " + rr.resource_path.get_file()
		gen.add_child(inst)
		inst.global_position = far
		G.player.teleport(Transform2D(0.0, far))
		G.main.reset_camera_pos()
		lock_pos = far
		await _frames(6)
		lock_zoom = _room_zoom(inst)
		await _frames(25)
		_census()
		cover.append({"where": where, "room_scene": rr.resource_path, "type": int(rr.type), "zoom": lock_zoom})
		inst.queue_free()
		await _frames(3)
		if idx % 10 == 0:
			_log("rooms %d/%d textures=%d" % [idx, total, texk.size()])
			_save()

# ---- other scenes: effects, projectiles, props, pickups ----
func _misc_survey() -> void:
	var gen = G.level_generator
	var far := Vector2(260000.0, 0.0)
	G.player.teleport(Transform2D(0.0, far))
	G.main.reset_camera_pos()
	lock_pos = far
	lock_zoom = G.get_level_config().base_zoom.x * zs
	var dirs := _env("SV_DIRS", "res://scn/particles,res://scn/player/projectiles,res://scn/player/status_effects,res://scn/player/minions,res://scn/enemies/shots,res://scn/environ/pickups,res://scn/environ/props,res://scn/platforms,res://scn/cells").split(",", false)
	var idx := 0
	var from := int(_env("SV_FROM", "0"))  # resume after a crash, as in the enemy sweep
	var item := -1
	for dir in dirs:
		for path in _scenes(dir):
			item += 1
			if item < from:
				continue
			_log("item %d %s" % [item, path.get_file()])
			var ps = load(path)
			if ps == null or not (ps is PackedScene):
				continue
			var inst = ps.instantiate()
			if not (inst is Node2D):
				if inst:
					inst.queue_free()
				continue
			where = "misc " + path.get_file()
			gen.add_child(inst)
			inst.global_position = far
			await _frames(12)
			_census()
			await _frames(18)
			_census()
			if is_instance_valid(inst):
				inst.queue_free()
			idx += 1
			cover.append({"where": where, "misc_scene": path})
			_save()
			if idx % 10 == 0:
				_log("misc %d textures=%d (%s)" % [idx, texk.size(), path.get_file()])
				_save()
			await _frames(2)

# ---- every enemy scene, one at a time, in the boss room ----
func _enemies_survey() -> void:
	var gen = G.level_generator
	var room = gen.boss_room
	var paths := _scenes("res://scn/enemies")
	_log("enemy scenes=%d" % paths.size())
	where = "enemies"
	var pos: Vector2 = room.global_position
	G.player.teleport(Transform2D(0.0, pos + Vector2(0, 1500)))
	G.main.reset_camera_pos()
	lock_pos = pos
	lock_zoom = G.get_level_config().base_zoom.x * zs
	if room.has_node("NavigationPoly"):
		room.get_node("NavigationPoly").enabled = true
	await _sleep(1.0)
	var done_n := 0
	# SV_FROM: resume a sweep after the scene at that index crashed the game
	var from := int(_env("SV_FROM", "0"))
	var item := -1
	for path in paths:
		item += 1
		if item < from:
			continue
		_log("item %d %s" % [item, path.get_file()])
		var sc = load(path)
		if sc == null:
			continue
		var e = sc.instantiate()
		if not (e is Node2D):
			e.queue_free()
			continue
		if "room" in e:
			e.room = room
		if "skip_room_bounds_check" in e:
			e.skip_room_bounds_check = true
		if "dna_reward" in e:
			e.dna_reward = 0
		e.global_position = pos
		where = "enemy " + path.get_file()
		Utils.safe_add_child_deferred(gen, e)
		await _frames(30)
		if is_instance_valid(e):
			e.global_position = pos
		await _sleep(1.2)
		_census()
		if is_instance_valid(e):
			e.queue_free()
		await _frames(5)
		done_n += 1
		cover.append({"where": where, "enemy_scene": path})
		_save()
		if done_n % 10 == 0:
			_log("enemies %d/%d textures=%d" % [done_n, paths.size(), texk.size()])
			_save()
		for g in ["enemy_bullets", "bullets", "gib", "enemy"]:
			for b in get_tree().get_nodes_in_group(g):
				if is_instance_valid(b):
					b.queue_free()

# ---- UI survey: menus and screens ----
func _ui_survey() -> void:
	where = "ui"
	var t := 0.0
	while get_tree().root.get_node_or_null("MainMenu") == null and t < 90.0:
		await _sleep(0.5)
		t += 0.5
	await _sleep(8.0)
	_census()
	_log("menu census textures=%d" % texk.size())
	await _ui_more()
	_finish()

func _ui_more() -> void:
	var skip := _env("SV_SKIP", "").split(",", false)
	var n := 0
	for dir in ["res://scn/ui", "res://scn/metaprogression", "res://scn/cells"]:
		for path in _scenes(dir):
			var base: String = path.get_file()
			if skip.has(base) or base.begins_with("main_menu") or base.contains("quit") or base.contains("splash"):
				continue
			var ps = load(path)
			if ps == null or not (ps is PackedScene):
				continue
			_log("ui scene %s" % path)
			var inst = ps.instantiate()
			if inst == null:
				continue
			if not (inst is CanvasItem):
				inst.queue_free()
				continue
			var layer := CanvasLayer.new()
			layer.layer = 60
			get_tree().root.add_child(layer)
			layer.add_child(inst)
			if inst is Control and inst.size == Vector2.ZERO:
				inst.set_anchors_preset(Control.PRESET_FULL_RECT)
			where = "ui " + base
			await _sleep(0.6)
			_census()
			n += 1
			layer.queue_free()
			await _frames(3)
			if n % 8 == 0:
				_save()
	_log("ui scenes shown=%d" % n)

# ---- census ----
func _real(tex):
	if tex is CanvasTexture:
		return tex.diffuse_texture
	return tex

func _extras(tex) -> Array:
	var r := []
	if tex is CanvasTexture:
		if tex.normal_texture:
			r.append(tex.normal_texture)
		if tex.specular_texture:
			r.append(tex.specular_texture)
	return r

func _tex_path(tex: Texture2D) -> String:
	var t := tex
	if t is AtlasTexture and t.atlas:
		t = t.atlas
	return t.resource_path

func _vis_area(xf: Transform2D, r: Rect2, bounds: Rect2) -> float:
	var pts := [xf * r.position, xf * (r.position + Vector2(r.size.x, 0)), xf * (r.position + Vector2(0, r.size.y)), xf * r.end]
	var mn: Vector2 = pts[0]
	var mx: Vector2 = pts[0]
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	return bounds.intersection(Rect2(mn, mx - mn)).get_area()

# [[texture, k_screen, area, class]]
func _entries(n: CanvasItem, root: Rect2) -> Array:
	var vp := n.get_viewport()
	var xf := vp.get_final_transform() * n.get_global_transform_with_canvas()
	var k := (xf.x.length() + xf.y.length()) / 2.0
	var res := []
	var cls := n.get_class()
	if n is Sprite2D and n.texture:
		res.append([n.texture, k, _vis_area(xf, n.get_rect(), root), cls])
	elif n is AnimatedSprite2D and n.sprite_frames:
		var sf: SpriteFrames = n.sprite_frames
		var area := 0.0
		var cur: Texture2D = null
		if sf.has_animation(n.animation):
			cur = sf.get_frame_texture(n.animation, n.frame)
			if cur:
				var sz := cur.get_size()
				var r := Rect2(-sz / 2.0 if n.centered else Vector2.ZERO, sz)
				r.position += n.offset
				area = _vis_area(xf, r, root)
		if area >= 4.0:
			# every frame of every animation of a visible sprite may be shown
			var seen := {}
			for an in sf.get_animation_names():
				for fi in sf.get_frame_count(an):
					var ft: Texture2D = sf.get_frame_texture(an, fi)
					if ft and not seen.has(ft):
						seen[ft] = true
						res.append([ft, k, area, "AnimatedSprite2D"])
	elif n is Polygon2D and n.texture:
		var ts: Vector2 = n.texture_scale
		var kk := k / maxf(absf(ts.x), 0.0001)
		var poly: PackedVector2Array = n.polygon
		if poly.size() >= 3:
			var mn := poly[0]
			var mx := poly[0]
			for p in poly:
				mn = mn.min(p)
				mx = mx.max(p)
			res.append([n.texture, kk, _vis_area(xf, Rect2(mn + n.offset, mx - mn), root), cls])
	elif n is MultiMeshInstance2D and n.texture and n.multimesh and n.multimesh.mesh:
		var mm: MultiMesh = n.multimesh
		var cnt := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		var tex = _real(n.texture)
		var ab: AABB = mm.mesh.get_aabb()
		var mesh_k := absf(ab.size.x) / maxf(tex.get_width(), 1.0)
		var kmax := 0.0
		var area := 0.0
		var r := Rect2(Vector2(ab.position.x, ab.position.y), Vector2(ab.size.x, ab.size.y)).abs()
		for i in mini(cnt, 4000):
			var it: Transform2D = mm.get_instance_transform_2d(i)
			var x2 := xf * it
			var a := _vis_area(x2, r, root)
			if a > 0.0:
				kmax = maxf(kmax, (x2.x.length() + x2.y.length()) / 2.0 * mesh_k)
				area += a
		if area > 0.0:
			res.append([n.texture, kmax, area, cls])
	elif n is MeshInstance2D and n.texture and n.mesh:
		var tex = _real(n.texture)
		var arr: Array = n.mesh.surface_get_arrays(0) if n.mesh.get_surface_count() > 0 else []
		if arr.size() > Mesh.ARRAY_TEX_UV and arr[Mesh.ARRAY_TEX_UV] != null and arr[Mesh.ARRAY_TEX_UV].size() > 0:
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var umin := uv[0]
			var umax := uv[0]
			for u in uv:
				umin = umin.min(u)
				umax = umax.max(u)
			var ab: AABB = n.mesh.get_aabb()
			# repeating or tiled UVs span more than one texture: use the larger of the two axes
			var kx := absf(ab.size.x) / maxf((umax.x - umin.x) * tex.get_width(), 0.001)
			var ky := absf(ab.size.y) / maxf((umax.y - umin.y) * tex.get_height(), 0.001)
			res.append([n.texture, k * maxf(kx, ky), _vis_area(xf, Rect2(Vector2(ab.position.x, ab.position.y), Vector2(ab.size.x, ab.size.y)).abs(), root), cls])
	elif n is Line2D and n.texture:
		var pts: PackedVector2Array = n.points
		if pts.size() >= 2:
			var mn := pts[0]
			var mx := pts[0]
			for p in pts:
				mn = mn.min(p)
				mx = mx.max(p)
			var tex = _real(n.texture)
			var kl: float = n.width / maxf(tex.get_height(), 1.0)
			res.append([n.texture, k * kl, minf(_vis_area(xf, Rect2(mn, mx - mn).grow(n.width / 2.0), root), 1e9), cls])
	elif n is NinePatchRect and n.texture:
		res.append([n.texture, k, _vis_area(xf, Rect2(Vector2.ZERO, n.size), root), cls])
	elif n is TextureRect and n.texture:
		var tw: Vector2 = n.texture.get_size()
		var rs: Vector2 = n.size
		var kk := k
		if n.stretch_mode != TextureRect.STRETCH_KEEP and n.stretch_mode != TextureRect.STRETCH_TILE:
			kk = minf(rs.x / maxf(tw.x, 1.0), rs.y / maxf(tw.y, 1.0)) * k
			if n.stretch_mode == TextureRect.STRETCH_SCALE:
				kk = maxf(rs.x / maxf(tw.x, 1.0), rs.y / maxf(tw.y, 1.0)) * k
		res.append([n.texture, kk, _vis_area(xf, Rect2(Vector2.ZERO, rs), root), cls])
	elif n is TextureButton:
		for t in [n.texture_normal, n.texture_pressed, n.texture_hover, n.texture_disabled, n.texture_focused]:
			if t:
				res.append([t, k, _vis_area(xf, Rect2(Vector2.ZERO, n.size), root), cls])
	elif n is TextureProgressBar:
		for t in [n.texture_under, n.texture_over, n.texture_progress]:
			if t:
				res.append([t, k, _vis_area(xf, Rect2(Vector2.ZERO, n.size), root), cls])
	elif n is Button and n.icon:
		res.append([n.icon, k, _vis_area(xf, Rect2(Vector2.ZERO, n.size), root), cls])
	elif n is GPUParticles2D or n is CPUParticles2D:
		var tex = n.texture
		if tex:
			var sc := 1.0
			if n is GPUParticles2D and n.process_material is ParticleProcessMaterial:
				var pm: ParticleProcessMaterial = n.process_material
				sc = maxf(pm.scale_max, 0.0001)
				if pm.scale_curve is CurveTexture and pm.scale_curve.curve:
					var cmax := 0.0
					for i in pm.scale_curve.curve.point_count:
						cmax = maxf(cmax, pm.scale_curve.curve.get_point_position(i).y)
					sc *= maxf(cmax, 0.0001)
			elif n is CPUParticles2D:
				sc = maxf(n.scale_amount_max, 0.0001)
			var on_screen := _vis_area(xf, Rect2(Vector2(-50, -50), Vector2(100, 100)), root)
			res.append([tex, k * sc, maxf(on_screen, 100.0) if n.emitting else 0.0, cls])
	return res

func _shader_entries(n: CanvasItem, base: Array) -> Array:
	var res := []
	var mat := n.material as ShaderMaterial
	if mat == null or mat.shader == null:
		return res
	var code := mat.shader.code
	var xf := n.get_viewport().get_final_transform() * n.get_global_transform_with_canvas()
	var k := (xf.x.length() + xf.y.length()) / 2.0
	var world_div := 0.0
	var m := RegEx.create_from_string("world_pos\\s*/\\s*([0-9.]+)").search(code)
	if m:
		world_div = m.get_string(1).to_float()
	var main_w := 0.0
	if not base.is_empty():
		main_w = _real(base[0][0]).get_width()
	for u in mat.shader.get_shader_uniform_list():
		var v = mat.get_shader_parameter(u["name"])
		if not (v is Texture2D):
			continue
		var p := _tex_path(v)
		if not p.begins_with("res://gfx"):
			continue
		var tw: float = maxf(_real(v).get_width(), 1.0)
		if world_div > 0.0:
			# sampled at world position / (world_div * cell_size): one texture covers that many world units
			var cell = mat.get_shader_parameter("cell_size")
			var cellf: float = cell if cell is float else 1.0
			var zoom_total := _canvas_scale(n)
			var kk := (world_div * cellf / tw) * zoom_total
			res.append([v, kk, 1e6, "shader-world " + mat.shader.resource_path.get_file()])
		elif not base.is_empty() and main_w > 0.0:
			res.append([v, base[0][1] * main_w / tw, base[0][2], "shader-uv " + mat.shader.resource_path.get_file()])
		else:
			unknown_shaders[mat.shader.resource_path.get_file() + " " + p] = k
	return res

# screen pixels per canvas unit (camera zoom and content scale)
func _canvas_scale(n: CanvasItem) -> float:
	var t := n.get_viewport().get_final_transform() * n.get_viewport().get_canvas_transform()
	return (t.x.length() + t.y.length()) / 2.0

# screen pixels per pixel of a SubViewport shown through a SubViewportContainer; 0 when it is not shown that way
func _sv_factor(sv: SubViewport) -> float:
	var c := sv.get_parent() as SubViewportContainer
	if c == null or not c.is_visible_in_tree() or sv.size.x <= 0:
		return 0.0
	var cx := c.get_viewport().get_final_transform() * c.get_global_transform_with_canvas()
	return cx.x.length() * c.size.x / float(sv.size.x)

func _census() -> void:
	var root := get_tree().root
	var cs := (root.get_final_transform().x.length())
	var root_bounds := Rect2(Vector2.ZERO, Vector2(root.size))
	for n in root.find_children("*", "CanvasItem", true, false):
		var ci := n as CanvasItem
		if not ci.is_visible_in_tree():
			continue
		var vp := ci.get_viewport()
		var f := 1.0
		var bounds := root_bounds
		var tag := ""
		if vp != root:
			var sv := vp as SubViewport
			f = _sv_factor(sv) if sv != null else 0.0
			if f <= 0.0:
				continue  # offscreen content shown some other way: not measurable here
			bounds = Rect2(Vector2.ZERO, Vector2(sv.size))
			tag = " [sv]"
		var base := _entries(ci, bounds)
		var all := base.duplicate()
		if ci.material is ShaderMaterial:
			all.append_array(_shader_entries(ci, base))
		if all.is_empty():
			if n is Light2D or n is LightOccluder2D:
				skipped[n.get_class()] = skipped.get(n.get_class(), 0) + 1
			continue
		for e in all:
			var tex = e[0]
			var area: float = e[2] * f * f
			if area < 4.0:
				continue
			for t in [_real(tex)] + _extras(tex):
				if t == null:
					continue
				_record(t, e[1] * f / cs, area, e[3] + tag)

func _record(tex: Texture2D, kref: float, area: float, cls: String) -> void:
	var t := tex
	if t is AtlasTexture and t.atlas:
		t = t.atlas
	var path := t.resource_path
	if path == "" or not path.begins_with("res://"):
		return
	var tk: Dictionary = texk.get(path, {})
	if tk.is_empty():
		tk = {"w": t.get_width(), "h": t.get_height(), "k": 0.0, "area": 0.0, "n": 0, "src": {}, "where": []}
		texk[path] = tk
	tk["n"] += 1
	tk["area"] = maxf(tk["area"], area)
	if kref > tk["k"]:
		tk["k"] = kref
		tk["kwhere"] = where
	var s: Dictionary = tk["src"]
	s[cls] = maxf(s.get(cls, 0.0), kref)
	var wl: Array = tk["where"]
	var short := where.split(" ")[0]
	if not wl.has(short) and wl.size() < 12:
		wl.append(short)
