class_name TouchControls
extends Control
## Multi-touch router for gameplay. Each finger is assigned on touch-down to a button,
## the joystick zone (left) or the look zone (right) and keeps that owner until release,
## so moving, looking and pressing buttons simultaneously works reliably.
## Layout adapts to aspect ratio + safe area, honours scale/opacity/left-handed settings.

const LOOK_TOUCH_SCALE := 0.18

var joystick: TouchJoystick
var buttons: Dictionary = {}   # action -> TouchButton
var _look_finger := -1
var _look_last := Vector2.ZERO
var _finger_owner: Dictionary = {} # index -> "joy" | "look" | TouchButton
## Regular GUI controls (inventory bar, pause button...) that must receive their touches.
var ui_blockers: Array[Control] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	joystick = TouchJoystick.new()
	joystick.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(joystick)
	_add_button(&"interact", "E", "TOUCH_INTERACT", 66.0, UiTheme.ACCENT)
	_add_button(&"sprint", ">>", "TOUCH_SPRINT", 44.0)
	_add_button(&"crouch", "v", "TOUCH_CROUCH", 44.0)
	_add_button(&"flashlight", "*", "TOUCH_LIGHT", 44.0, Color(1.0, 0.95, 0.7))
	_add_button(&"use_item", "+", "TOUCH_USE", 44.0, UiTheme.SUCCESS)
	_add_button(&"ping", "!", "TOUCH_PING", 34.0)
	get_viewport().size_changed.connect(layout)
	Events.settings_changed.connect(func(_s: String) -> void: layout())
	layout.call_deferred()


func _add_button(action: StringName, glyph: String, label_key: String, r: float, accent := UiTheme.ACCENT_2) -> void:
	var b := TouchButton.new()
	b.action = action
	b.glyph = glyph
	b.label_key = label_key
	b.radius = r
	b.accent = accent
	add_child(b)
	buttons[action] = b


func layout() -> void:
	var vp := get_viewport_rect().size
	var bs := float(Settings.get_value("controls", "button_scale"))
	var js := float(Settings.get_value("controls", "joystick_scale"))
	var left_handed := bool(Settings.get_value("controls", "left_handed"))
	var safe := _safe_margins(vp)
	var unit := clampf(vp.y / 720.0, 0.7, 1.6)
	joystick.radius = 80.0 * js * unit
	joystick.dynamic = bool(Settings.get_value("controls", "dynamic_joystick"))
	var joy_x: float = safe.x + 60.0 * unit + joystick.radius
	if left_handed:
		joy_x = vp.x - joy_x
	joystick.rest_position = Vector2(joy_x, vp.y - safe.w - 60.0 * unit - joystick.radius)
	# right cluster positions (relative to bottom-right corner, in "unit" pixels)
	var cluster := {
		&"interact": Vector2(-150, -150),
		&"sprint": Vector2(-290, -95),
		&"crouch": Vector2(-70, -290),
		&"flashlight": Vector2(-215, -300),
		&"use_item": Vector2(-305, -215),
		&"ping": Vector2(-70, -420),
	}
	for action: StringName in buttons:
		var b: TouchButton = buttons[action]
		b.radius = {&"interact": 66.0, &"ping": 34.0}.get(action, 44.0) * bs * unit
		b.size = Vector2(b.radius * 2.0, b.radius * 2.0)
		var off: Vector2 = cluster[action] * unit * sqrt(bs)
		var anchor := Vector2(vp.x - safe.z, vp.y - safe.w)
		var c := anchor + off
		if left_handed:
			c.x = vp.x - c.x
		b.position = c - b.size * 0.5
		b.queue_redraw()
	joystick.queue_redraw()


func _safe_margins(vp: Vector2) -> Vector4:
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	if DisplayServer.get_name() == "headless" or screen.x <= 0 or safe.size.x <= 0:
		return Vector4(16, 16, 16, 16)
	var sx := vp.x / float(screen.x)
	var sy := vp.y / float(screen.y)
	return Vector4(16 + safe.position.x * sx, 16 + safe.position.y * sy, 16 + (screen.x - safe.end.x) * sx, 16 + (screen.y - safe.end.y) * sy)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		var owner_v: Variant = _finger_owner.get(d.index)
		if owner_v is String and owner_v == "joy":
			joystick.drag(d.position)
		elif owner_v is String and owner_v == "look":
			var delta := d.position - _look_last
			_look_last = d.position
			GameInput.add_look(delta * LOOK_TOUCH_SCALE * (720.0 / get_viewport_rect().size.y) * 1.6)


func _touch_down(index: int, pos: Vector2) -> void:
	for c in ui_blockers:
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
			return
	for b: TouchButton in buttons.values():
		if b.hit(pos):
			_finger_owner[index] = b
			b.press(index)
			return
	var vp := get_viewport_rect().size
	var left_handed := bool(Settings.get_value("controls", "left_handed"))
	var in_joy_zone := pos.x < vp.x * 0.42 if not left_handed else pos.x > vp.x * 0.58
	if in_joy_zone and joystick.finger == -1 and pos.y > vp.y * 0.25:
		_finger_owner[index] = "joy"
		joystick.begin(index, pos)
	elif _look_finger == -1:
		_finger_owner[index] = "look"
		_look_finger = index
		_look_last = pos


func _touch_up(index: int) -> void:
	var owner_v: Variant = _finger_owner.get(index)
	_finger_owner.erase(index)
	if owner_v is TouchButton:
		(owner_v as TouchButton).release()
	elif owner_v is String and owner_v == "joy":
		joystick.end()
	elif owner_v is String and owner_v == "look":
		_look_finger = -1


func release_all() -> void:
	for index in _finger_owner.keys():
		_touch_up(index)
