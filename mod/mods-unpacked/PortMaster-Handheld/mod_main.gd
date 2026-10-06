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


func _init() -> void:
	var dir := ModLoaderMod.get_unpacked_dir().path_join(MOD_DIR).path_join("extensions")
	for path in EXTENSIONS:
		ModLoaderMod.install_script_extension(dir.path_join(path))


# The level start map (scn/ui/bodymap.tscn) pans by the viewport height times its `pos`, keyed
# for a 1080 high viewport. Screens taller than 16:9 (4:3 handhelds: 1920x1440) pan it further,
# which pushes the map up and leaves black below it. Its pan keys are scaled back to the 16:9
# height when it is added. (A script extension of bodymap.gd would load it, and the level configs
# it preloads, before the game is ready for them.)
func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node.name != "Bodymap" or not node is Control or not node.has_node("AnimationPlayer"):
		return
	var size: Vector2 = (node as Control).get_viewport_rect().size
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
