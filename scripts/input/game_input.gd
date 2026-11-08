extends Node
## Unified gameplay input (autoload "GameInput"). Touch controls, keyboard/mouse and
## gamepads all write into the same state; the local player only reads from here, so the
## player controller never cares which device produced the input.

signal action_pressed(action: StringName)
signal action_released(action: StringName)

## Actions that are "buttons" from gameplay's point of view.
const BUTTONS: Array[StringName] = [
	&"sprint", &"crouch", &"interact", &"flashlight", &"use_item", &"drop_item",
	&"next_item", &"ping", &"quick_chat", &"slot_1", &"slot_2", &"slot_3", &"slot_4",
]

var enabled: bool = true
## Movement from the virtual joystick (-1..1). Combined with keyboard/gamepad each frame.
var touch_move: Vector2 = Vector2.ZERO
var _look_accum: Vector2 = Vector2.ZERO
var _held: Dictionary = {}   # action -> source count
var _touch_held: Dictionary = {}
var mouse_look_active: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Combined movement vector, y = forward(-) / back(+), matching Input.get_vector.
func move_vector() -> Vector2:
	if not enabled:
		return Vector2.ZERO
	var v := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var pad := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if pad.length() > 0.2:
		v += pad
	v += touch_move
	return v.limit_length(1.0)


## Returns the look delta accumulated since the last call (in "degrees-ish" units).
func consume_look() -> Vector2:
	var d := _look_accum
	_look_accum = Vector2.ZERO
	if not enabled:
		return Vector2.ZERO
	var pad := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if pad.length() > 0.15:
		d += pad * 180.0 * get_process_delta_time()
	return d


func add_look(delta: Vector2) -> void:
	_look_accum += delta


func is_held(action: StringName) -> bool:
	if not enabled:
		return false
	return _touch_held.get(action, false) or Input.is_action_pressed(action)


## Called by touch buttons.
func touch_press(action: StringName) -> void:
	_touch_held[action] = true
	if enabled:
		action_pressed.emit(action)


func touch_release(action: StringName) -> void:
	_touch_held[action] = false
	if enabled:
		action_released.emit(action)


func reset() -> void:
	touch_move = Vector2.ZERO
	_look_accum = Vector2.ZERO
	_touch_held.clear()


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	for a in BUTTONS:
		if event.is_action_pressed(a, false, true):
			action_pressed.emit(a)
		elif event.is_action_released(a, true):
			action_released.emit(a)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := float(Settings.get_value("controls", "mouse_sensitivity"))
		add_look((event as InputEventMouseMotion).relative * 0.12 * s)
