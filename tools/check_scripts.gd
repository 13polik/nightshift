extends Node
## Compiles every GDScript under res://scripts and res://tests and reports failures.
##   godot --headless --path . res://tools/check_scripts.tscn

var failures := 0
var checked := 0


func _ready() -> void:
	for root in ["res://scripts", "res://tests", "res://tools"]:
		_walk(root)
	print("check_scripts: %d scripts, %d failed" % [checked, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _walk(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for d in dir.get_directories():
		_walk(path.path_join(d))
	for f in dir.get_files():
		if f.ends_with(".gd"):
			checked += 1
			var s: GDScript = load(path.path_join(f))
			if s == null or not s.can_instantiate() and not _is_abstract_ok(s):
				failures += 1
				printerr("FAILED: ", path.path_join(f))


func _is_abstract_ok(s: GDScript) -> bool:
	return s != null and s.is_tool() == false and s.get_instance_base_type() != &""
