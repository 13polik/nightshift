class_name SettingsPanel
extends PanelContainer
## Settings UI shared by the main menu and the in-game pause menu. All changes apply
## immediately and persist through Settings / SaveManager.

signal closed

var _tabs: TabContainer


func _ready() -> void:
	theme = UiTheme.get_theme()
	custom_minimum_size = Vector2(760, 520)
	var v := VBoxContainer.new()
	add_child(v)
	var header := HBoxContainer.new()
	v.add_child(header)
	var title := UiTheme.label(tr("MENU_SETTINGS"), 32, UiTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := UiTheme.button(tr("UI_BACK"), 56)
	close.custom_minimum_size.x = 140
	close.pressed.connect(func() -> void: closed.emit())
	header.add_child(close)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tabs)
	_build_graphics()
	_build_audio()
	_build_controls()
	_build_gameplay()


func _page(title_key: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tr(title_key)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 14)
	scroll.add_child(v)
	return v


func _row(parent: Control, label_key: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := UiTheme.label(tr(label_key))
	l.custom_minimum_size.x = 300
	h.add_child(l)
	parent.add_child(h)
	return h


func _slider(parent: Control, label_key: String, section: String, key: String, min_v: float, max_v: float, step: float) -> void:
	var h := _row(parent, label_key)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = float(Settings.get_value(section, key))
	s.custom_minimum_size = Vector2(300, 44)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := UiTheme.label("%.2f" % s.value, UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	val.custom_minimum_size.x = 64
	s.value_changed.connect(func(x: float) -> void:
		val.text = "%.2f" % x
		Settings.set_value(section, key, x))
	h.add_child(s)
	h.add_child(val)


func _toggle(parent: Control, label_key: String, section: String, key: String) -> void:
	var h := _row(parent, label_key)
	var c := CheckButton.new()
	c.button_pressed = bool(Settings.get_value(section, key))
	c.custom_minimum_size = Vector2(80, 44)
	c.toggled.connect(func(on: bool) -> void: Settings.set_value(section, key, on))
	h.add_child(c)


func _options(parent: Control, label_key: String, items: Array, current: int, on_pick: Callable) -> void:
	var h := _row(parent, label_key)
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(260, 52)
	for it in items:
		o.add_item(tr(str(it)))
	o.selected = current
	o.item_selected.connect(on_pick)
	h.add_child(o)


func _build_graphics() -> void:
	var p := _page("SETTINGS_GRAPHICS")
	_options(p, "SETTINGS_QUALITY", ["QUALITY_LOW", "QUALITY_MEDIUM", "QUALITY_HIGH"], Settings.quality(),
		func(i: int) -> void: Settings.set_value("graphics", "quality", i))
	_slider(p, "SETTINGS_BRIGHTNESS", "graphics", "brightness", 0.7, 1.8, 0.05)
	_slider(p, "SETTINGS_RENDER_SCALE", "graphics", "render_scale", 0.6, 1.0, 0.05)
	_options(p, "SETTINGS_FPS", ["30", "60"], 0 if int(Settings.get_value("graphics", "fps_cap")) == 30 else 1,
		func(i: int) -> void: Settings.set_value("graphics", "fps_cap", 30 if i == 0 else 60))
	_toggle(p, "SETTINGS_SHOW_FPS", "graphics", "show_fps")


func _build_audio() -> void:
	var p := _page("SETTINGS_AUDIO")
	_slider(p, "SETTINGS_MASTER", "audio", "master", 0.0, 1.0, 0.05)
	_slider(p, "SETTINGS_MUSIC", "audio", "music", 0.0, 1.0, 0.05)
	_slider(p, "SETTINGS_SFX", "audio", "sfx", 0.0, 1.0, 0.05)
	_slider(p, "SETTINGS_AMBIENCE", "audio", "ambience", 0.0, 1.0, 0.05)
	_slider(p, "SETTINGS_UI_VOLUME", "audio", "ui", 0.0, 1.0, 0.05)


func _build_controls() -> void:
	var p := _page("SETTINGS_CONTROLS")
	_slider(p, "SETTINGS_LOOK_SENS", "controls", "look_sensitivity", 0.3, 2.5, 0.05)
	_toggle(p, "SETTINGS_INVERT_Y", "controls", "invert_y")
	_slider(p, "SETTINGS_JOYSTICK_SCALE", "controls", "joystick_scale", 0.7, 1.5, 0.05)
	_slider(p, "SETTINGS_BUTTON_SCALE", "controls", "button_scale", 0.7, 1.5, 0.05)
	_slider(p, "SETTINGS_HUD_OPACITY", "controls", "hud_opacity", 0.3, 1.0, 0.05)
	_toggle(p, "SETTINGS_LEFT_HANDED", "controls", "left_handed")
	_toggle(p, "SETTINGS_DYNAMIC_STICK", "controls", "dynamic_joystick")
	_toggle(p, "SETTINGS_SPRINT_TOGGLE", "controls", "sprint_toggle")
	_toggle(p, "SETTINGS_CROUCH_TOGGLE", "controls", "crouch_toggle")
	_toggle(p, "SETTINGS_HAPTICS", "controls", "haptics")
	_options(p, "SETTINGS_TOUCH_UI", ["TOUCH_AUTO", "TOUCH_ALWAYS", "TOUCH_NEVER"], int(Settings.get_value("controls", "touch_ui")),
		func(i: int) -> void: Settings.set_value("controls", "touch_ui", i))
	_slider(p, "SETTINGS_MOUSE_SENS", "controls", "mouse_sensitivity", 0.2, 3.0, 0.05)


func _build_gameplay() -> void:
	var p := _page("SETTINGS_GAMEPLAY")
	_slider(p, "SETTINGS_CAMERA_SHAKE", "gameplay", "camera_shake", 0.0, 1.0, 0.05)
	_toggle(p, "SETTINGS_HINTS", "gameplay", "show_hints")
	var langs: Array = []
	for l in Loc.SUPPORTED:
		langs.append(Loc.LANGUAGE_NAMES[l])
	_options(p, "SETTINGS_LANGUAGE", langs, maxi(0, Loc.SUPPORTED.find(Loc.current())),
		func(i: int) -> void: Loc.set_language(Loc.SUPPORTED[i]))
	# internet play: optional custom relay server (empty = the game's default server)
	var h := _row(p, "SETTINGS_RELAY")
	var e := LineEdit.new()
	e.placeholder_text = str(ProjectSettings.get_setting("nightshift/network/relay_url", "wss://"))
	e.text = str(Settings.get_value("network", "relay_url"))
	e.custom_minimum_size = Vector2(360, 52)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.text_submitted.connect(func(t: String) -> void: Settings.set_value("network", "relay_url", t.strip_edges()))
	e.focus_exited.connect(func() -> void: Settings.set_value("network", "relay_url", e.text.strip_edges()))
	h.add_child(e)
