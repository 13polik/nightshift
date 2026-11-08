class_name LocalSaveBackend
extends SaveBackend
## Atomic local file storage under user://save/. Each write goes to a temp file first and
## the previous good file is kept as .bak so a crash mid-write cannot destroy progress.

var root: String = "user://save"


func _init(p_root: String = "user://save") -> void:
	root = p_root
	DirAccess.make_dir_recursive_absolute(root)


func _path(key: String) -> String:
	return "%s/%s.json" % [root, key.validate_filename()]


func read_text(key: String) -> String:
	return _read_file(_path(key))


func read_backup(key: String) -> String:
	return _read_file(_path(key) + ".bak")


func write_text(key: String, text: String) -> bool:
	var path := _path(key)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		Log.e("save", "cannot open %s: %s" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(text)
	f.flush()
	f.close()
	if FileAccess.file_exists(path):
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		Log.e("save", "rename failed for %s: %s" % [path, error_string(err)])
		return false
	return true


func exists(key: String) -> bool:
	return FileAccess.file_exists(_path(key))


func remove(key: String) -> void:
	for p in [_path(key), _path(key) + ".bak", _path(key) + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func describe() -> String:
	return "local:" + ProjectSettings.globalize_path(root)


func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()
