class_name InventorySlot
extends Control
## One inventory slot. Tap = select (tap again = use), long-press = drop.

signal tapped(index: int)
signal long_pressed(index: int)

const LONG_PRESS := 0.55

var index := 0
var item: ItemData
var count := 0
var selected := false
var use_progress := 0.0
var _down_t := -1.0
var _long_fired := false


func _ready() -> void:
	custom_minimum_size = Vector2(84, 84)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_content(p_item: ItemData, p_count: int, p_selected: bool, p_progress: float) -> void:
	item = p_item
	count = p_count
	selected = p_selected
	use_progress = p_progress
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_down_t = 0.0
			_long_fired = false
		else:
			if _down_t >= 0.0 and not _long_fired:
				tapped.emit(index)
			_down_t = -1.0
		accept_event()


func _process(delta: float) -> void:
	if _down_t >= 0.0:
		_down_t += delta
		if _down_t >= LONG_PRESS and not _long_fired:
			_long_fired = true
			long_pressed.emit(index)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var alpha := float(Settings.get_value("controls", "hud_opacity"))
	draw_style_box(UiTheme.box(Color(0.02, 0.025, 0.03, 0.6 * alpha), UiTheme.ACCENT if selected else UiTheme.LINE, 3 if selected else 1, 8), r)
	var font := get_theme_default_font()
	if item:
		var g := item.icon_glyph
		var fs := 34
		var col := item.color
		var tex := item.get_icon()
		if tex:
			draw_texture_rect(tex, Rect2(Vector2(8, 4), size - Vector2(16, 26)), false)
		else:
			var w := font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2((size.x - w) * 0.5, size.y * 0.55), g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		var n := tr(item.name_key)
		var nw := font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, Vector2(maxf(4.0, (size.x - nw) * 0.5), size.y - 8), n, HORIZONTAL_ALIGNMENT_LEFT, size.x - 8, 13, UiTheme.TEXT_DIM)
		if count > 1:
			draw_string(font, Vector2(size.x - 26, 22), "x%d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiTheme.TEXT)
	draw_string(font, Vector2(6, 18), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.TEXT_DIM)
	if use_progress > 0.0:
		draw_rect(Rect2(4, size.y - 6, (size.x - 8) * use_progress, 3), UiTheme.SUCCESS)
	if _down_t > 0.15 and not _long_fired and item:
		draw_rect(Rect2(4, 4, (size.x - 8) * clampf(_down_t / LONG_PRESS, 0, 1), 3), UiTheme.DANGER)
