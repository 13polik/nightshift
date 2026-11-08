class_name InputSetup
extends RefCounted
## Registers input actions at runtime. Touch controls feed GameInput directly; these
## actions exist for development on desktop and for gamepads.

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_C, KEY_CTRL],
	"interact": [KEY_E],
	"flashlight": [KEY_F],
	"use_item": [KEY_Q],
	"drop_item": [KEY_X],
	"next_item": [KEY_TAB],
	"slot_1": [KEY_1],
	"slot_2": [KEY_2],
	"slot_3": [KEY_3],
	"slot_4": [KEY_4],
	"ping": [KEY_G],
	"quick_chat": [KEY_T],
	"pause": [KEY_ESCAPE],
	"debug_overlay": [KEY_F3],
}

const PAD_BUTTONS := {
	"interact": JOY_BUTTON_X,
	"flashlight": JOY_BUTTON_DPAD_UP,
	"use_item": JOY_BUTTON_Y,
	"crouch": JOY_BUTTON_B,
	"sprint": JOY_BUTTON_LEFT_STICK,
	"next_item": JOY_BUTTON_RIGHT_SHOULDER,
	"ping": JOY_BUTTON_LEFT_SHOULDER,
	"pause": JOY_BUTTON_START,
}


static func register_default_actions() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for keycode: int in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode as Key
			InputMap.action_add_event(action, ev)
	for action: String in PAD_BUTTONS:
		var jb := InputEventJoypadButton.new()
		jb.button_index = PAD_BUTTONS[action] as JoyButton
		InputMap.action_add_event(action, jb)
