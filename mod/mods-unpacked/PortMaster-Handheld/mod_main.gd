extends Node
# PortMaster port changes for handhelds (the launcher starts the game with SteamDeck=1, so a new
# install also starts on the largest text size). Each extension explains itself.

const MOD_DIR := "PortMaster-Handheld"
const EXTENSIONS := [
	"scn/globals.gd",
	"scn/text_scale_manager.gd",
	"scn/ui/shader_loader.gd",
	"scn/ui/start_menus/slime_shader.gd",
]
const MINIMAP_SCRIPT := "res://scn/ui/minimap.gd"
const PLAYER_MINIMAP_SCRIPT := "res://scn/ui/player_minimap.gd"
const HUD_SCENE := "res://scn/ui/ui.tscn"
const STAMINA_SCRIPT := "res://scn/ui/stamina_bar.gd"
const CELL_SELECTION_SCENE := "res://scn/ui/start_menus/player_selection_menu.tscn"
const INFO_PANEL_SCALE := 1.3
const MINIMAP_ALPHA := 0.9
const TEXT_OUTLINE := 6  # design pixels, 2 on a 640x480 screen
const EDITOR_SCRIPT := "res://scn/ui/editor.gd"
const HUD_MAP_EVERY := 2  # frames between minimap redraws

## Screen pixels per design unit (the game is laid out for 1920x1080 and stretched with
## canvas_items, so 1/3 at 640x480 and 0.375 at 720x720).
static func screen_scale(tree: SceneTree) -> float:
	var root := tree.root
	var view := root.get_visible_rect().size
	return float(root.size.x) / view.x if view.x > 0.0 else 1.0

## How much the camera zooms in on small screens: the play area as large as on an 800 wide
## screen, at most 1.25x (picked on the RG35XX H after trying 1.5 and 1.75). 640x480 1.25,
## 720x720 1.11, 1.0 from 800 wide up.
static func handheld_zoom(tree: SceneTree) -> float:
	return clampf((5.0 / 12.0) / screen_scale(tree), 1.0, 1.25)

## How much larger the HUD is drawn, as a fraction of its design size on screen: 640x480 1.75 for
## the minimap (top right), 1.4 for the player minimap (top left), 1.5 for the DNA and health
## bars and the stamina wheel. Picked on the RG35XX H.
static func hud_scale(tree: SceneTree, design_fraction: float) -> float:
	return clampf(design_fraction / screen_scale(tree), 1.0, 2.0)


var _shrink := 1
var _zoom := 1.0
var _hud_map := 1.0
var _hud_body := 1.0
var _hud_bottom := 1.0
var _minimap: Control
var _light_count := 0
var _editor: Control
var _molecules_set := Vector2.INF
var _map_views: Array[SubViewport] = []
var _frame := 0


func _init() -> void:
	var dir := ModLoaderMod.get_unpacked_dir().path_join(MOD_DIR).path_join("extensions")
	for path in EXTENSIONS:
		ModLoaderMod.install_script_extension(dir.path_join(path))


func _ready() -> void:
	_shrink = int(floor(1.0 / screen_scale(get_tree()) + 0.01))
	_zoom = handheld_zoom(get_tree())
	_hud_map = hud_scale(get_tree(), 1.75 / 3.0)
	_hud_body = hud_scale(get_tree(), 1.4 / 3.0)
	_hud_bottom = hud_scale(get_tree(), 0.5)
	get_tree().node_added.connect(_on_node_added)
	# the main menu is already up when the mods start
	for vp in get_tree().root.find_children("*", "SubViewport", true, false):
		if vp.get_parent() is SubViewportContainer or vp.get_parent() is TextureRect:
			_fit_viewport.call_deferred(vp)
	process_physics_priority = 1000  # after the editor's own _physics_process


func _on_node_added(node: Node) -> void:
	if node.name == "Bodymap" and node is Control and node.has_node("AnimationPlayer"):
		_fix_bodymap_pan(node)
	if node is SubViewport and (node.get_parent() is SubViewportContainer or node.get_parent() is TextureRect):
		_fit_viewport.call_deferred(node)
	if node is GPUParticles2D and node.scene_file_path.get_file().begins_with("particle_light"):
		_thin_light(node)
	var sc2: Script = node.get_script()
	if sc2 and sc2.resource_path == MINIMAP_SCRIPT and node is Control:
		_minimap = node
		node.scale = Vector2.ONE * _hud_map
		if _hud_map > 1.0:  # its resting opacity from the scene was hard to read on a small screen
			node.modulate.a = maxf(node.modulate.a, MINIMAP_ALPHA)
		_add_map_views.call_deferred(node)
	if sc2 and sc2.resource_path == PLAYER_MINIMAP_SCRIPT and node is Control and _hud_body > 1.0:
		node.scale = Vector2.ONE * _hud_body  # top left, pivot at its corner
	if sc2 and sc2.resource_path == PLAYER_MINIMAP_SCRIPT and node is Control:
		_add_map_views.call_deferred(node)
	if node is VBoxContainer and node.name == "VBoxContainer" and node.get_parent() is MarginContainer \
			and node.owner and node.owner.scene_file_path == HUD_SCENE and node.get_parent().get_parent() == node.owner \
			and _hud_bottom > 1.0:
		_scale_bars(node)
	if sc2 and sc2.resource_path == STAMINA_SCRIPT and node is CanvasItem and _hud_bottom > 1.0:
		node.scale *= _hud_bottom  # the stamina wheel by the player
	if sc2 and sc2.resource_path == EDITOR_SCRIPT:
		_editor = node
	if node.owner and node.owner.scene_file_path == CELL_SELECTION_SCENE and _shrink >= 2:
		if node is PanelContainer and node.name == "InfoPanel":
			_scale_in_container(node, INFO_PANEL_SCALE, Vector2(0.5, 0.0))
		elif node is RichTextLabel and node.get_parent().get_parent().name == "InfoPanel":
			node.add_theme_constant_override("outline_size", TEXT_OUTLINE)
			node.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.12, 0.9))


# The two minimaps (the room map top right, the body top left) each draw the whole level again
# through their own SubViewport: on an H700 that was about 4 ms a frame (26 fps in a quiet room,
# 30 without them). They are redrawn every second frame, and every frame while the map is open.
func _add_map_views(map: Control) -> void:
	if not is_instance_valid(map):
		return
	for vp in map.find_children("*", "SubViewport", true, false):
		_map_views.append(vp)


func _process(_delta: float) -> void:
	_frame += 1
	for i in range(_map_views.size() - 1, -1, -1):
		var vp := _map_views[i]
		if not is_instance_valid(vp):
			_map_views.remove_at(i)
			continue
		var map := vp.get_parent().get_parent() as Control
		if not map or not map.is_visible_in_tree():
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		elif map == _minimap and _minimap.get("expanded"):
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		elif _frame % HUD_MAP_EVERY == 0:
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		elif vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


# The body editor's view renders at the screen's size with its layout kept at the design size
# (_fit_viewport). editor.gd centres the molecules behind the body on %SubViewport.size, the
# rendered size, in its _physics_process; this runs after it and moves them to the centre of the
# design size whenever the game has positioned them again. (editor.gd declares a global class,
# which a script extension cannot replace.)
func _physics_process(_delta: float) -> void:
	_scale_minimap()
	if not is_instance_valid(_editor) or not _editor.is_visible_in_tree():
		return
	var molecules := _editor.get_node_or_null("%Molecules") as Node2D
	var vp := _editor.get_node_or_null("%SubViewport") as SubViewport
	if not molecules or not vp or vp.size_2d_override == Vector2i.ZERO:
		return
	if molecules.position != _molecules_set:
		molecules.position += (Vector2(vp.size_2d_override) - Vector2(vp.size)) / 2.0
		_molecules_set = molecules.position


# The level start map (scn/ui/bodymap.tscn) pans by the viewport height times its `pos`, keyed
# for a 1080 high viewport. Screens taller than 16:9 (4:3 handhelds: 1920x1440) pan it further,
# which pushes the map up and leaves black below it. Its pan keys are scaled back to the 16:9
# height when it is added. (A script extension of bodymap.gd would load it, and the level configs
# it preloads, before the game is ready for them.)
func _fix_bodymap_pan(node: Control) -> void:
	var size: Vector2 = node.get_viewport_rect().size
	var k: float = size.x * 9.0 / 16.0 / size.y
	if k >= 1.0:
		return
	var player: AnimationPlayer = node.get_node("AnimationPlayer")
	for anim_name in player.get_animation_list():
		var anim := player.get_animation(anim_name)
		if anim.has_meta("port_pan_scale"):  # shared by every instance of the scene
			continue
		anim.set_meta("port_pan_scale", k)
		var t := anim.find_track(NodePath(".:pos"), Animation.TYPE_VALUE)
		for i in (anim.track_get_key_count(t) if t != -1 else 0):
			anim.track_set_key_value(t, i, anim.track_get_key_value(t, i) * k)


# Offscreen views (minimaps, the body editor, the DNA panels, the menu's CRT screen) render in
# SubViewports at the design size, 1920x1440 for the editor, and are then drawn at a third of
# that on a 640x480 screen. Each one shown through a SubViewportContainer renders at the size it
# is shown instead: the container stretches it and divides its resolution by the screen's whole
# factor (3 at 640x480, 2 at 720x720), and size_2d_override keeps the content laid out at the
# design size, input included. (A larger shown HUD element gets a smaller factor, or none.)
# A viewport the same size as its container gets that directly; a different sized one (drawn at
# its own size) is rendered smaller and its container scaled up.
# One shown by a TextureRect (the menu's 1920x1080 CRT screen) just renders smaller: the
# TextureRect stretches its texture to its own size anyway.
# They also drop HDR 2D (16-bit float buffers, slow on handheld GPUs).
func _fit_viewport(vp: SubViewport) -> void:
	if _shrink < 2 or not is_instance_valid(vp) or not vp.is_inside_tree() or vp.has_meta("port_fit"):
		return
	# the screen's factor, times any scale of the node showing it (the enlarged minimaps)
	var shown_by := vp.get_parent() as Control
	var px := screen_scale(get_tree()) * shown_by.get_global_transform_with_canvas().get_scale().x
	var shrink := int(floor(1.0 / px + 0.01))
	vp.use_hdr_2d = false
	if shrink < 2:
		return
	if vp.get_parent() is TextureRect:
		if vp.size_2d_override == Vector2i.ZERO:
			vp.set_meta("port_fit", true)
			vp.use_hdr_2d = false
			var design := vp.size
			vp.size_2d_override_stretch = true
			vp.size_2d_override = design
			vp.size = Vector2i((Vector2(design) / shrink).ceil())
		return
	var c := vp.get_parent() as SubViewportContainer
	if not c or vp.size_2d_override != Vector2i.ZERO or (c.stretch and c.stretch_shrink != 1):
		return  # already scaled by the game (or by this mod)
	var cs := Vector2i(c.size.round())
	if cs.x <= 0 or cs.y <= 0:
		c.resized.connect(_fit_viewport.bind(vp), CONNECT_ONE_SHOT)
		return
	# 3D content (the DNA helix) follows the viewport size by itself, and its scripts project
	# positions with the real size, so it gets no 2D override (cameras of viewports nested
	# inside, like the helix inside the editor, do not count)
	var has_3d := vp.find_children("*", "Camera3D", true, false).any(func(cam: Node) -> bool: return cam.get_viewport() == vp)
	if c.stretch or (absi(vp.size.x - cs.x) <= 2 and absi(vp.size.y - cs.y) <= 2):
		vp.set_meta("port_fit", true)
		vp.use_hdr_2d = false
		c.stretch = true
		c.stretch_shrink = shrink
		if not has_3d:
			vp.size_2d_override_stretch = true
			vp.size_2d_override = cs
			c.resized.connect(func() -> void:
				if is_instance_valid(vp):
					vp.size_2d_override = Vector2i(c.size.round()))
	elif not has_3d and not c.get_parent() is Container:
		vp.set_meta("port_fit", true)
		vp.use_hdr_2d = false
		var full := vp.size
		vp.size_2d_override_stretch = true
		vp.size_2d_override = full
		vp.size = Vector2i((Vector2(full) / shrink).ceil())
		c.scale *= shrink


# The ambient light motes (particle_light*.tscn) are the largest group of particle emitters:
# about 135 in a level, each a separate GPU pass every frame on the Compatibility renderer. Two of
# every three are removed.
func _thin_light(node: GPUParticles2D) -> void:
	_light_count += 1
	if _light_count % 3 != 0:
		node.queue_free.call_deferred()


# The HUD is drawn larger on small screens (hud_scale): the minimap (top right, about its top
# right corner, more opaque; back to its own size while expanded to the full screen) by
# _hud_map, the player minimap (top left) by _hud_body, the DNA and health bars (bottom left)
# and the stamina wheel that follows the player by _hud_bottom. The bars sit in a
# MarginContainer, whose layout resets their scale, so it is set again after every sort.
func _scale_minimap() -> void:
	if not is_instance_valid(_minimap) or _hud_map <= 1.0:
		return
	var target := 1.0 if _minimap.get("expanded") else _hud_map
	_minimap.pivot_offset = Vector2(_minimap.size.x, 0.0)
	_minimap.scale = _minimap.scale.lerp(Vector2.ONE * target, 0.2)


# The cell selection screen's description (top centre) is white text on a light panel: drawn
# larger and outlined in dark blue on small screens.
func _scale_in_container(c: Control, k: float, pivot: Vector2) -> void:
	var apply := func() -> void:
		if is_instance_valid(c):
			c.pivot_offset = c.size * pivot
			c.scale = Vector2.ONE * k
	c.get_parent().sort_children.connect(apply)
	c.resized.connect(apply)
	apply.call()


func _scale_bars(bars: VBoxContainer) -> void:
	var apply := func() -> void:
		if is_instance_valid(bars):
			bars.pivot_offset = Vector2(0.0, bars.size.y)
			bars.scale = Vector2.ONE * _hud_bottom
	bars.get_parent().sort_children.connect(apply)
	bars.resized.connect(apply)
	apply.call()
