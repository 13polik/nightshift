class_name TouchJoystick
extends Control
## Floating (or fixed) movement stick. Appears under the thumb inside the left zone;
## pushing past the outer ring auto-sprints if enabled.

const DEADZONE := 0.12

var radius := 80.0
var finger := -1
var origin := Vector2.ZERO
var knob := Vector2.ZERO
var rest_position := Vector2.ZERO
var dynamic := true
var value := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func begin(index: int, pos: Vector2) -> void:
	finger = index
	origin = pos if dynamic else rest_position
	_update(pos)


func drag(pos: Vector2) -> void:
	_update(pos)


func end() -> void:
	finger = -1
	value = Vector2.ZERO
	knob = Vector2.ZERO
	GameInput.touch_move = Vector2.ZERO
	queue_redraw()


func _update(pos: Vector2) -> void:
	var off := pos - origin
	if off.length() > radius:
		if dynamic:
			# drag the base along so the stick never "sticks" at the edge
			origin = pos - off.normalized() * radius
		off = off.limit_length(radius)
	knob = off
	var v := off / radius
	value = Vector2.ZERO if v.length() < DEADZONE else v * ((v.length() - DEADZONE) / (1.0 - DEADZONE)) / v.length()
	GameInput.touch_move = value
	queue_redraw()


func _draw() -> void:
	var alpha := float(Settings.get_value("controls", "hud_opacity"))
	var base := (origin if finger >= 0 else rest_position) - global_position
	draw_circle(base, radius, Color(0.02, 0.025, 0.03, 0.35 * alpha))
	draw_arc(base, radius, 0, TAU, 64, Color(0.8, 0.85, 0.9, 0.35 * alpha), 2.5, true)
	draw_circle(base + knob, radius * 0.42, Color(0.85, 0.88, 0.9, (0.55 if finger >= 0 else 0.3) * alpha))
