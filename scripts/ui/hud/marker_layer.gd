class_name MarkerLayer
extends Control
## Screen-space markers for world positions (objectives, teammates, pings). Off-screen
## markers are clamped to the screen edge with a direction arrow.

var markers: Array[Dictionary] = [] # {pos: Vector3, color, label, icon}
var camera: Camera3D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if camera == null or not is_instance_valid(camera):
		return
	var vp := size
	var margin := 60.0
	if vp.x <= margin * 2.0 or vp.y <= margin * 2.0:
		return
	var font := get_theme_default_font()
	var alpha := float(Settings.get_value("controls", "hud_opacity"))
	for m: Dictionary in markers:
		var wp: Vector3 = m.pos
		var behind := camera.is_position_behind(wp)
		var sp := camera.unproject_position(wp)
		var on_screen := not behind and Rect2(Vector2(margin, margin), vp - Vector2(margin, margin) * 2.0).has_point(sp)
		var col: Color = m.get("color", UiTheme.ACCENT)
		col.a *= alpha
		if not on_screen:
			var center := vp * 0.5
			var dir := (sp - center)
			if behind:
				dir = -dir
			if dir.length() < 0.01:
				dir = Vector2(0, 1)
			dir = dir.normalized()
			var t := minf((vp.x * 0.5 - margin) / maxf(absf(dir.x), 0.001), (vp.y * 0.5 - margin) / maxf(absf(dir.y), 0.001))
			sp = center + dir * t
			var tip := sp + dir * 16.0
			var side := Vector2(-dir.y, dir.x) * 9.0
			draw_colored_polygon(PackedVector2Array([tip, sp + side, sp - side]), col)
		var r := 9.0
		var pts := PackedVector2Array([sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0)])
		draw_colored_polygon(pts, Color(0, 0, 0, 0.5 * alpha))
		draw_polyline(pts + PackedVector2Array([pts[0]]), col, 2.0, true)
		var cam_pos := camera.global_position
		var dist := cam_pos.distance_to(wp)
		var label := str(m.get("label", ""))
		var txt := ("%s  %dm" % [label, int(dist)]) if not label.is_empty() else "%dm" % int(dist)
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(font, sp + Vector2(-w * 0.5, -16), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
