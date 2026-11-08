class_name TestCase
extends RefCounted
## Minimal test base. Methods starting with "test_" are run by TestRunner; they may be
## coroutines (await). Assertions record failures instead of aborting the suite.

var runner: Node
var failures: PackedStringArray = PackedStringArray()
var current_test := ""


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func check(cond: bool, message: String) -> bool:
	if not cond:
		failures.append("%s: %s" % [current_test, message])
	return cond


func eq(a: Variant, b: Variant, message: String) -> bool:
	return check(a == b, "%s (expected %s, got %s)" % [message, str(b), str(a)])


func tree() -> SceneTree:
	return runner.get_tree()


func wait_frames(n: int) -> void:
	for i in n:
		await tree().physics_frame


func wait_seconds(s: float) -> void:
	await tree().create_timer(s, true, true).timeout
