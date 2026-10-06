extends RefCounted
## In-place patcher for Godot 4.4+ packs (format 3 and 4, directory at the offset the header
## gives), after pck_patch.py from Knifethrower/PM-Porting-Tools (0BSD). Replacement data is
## appended at the end of the pack and the file's directory entry (offset, size, MD5)
## repointed; the directory itself never changes size, so only existing paths can be replaced.

const FLAG_ENCRYPTED := 1
const FLAG_REL_FILEBASE := 2

var file: FileAccess
var base := 0
var relative := false
var entries := {}  # res path -> position of its (offset u64, size u64, md5) record

func open(path: String) -> Error:
	file = FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		return FileAccess.get_open_error()
	if file.get_buffer(4).get_string_from_ascii() != "GDPC":
		return ERR_FILE_UNRECOGNIZED
	var version := file.get_32()
	if version < 3:
		return ERR_FILE_UNRECOGNIZED
	file.seek(20)
	var flags := file.get_32()
	if flags & FLAG_ENCRYPTED:
		return ERR_UNAUTHORIZED
	relative = flags & FLAG_REL_FILEBASE != 0
	base = file.get_64()
	file.seek(file.get_64())  # directory offset
	for i in file.get_32():
		var n := file.get_32()
		var name := file.get_buffer(n).get_string_from_utf8()
		entries[name] = file.get_position()
		file.seek(file.get_position() + 16 + 16 + 4)
	return OK

func read(path: String) -> PackedByteArray:
	file.seek(entries[path])
	var off := file.get_64()
	var size := file.get_64()
	file.seek(off + (base if relative else 0))
	return file.get_buffer(size)

func replace(path: String, data: PackedByteArray) -> void:
	file.seek_end()
	var end := file.get_position()
	var pad := (16 - end % 16) % 16
	for i in pad:
		file.store_8(0)
	file.store_buffer(data)
	var md5 := HashingContext.new()
	md5.start(HashingContext.HASH_MD5)
	md5.update(data)
	file.seek(entries[path])
	file.store_64(end + pad - (base if relative else 0))
	file.store_64(data.size())
	file.store_buffer(md5.finish())

func close() -> void:
	file.flush()
	file = null
