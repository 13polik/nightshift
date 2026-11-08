class_name UiScreen
extends Control
## Base for full-screen menus: theme, animated background, safe-area content root, and
## the mobile back gesture / Android back button.

var content: MarginContainer
var _bg: ColorRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/menu_background.gdshader")
	_bg.material = m
	add_child(_bg)
	content = UiTheme.safe_area_margin()
	add_child(content)
	get_viewport().size_changed.connect(func() -> void: UiTheme.apply_safe_area(content))
	UiTheme.apply_safe_area.call_deferred(content)
	Events.language_changed.connect(func(_l: String) -> void: rebuild())
	build()


## Override: create the screen's widgets inside `content`.
func build() -> void:
	pass


func rebuild() -> void:
	for c in content.get_children():
		c.queue_free()
	build()


## Override: back navigation (Android back button / Esc).
func go_back() -> void:
	pass


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		go_back()
		get_viewport().set_input_as_handled()


static func title(text: String) -> Label:
	var l := UiTheme.label(text, UiTheme.FONT_TITLE, UiTheme.TEXT)
	l.add_theme_constant_override("outline_size", 0)
	return l


func clear_content() -> void:
	for c in content.get_children():
		c.queue_free()
