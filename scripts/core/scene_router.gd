extends Node
## Scene flow + global overlay (autoload "Router"): loading screen, toasts and modal
## dialogs survive scene changes. Also handles session loss from anywhere in the game.

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const LOBBY := "res://scenes/ui/lobby.tscn"
const MISSION := "res://scenes/missions/mission.tscn"
const RESULTS := "res://scenes/ui/results.tscn"
const INTRO := "res://scenes/ui/intro.tscn"

var last_results: Dictionary = {}
## Main-menu page to open when the intro finishes ("" = home).
var after_intro_page := ""
var _overlay: CanvasLayer
var _toast_box: VBoxContainer
var _loading: Control
var _loading_label: Label
var _dialog_layer: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()
	Events.toast_requested.connect(_show_toast)
	Events.dialog_requested.connect(func(title_key: String, body: String, _kind: int) -> void: show_dialog(title_key, body))
	Net.session_lost.connect(_on_session_lost)
	Net.connection_failed.connect(func(reason: String) -> void: show_dialog("DIALOG_CONNECTION_TITLE", tr(reason)))


## Automation (--ns-screenshot=<file.png>@<sec>[,<file2.png>@<sec>]): save viewport captures.
func schedule_screenshots(spec: String) -> void:
	for part in spec.split(",", false):
		var bits := part.split("@")
		if bits.size() != 2:
			continue
		var path := bits[0]
		get_tree().create_timer(float(bits[1]), true).timeout.connect(func() -> void:
			var img := get_viewport().get_texture().get_image()
			var err := img.save_png(path)
			Log.i("router", "screenshot %s (%s)" % [path, error_string(err)]))


## Automation: quit after `seconds` regardless of scene changes.
func schedule_quit(seconds: float) -> void:
	get_tree().create_timer(seconds, true).timeout.connect(_quit_now)


func _quit_now() -> void:
	Log.i("router", "quit-after reached - exiting")
	Net.leave(false)
	get_tree().quit(0)


func go_main_menu() -> void:
	_change(MAIN_MENU)


func go_intro() -> void:
	_change(INTRO)


func go_lobby() -> void:
	_change(LOBBY)


func go_mission() -> void:
	show_loading("LOADING_MISSION")
	_change.call_deferred(MISSION)


func go_results(results: Dictionary) -> void:
	last_results = results
	_change(RESULTS)


func _change(path: String) -> void:
	if not ResourceLoader.exists(path):
		Log.e("router", "missing scene %s" % path)
		show_dialog("DIALOG_ERROR_TITLE", tr("ERR_MISSING_ASSET") + "\n" + path)
		if path != MAIN_MENU:
			_change(MAIN_MENU)
		return
	get_tree().paused = false
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		Log.e("router", "change_scene failed %s: %s" % [path, error_string(err)])
		show_dialog("DIALOG_ERROR_TITLE", tr("ERR_MISSING_ASSET"))
		if path != MAIN_MENU:
			_change(MAIN_MENU)


func _on_session_lost(reason_key: String) -> void:
	GameInput.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hide_loading()
	go_main_menu()
	show_dialog("DIALOG_CONNECTION_TITLE", tr(reason_key))


# --- overlay --------------------------------------------------------------------------

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	add_child(_overlay)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	_overlay.add_child(root)

	_loading = ColorRect.new()
	(_loading as ColorRect).color = Color(0.01, 0.012, 0.015, 1)
	_loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.visible = false
	root.add_child(_loading)
	_loading_label = UiTheme.label("", 28, UiTheme.TEXT_DIM)
	_loading_label.set_anchors_preset(Control.PRESET_CENTER)
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading.add_child(_loading_label)

	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_box.position.y = 90
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast_box)

	_dialog_layer = Control.new()
	_dialog_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialog_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_dialog_layer)


func show_loading(text_key: String) -> void:
	_loading_label.text = tr(text_key)
	_loading.visible = true


func hide_loading() -> void:
	_loading.visible = false


func _show_toast(text: String, kind: int) -> void:
	var colors := [UiTheme.ACCENT_2, UiTheme.SUCCESS, UiTheme.ACCENT, UiTheme.DANGER]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.035, 0.04, 0.9), colors[clampi(kind, 0, 3)], 1, 6, 14))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiTheme.label(tr(text), UiTheme.FONT_SMALL + 2)
	p.add_child(l)
	_toast_box.add_child(p)
	if _toast_box.get_child_count() > 4:
		_toast_box.get_child(0).queue_free()
	var tw := p.create_tween()
	tw.tween_interval(3.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


## Modal dialog. Returns the dialog so callers can add buttons; default has OK.
func show_dialog(title_key: String, body: String, buttons: Array = []) -> Control:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_dialog_layer.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	v.add_child(UiTheme.label(tr(title_key), 30, UiTheme.ACCENT))
	var body_l := UiTheme.label(body)
	body_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_l.custom_minimum_size = Vector2(480, 0)
	v.add_child(body_l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	if buttons.is_empty():
		buttons = [{"text": "UI_OK", "callback": Callable()}]
	for b: Dictionary in buttons:
		var btn := UiTheme.button(tr(str(b.text)), 60)
		btn.custom_minimum_size.x = 160
		var cb: Callable = b.get("callback", Callable())
		btn.pressed.connect(func() -> void:
			shade.queue_free()
			if cb.is_valid():
				cb.call())
		row.add_child(btn)
	Audio.play_ui("ui_error")
	return shade


func confirm(title_key: String, body: String, on_yes: Callable) -> void:
	show_dialog(title_key, body, [
		{"text": "UI_CANCEL", "callback": Callable()},
		{"text": "UI_CONFIRM", "callback": on_yes},
	])
