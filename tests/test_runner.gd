extends Node
## Test entry point:
##   godot --headless --fixed-fps 60 --path . res://tests/test_runner.tscn [-- --ns-test=<filter>]
## Runs every tests/unit/test_*.gd, then tests/integration/test_*.gd. Exit code = number of
## failed tests (0 = success).

var total := 0
var failed := 0


func _ready() -> void:
	Log.min_level = Log.Level.INFO
	await get_tree().process_frame
	var filter := CmdArgs.value("test")
	for folder in ["res://tests/unit", "res://tests/integration"]:
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		var files := Array(dir.get_files()).filter(func(f: String) -> bool: return f.begins_with("test_") and f.ends_with(".gd"))
		files.sort()
		for f: String in files:
			if not filter.is_empty() and not f.contains(filter):
				continue
			await _run_file(folder.path_join(f))
	print("")
	print("==== TESTS: %d run, %d failed ====" % [total, failed])
	get_tree().quit(failed)


func _run_file(path: String) -> void:
	var script: GDScript = load(path)
	if script == null:
		failed += 1
		print("[FAIL] could not load %s" % path)
		return
	var tc: TestCase = script.new()
	tc.runner = self
	for m in script.get_script_method_list():
		var mname: String = m.name
		if not mname.begins_with("test_"):
			continue
		total += 1
		tc.current_test = "%s::%s" % [path.get_file().get_basename(), mname]
		tc.failures.clear()
		await tc.before_each()
		var t0 := Time.get_ticks_msec()
		await tc.call(mname)
		await tc.after_each()
		var ms := Time.get_ticks_msec() - t0
		if tc.failures.is_empty():
			print("[ OK ] %s (%d ms)" % [tc.current_test, ms])
		else:
			failed += 1
			print("[FAIL] %s" % tc.current_test)
			for f in tc.failures:
				print("         - %s" % f)
