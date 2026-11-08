class_name TouchButton
extends Control
## Round touch button drawn in code (crisp at any DPI). Multi-touch input is routed by
## TouchControls, which calls press()/release(); mouse clicks work for desktop testing.

signal pressed_down
signal released_up

@export var action: StringName
@export var glyph: String = "?"
@export var label_key: String = ""
@export var radius: float = 52.0
@export var accent: Color = UiTheme.ACCENT_2

var is_pressed := false
var toggled_on := false
var progress := 0.0          # hold ring (interact)
var dimmed := false
var finger := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	size = custom_minimum_size


func center_global() -> Vector2:
	return global_position + size * 0.5


func hit(p: Vector2) -> bool:
	return visible and p.distance_to(center_global()) <= radius * 1.15


func press(index: int) -> void:
	if is_pressed:
		return
	finger = index
	is_pressed = true
	GameInput.touch_press(action)
	pressed_down.emit()
	if Settings.get_value("controls", "haptics") and Settings.is_mobile():
		Input.vibrate_handheld(15)
	queue_redraw()


func release() -> void:
	if not is_pressed:
		return
	is_pressed = false
	finger = -1
	GameInput.touch_release(action)
	released_up.emit()
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var alpha := float(Settings.get_value("controls", "hud_opacity"))
	var bg := Color(0.02, 0.025, 0.03, 0.55 * alpha)
	var ring := accent if (toggled_on or is_pressed) else Color(0.75, 0.8, 0.85, 0.5 * alpha)
	if dimmed:
		ring = Color(0.5, 0.5, 0.5, 0.25 * alpha)
	draw_circle(c, radius * (0.94 if is_pressed else 1.0), bg)
	draw_arc(c, radius, 0, TAU, 48, ring, 3.0 if not toggled_on else 4.5, true)
	if progress > 0.0:
		draw_arc(c, radius - 6.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, UiTheme.ACCENT, 7.0, true)
	var font := get_theme_default_font()
	var fs := int(radius * 0.62)
	var text_col := Color(1, 1, 1, (0.4 if dimmed else 0.95) * alpha)
	var gw := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	draw_string(font, c + Vector2(-gw * 0.5, fs * 0.35), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_col)
	if not label_key.is_empty():
		var t := tr(label_key)
		var ls := 15
		var lw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, -1, ls).x
		draw_string(font, c + Vector2(-lw * 0.5, radius + 18.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, ls, Color(0.85, 0.88, 0.9, 0.75 * alpha))
