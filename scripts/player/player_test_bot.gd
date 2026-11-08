class_name PlayerTestBot
extends Node
## Automation bot for multiplayer smoke tests (--ns-bot). Wanders along a few directions,
## toggles the flashlight and occasionally sprints so movement replication, noise and AI
## perception get exercised in headless runs.

var _t := 0.0
var _dir := Vector2(0, -1)
var _turn_t := 0.0


func move_vector() -> Vector2:
	return _dir


func _process(delta: float) -> void:
	_t += delta
	_turn_t -= delta
	if _turn_t <= 0.0:
		_turn_t = randf_range(1.5, 3.5)
		var a := randf() * TAU
		_dir = Vector2(cos(a), sin(a)) * randf_range(0.5, 1.0)
		var p: Node = get_parent()
		if randf() < 0.3:
			p.set("sprinting", true)
		else:
			p.set("sprinting", false)
		if randf() < 0.25:
			p.flashlight.set_on(not p.flashlight.on)
