class_name UiTheme
extends RefCounted
## Builds the shared UI Theme in code (single source of truth for colours and metrics).
## A designer-made .tres theme at res://resources/ui_theme.tres takes precedence if present.

const BG := Color(0.035, 0.04, 0.05, 0.94)
const PANEL := Color(0.07, 0.08, 0.095, 0.92)
const PANEL_LIGHT := Color(0.12, 0.135, 0.155, 0.95)
const LINE := Color(0.22, 0.25, 0.28, 1.0)
const TEXT := Color(0.86, 0.89, 0.91)
const TEXT_DIM := Color(0.55, 0.6, 0.64)
const ACCENT := Color(0.95, 0.64, 0.24)      # warning amber: objectives / primary actions
const ACCENT_2 := Color(0.36, 0.78, 0.82)    # cool cyan: teammates / info
const DANGER := Color(0.86, 0.23, 0.18)
const SUCCESS := Color(0.42, 0.8, 0.45)

const FONT_SIZE := 22
const FONT_SMALL := 17
const FONT_TITLE := 46

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme:
		return _theme
	if ResourceLoader.exists("res://resources/ui_theme.tres"):
		_theme = load("res://resources/ui_theme.tres")
		return _theme
	var t := Theme.new()
	t.default_font_size = FONT_SIZE
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Roboto Condensed", "Bahnschrift", "Segoe UI", "Helvetica Neue", "Roboto", "Noto Sans", "sans-serif"])
	font.font_weight = 500
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	t.default_font = font

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM * Color(1, 1, 1, 0.6))
	t.set_color("font_focus_color", "Button", Color.WHITE)

	t.set_stylebox("normal", "Button", box(PANEL_LIGHT, LINE, 1, 6))
	t.set_stylebox("hover", "Button", box(PANEL_LIGHT.lightened(0.08), ACCENT * Color(1, 1, 1, 0.7), 1, 6))
	t.set_stylebox("pressed", "Button", box(PANEL_LIGHT.darkened(0.2), ACCENT, 2, 6))
	t.set_stylebox("disabled", "Button", box(PANEL * Color(1, 1, 1, 0.6), LINE * Color(1, 1, 1, 0.5), 1, 6))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), ACCENT, 2, 6))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, LINE, 1, 8))
	t.set_stylebox("panel", "Panel", box(PANEL, LINE, 1, 8))

	t.set_stylebox("normal", "LineEdit", box(Color(0.02, 0.025, 0.03, 0.95), LINE, 1, 6))
	t.set_stylebox("focus", "LineEdit", box(Color(0.02, 0.025, 0.03, 0.95), ACCENT, 2, 6))
	t.set_color("font_color", "LineEdit", TEXT)

	var bar_bg := box(Color(0, 0, 0, 0.55), LINE, 1, 3)
	var bar_fill := box(ACCENT, Color(0, 0, 0, 0), 0, 3)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", TEXT)

	t.set_stylebox("slider", "HSlider", box(Color(0, 0, 0, 0.6), LINE, 1, 3, 4))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT * Color(1, 1, 1, 0.8), Color(0, 0, 0, 0), 0, 3, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, Color(0, 0, 0, 0), 0, 3, 4))

	t.set_stylebox("tab_selected", "TabBar", box(PANEL_LIGHT, ACCENT, 0, 4, 0, 2))
	t.set_stylebox("tab_unselected", "TabBar", box(PANEL, LINE, 0, 4))
	t.set_stylebox("tab_hovered", "TabBar", box(PANEL_LIGHT, LINE, 0, 4))
	t.set_stylebox("panel", "TabContainer", box(PANEL, LINE, 1, 8))
	t.set_stylebox("tab_selected", "TabContainer", box(PANEL_LIGHT, ACCENT, 0, 4, 0, 2))
	t.set_stylebox("tab_unselected", "TabContainer", box(PANEL, LINE, 0, 4))
	t.set_stylebox("tab_hovered", "TabContainer", box(PANEL_LIGHT, LINE, 0, 4))
	t.set_color("font_selected_color", "TabContainer", ACCENT)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)

	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_stylebox("panel", "PopupMenu", box(PANEL, LINE, 1, 6))
	t.set_stylebox("normal", "OptionButton", box(PANEL_LIGHT, LINE, 1, 6))
	t.set_stylebox("hover", "OptionButton", box(PANEL_LIGHT.lightened(0.08), ACCENT, 1, 6))
	t.set_stylebox("pressed", "OptionButton", box(PANEL_LIGHT, ACCENT, 1, 6))
	_theme = t
	return t


static func box(bg: Color, border: Color, border_w: int = 1, radius: int = 6, content_margin: int = 12, bottom_border: int = -1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	if bottom_border >= 0:
		s.border_width_bottom = bottom_border
	s.set_corner_radius_all(radius)
	s.content_margin_left = content_margin
	s.content_margin_right = content_margin
	s.content_margin_top = content_margin * 0.6
	s.content_margin_bottom = content_margin * 0.6
	s.anti_aliasing = true
	return s


static func label(text: String, size: int = FONT_SIZE, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, min_height: int = 64) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_height)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func() -> void: Audio.play_ui("ui_click"))
	return b


static func primary_button(text: String, min_height: int = 72) -> Button:
	var b := button(text, min_height)
	b.add_theme_stylebox_override("normal", box(ACCENT * Color(0.85, 0.85, 0.85, 1), ACCENT, 1, 6))
	b.add_theme_stylebox_override("hover", box(ACCENT, Color.WHITE * Color(1, 1, 1, 0.6), 1, 6))
	b.add_theme_stylebox_override("pressed", box(ACCENT.darkened(0.25), ACCENT, 2, 6))
	b.add_theme_color_override("font_color", Color(0.06, 0.05, 0.03))
	b.add_theme_color_override("font_hover_color", Color(0.02, 0.02, 0.02))
	b.add_theme_color_override("font_pressed_color", Color(0.02, 0.02, 0.02))
	b.add_theme_font_size_override("font_size", 26)
	return b


## Root Control filling the screen inside the device safe area (notches, rounded corners).
static func safe_area_margin() -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	apply_safe_area(m)
	return m


static func apply_safe_area(m: MarginContainer, extra: int = 24) -> void:
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	var vp_size := m.get_viewport_rect().size if m.is_inside_tree() else Vector2(1280, 720)
	var left := extra
	var right := extra
	var top := extra
	var bottom := extra
	if screen.x > 0 and safe.size.x > 0 and DisplayServer.get_name() != "headless":
		var sx := vp_size.x / float(screen.x)
		var sy := vp_size.y / float(screen.y)
		left += int(safe.position.x * sx)
		top += int(safe.position.y * sy)
		right += int((screen.x - safe.end.x) * sx)
		bottom += int((screen.y - safe.end.y) * sy)
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_bottom", bottom)
