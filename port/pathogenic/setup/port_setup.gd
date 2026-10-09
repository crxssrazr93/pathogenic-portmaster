extends MainLoop
## One-time PortMaster setup for Pathogenic on stock Godot 4.7. Run from the port folder:
##   godot --main-pack gamedata/pathogenic.pck --headless --script res://setup/port_setup.gd -- \
##     --out="$PWD" --pck="$PWD/gamedata/pathogenic.pck" --ui-scale=0.3333 --world-scale=0.1667
## res:// is read-only in pack mode, so files go to the absolute folder given by --out; the game
## later finds them through res:// because paths missing from the pack resolve from that folder.
## The step skips work already done, so an interrupted run can simply be restarted.
##
## textures   The Steam pack holds 3226 textures. 974 are BPTC (BC7) only: a Mali GPU cannot use that,
##            so Godot would have to unpack each to RGBA8 (4 bytes per pixel, 2.9 GB for all of them
##            at full size) and the import has no ETC2 fallback to pick instead. The other 2252 are
##            lossless WebP, which also becomes RGBA8 on the GPU. Every texture is therefore rewritten
##            as a plain .ctex in cache/textures/ (the format Godot itself imports to, raw RGBA8 or RGB8,
##            no mipmaps: the game's 2D filter never samples them) and its .import remap in the pack
##            repointed there, stored at the size it is drawn at on this screen. The UI is designed
##            for 1920x1080 and drawn at --ui-scale (the launcher passes the screen's scale, 1/3 at
##            640x480); the levels are drawn smaller still, as the camera zooms out to 0.3 to 0.36,
##            so world art is stored at --world-scale (half the UI scale, which leaves room for the
##            camera zooming in). UI_DIRS lists the art the UI shows. The .ctex header keeps the
##            original size, which Godot reports as the texture size (the mechanism of the importer's
##            own size limit), so sprite regions, atlases and frame grids, all in original pixels, are
##            unchanged. Small textures (below KEEP_BELOW) stay as they are.
##            The levels draw some art larger than that blanket scale: the wall pattern the shader tiles
##            over every wall, the tiled background, the player's body in the body editor. setup/drawn_sizes.tsv
##            lists such textures with the size they are drawn at, measured in the game (docs/PORTING.md,
##            build/make_drawn_table.py): "res://path<TAB>k", k being screen pixels per texture pixel at the
##            1920x1080 design size. A listed texture is stored at k * ui scale, between its default scale and
##            DRAWN_GAIN_MAX times that (a level loads all its art up front, so every listed texture
##            costs memory), and at most its original size.
##            Measured in the first level at 640x480 (PC): 485 MB of textures with a side of 512 or
##            more halved and the rest at full size, which the device ran out of memory on.
##            A run with other scales (another screen) converts everything again from the original
##            textures, which stay in the pack.
## The pack is patched in place (small .import texts appended); game data never leaves it.

const PckPatcher := preload("res://setup/pck_patcher.gd")

const DONE_MARKER := "cache/.setup_ok"
const CACHE := "cache/textures"
const KEEP_BELOW := 32  # longest side below which a texture keeps its size
const UI_DIRS: Array[String] = ["res://gfx/ui/", "res://gfx/player/mutations/", "res://gfx/player/evolutions/", "res://addons/"]
const SCALES_FILE := "cache/.texture_scales"
const DRAWN_TABLE := "setup/drawn_sizes.tsv"
const DRAWN_GAIN_MAX := 1.5  # a listed texture is stored at most this many times larger (per side) than its default
const IMPORTED := "res://.godot/imported/"
const MAX_SIDE := 4096  # no stored side above this (Mali GLES3 allows 8192, memory is the limit)
const STORE_WEBP := false  # lossless WebP instead of raw pixels: ~4x smaller files, ~3x slower setup
const SKIP_PREFIX := "res://test/"

var out_dir := ""
var pck_path := ""
var ui_scale := 1.0
var world_scale := 1.0
var pck := PckPatcher.new()
var drawn := {}  # source texture path -> k (drawn size relative to the 1920x1080 design)

# A plain MainLoop, not a SceneTree: Godot adds the project's autoloads to a SceneTree main loop
# after _init, and the game's autoloads load enough of the game to endanger a 1 GB device. A MainLoop
# script cannot set a success exit code (Godot 4 defaults to failure), so success is reported by the
# marker file DONE_MARKER, which the launcher checks.

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--pck="):
			pck_path = arg.trim_prefix("--pck=")
		elif arg.begins_with("--ui-scale="):
			ui_scale = clampf(arg.trim_prefix("--ui-scale=").to_float(), 0.05, 1.0)
		elif arg.begins_with("--world-scale="):
			world_scale = clampf(arg.trim_prefix("--world-scale=").to_float(), 0.05, 1.0)
	if out_dir == "" or pck_path == "":
		push_error("usage: -- --out=<port folder> --pck=<pathogenic.pck>")
		return
	DirAccess.remove_absolute(out_dir.path_join(DONE_MARKER))
	var err := pck.open(pck_path)
	if err != OK:
		push_error("cannot open %s for patching: %s" % [pck_path, error_string(err)])
		return
	var ok := convert_textures()
	pck.close()
	if ok:
		DirAccess.make_dir_recursive_absolute(out_dir.path_join("cache"))
		FileAccess.open(out_dir.path_join(DONE_MARKER), FileAccess.WRITE).store_string("ok\n")
	printerr("PORT_SETUP: ", "OK" if ok else "FAILED")

func _process(_delta: float) -> bool:
	return true  # all work happens in _initialize; end the main loop on the first frame

## Header of a .ctex file: {size, image_size, data_format, mipmaps, format, data_at}, or {} if it is not one.
func read_ctex(ctex_path: String) -> Dictionary:
	var f := FileAccess.open(ctex_path, FileAccess.READ)
	if f == null or f.get_buffer(4).get_string_from_ascii() != "GST2":
		return {}
	f.get_32()  # format version
	var size := Vector2i(f.get_32(), f.get_32())
	f.seek(36)  # flags, mipmap limit and 3 reserved fields of the texture header
	var data_format := f.get_32()
	var image_size := Vector2i(f.get_16(), f.get_16())  # padded to a multiple of 4 for VRAM compression
	var mipmaps := f.get_32()
	var format := f.get_32()
	return {"size": size, "image_size": image_size, "data_format": data_format, "mipmaps": mipmaps, "format": format, "data_at": f.get_position()}

## The full size base image of a .ctex straight from the pack: raw (VRAM compressed) data is
## unpacked to RGBA8, lossless WebP and PNG are decoded. Loading it as a Texture2D instead would
## keep several copies alive. Returns null for anything else.
func decode_ctex(ctex_path: String, ctex: Dictionary) -> Image:
	var f := FileAccess.open(ctex_path, FileAccess.READ)
	f.seek(ctex["data_at"])
	var img := Image.new()
	match ctex["data_format"]:
		0:
			var data := f.get_buffer(f.get_length() - f.get_position())
			img = Image.create_from_data(ctex["image_size"].x, ctex["image_size"].y, ctex["mipmaps"] > 0, ctex["format"], data)
			data = PackedByteArray()
			if img == null or img.is_empty():
				return null
			img.clear_mipmaps()
			if img.is_compressed() and img.decompress() != OK:
				return null
		1, 2:
			var data := f.get_buffer(f.get_32())
			var err := img.load_png_from_buffer(data) if ctex["data_format"] == 1 else img.load_webp_from_buffer(data)
			if err != OK:
				return null
		_:
			return null
	return img

## Writes a .ctex: header (reporting display_size), then the pixels raw or as lossless WebP.
func write_ctex(path: String, display_size: Vector2i, img: Image) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer("GST2".to_ascii_buffer())
	f.store_32(1)  # format version
	f.store_32(display_size.x)
	f.store_32(display_size.y)
	f.store_32(0)  # flags
	f.store_32(0xffffffff)  # mipmap limit: none
	f.store_32(0)
	f.store_32(0)
	f.store_32(0)
	f.store_32(2 if STORE_WEBP else 0)  # data format: WebP or raw image
	f.store_16(img.get_width())
	f.store_16(img.get_height())
	f.store_32(0)  # no mipmaps
	f.store_32(img.get_format())
	if STORE_WEBP:
		var data := img.save_webp_to_buffer(false)
		f.store_32(data.size())
		f.store_buffer(data)
	else:
		f.store_buffer(img.get_data())
	f.close()
	return true

## The table of drawn sizes: lines of "res://path<TAB>k", "#" starts a comment. Missing is fine (the
## blanket scales then apply to everything).
func load_drawn_table() -> void:
	drawn.clear()
	var text := FileAccess.get_file_as_string(out_dir.path_join(DRAWN_TABLE))
	for line in text.split("\n", false):
		if line.begins_with("#"):
			continue
		var kv := line.strip_edges(false, true).split("\t")
		if kv.size() >= 2 and kv[1].is_valid_float():
			drawn[kv[0]] = kv[1].to_float()
	printerr("PORT_SETUP: %d textures with a measured drawn size" % drawn.size())

func convert_textures() -> bool:
	DirAccess.make_dir_recursive_absolute(out_dir.path_join(CACHE))
	load_drawn_table()
	var path_re := RegEx.create_from_string('(?m)^(path(?:\\.[a-z0-9_]+)?)="([^"]+\\.ctex)"')
	var uid_re := RegEx.create_from_string('(?m)^uid="([^"]+)"')
	# textures stored for other scales are converted again
	var scales := "%.4f %.4f" % [ui_scale, world_scale]
	var scales_path := out_dir.path_join(SCALES_FILE)
	if FileAccess.get_file_as_string(scales_path).strip_edges() != scales:
		for f in DirAccess.get_files_at(out_dir.path_join(CACHE)):
			DirAccess.remove_absolute(out_dir.path_join(CACHE).path_join(f))
		FileAccess.open(scales_path, FileAccess.WRITE).store_string(scales + "\n")
	# textures to convert: [.import path in the pack, its text, original .ctex, header, scale]
	var todo := []
	for path in pck.entries:
		if not path.ends_with(".import") or ("res://" + path).begins_with(SKIP_PREFIX):
			continue
		var text := pck.read(path).get_string_from_utf8()
		var m := path_re.search(text) if text.contains('importer="texture"') else null
		if m == null:
			continue  # not a texture
		var original := m.get_string(2)
		if original.begins_with("res://cache/"):  # converted before: the original is still in the pack
			original = IMPORTED + original.get_file()
		var ctex := read_ctex(original)
		if ctex.is_empty():
			continue
		var res_path: String = "res://" + path
		var scale := world_scale
		for dir in UI_DIRS:
			if res_path.begins_with(dir):
				scale = ui_scale
		# measured drawn size (key: the source texture, the .import file without its suffix)
		var k: float = drawn.get(res_path.trim_suffix(".import"), 0.0)
		if k > 0.0:
			scale = minf(1.0, maxf(scale, minf(k * ui_scale, scale * DRAWN_GAIN_MAX)))
		todo.append([path, text, original, ctex, scale])
	var done := 0
	var reused := 0
	var failed := 0
	var stored := 0
	var stored_reused := 0
	var started := Time.get_ticks_msec()
	printerr("PORT_SETUP: %d textures to convert" % todo.size())
	for job in todo:
		var imported: String = job[2]
		var ctex: Dictionary = job[3]
		var name := imported.get_file()
		var target := out_dir.path_join(CACHE + "/" + name)
		var size: Vector2i = ctex["size"]
		# The cached file is named after the texture's path, so a game update that changes the
		# art keeps the name; <name>.src holds the MD5 of the original it was made from (from
		# the pack's directory), and a different one makes it again
		var src_md5 := pck.md5(imported.trim_prefix("res://"))
		if src_md5 == "":
			src_md5 = pck.md5(imported)
		# the scale it is stored at: small textures keep their size, nothing goes below KEEP_BELOW / 2
		# on the longest side or above MAX_SIDE
		var longest := maxi(size.x, size.y)
		var scale: float = job[4]
		if longest < KEEP_BELOW:
			scale = 1.0
		scale = minf(maxf(scale, KEEP_BELOW / 2.0 / longest), float(MAX_SIDE) / longest)
		# <name>.src holds the original's MD5 and the stored size, so a changed drawn size
		# (a new table entry, a new screen) converts that one texture again
		var stamp := "%s %dx%d" % [src_md5, maxi(1, ceili(size.x * minf(scale, 1.0))), maxi(1, ceili(size.y * minf(scale, 1.0)))]
		var cached_ok := FileAccess.file_exists(target) and (src_md5 == ""
			or FileAccess.get_file_as_string(target + ".src").strip_edges() == stamp)
		if not cached_ok:
			var img := decode_ctex(imported, ctex)
			if img == null:
				printerr("PORT_SETUP: skipped %s (unsupported format)" % job[0])
				failed += 1
				continue
			if scale < 1.0:
				img.resize(maxi(1, ceili(size.x * scale)), maxi(1, ceili(size.y * scale)), Image.INTERPOLATE_TRILINEAR)
			if img.get_format() == Image.FORMAT_RGBA8 and img.detect_alpha() == Image.ALPHA_NONE:
				img.convert(Image.FORMAT_RGB8)
			elif img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
				img.convert(Image.FORMAT_RGBA8)
			# written under a temporary name so an interrupted run never leaves a short file
			if not write_ctex(target + ".tmp", size, img):
				push_error("cannot write " + target)
				return false
			DirAccess.rename_absolute(target + ".tmp", target)
			if src_md5 != "":
				FileAccess.open(target + ".src", FileAccess.WRITE).store_string(stamp + "\n")
			stored += img.get_data().size()
			done += 1
		else:
			reused += 1
			stored_reused += FileAccess.open(target, FileAccess.READ).get_length()
		var new_text := '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n'
		var uid := uid_re.search(job[1])
		if uid:
			new_text += 'uid="%s"\n' % uid.get_string(1)
		new_text += 'path="res://%s/%s"\n' % [CACHE, name]
		pck.replace(job[0], new_text.to_utf8_buffer())
		if (done + reused) % 100 == 0:
			printerr("PORT_SETUP: textures %d of %d" % [done + reused, todo.size()])
	printerr("PORT_SETUP: textures converted=%d reused=%d failed=%d stored=%d MB (total in cache %d MB) in %d s" % [done, reused, failed, stored / 1048576, (stored + stored_reused) / 1048576, (Time.get_ticks_msec() - started) / 1000])
	return failed == 0
