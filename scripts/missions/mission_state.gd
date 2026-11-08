class_name MissionState
extends Node
## Replicated mission flags (server writes, everyone reads). Systems react to
## flag_changed instead of referencing each other directly.
##
## Known flags: power_main, power_underground, power_generator, alarm, lockdown, evac,
## evac_deadline, extraction_open, extraction_room, hunter_alert, elevator_online, threat

signal flag_changed(flag: StringName, value: Variant)

var flags: Dictionary = {}


func get_flag(flag: StringName, default_value: Variant = false) -> Variant:
	return flags.get(flag, default_value)


func set_flag(flag: StringName, value: Variant) -> void:
	if not multiplayer.is_server():
		return
	if flags.has(flag) and flags[flag] == value:
		return
	_rpc_flag.rpc(String(flag), value)


func snapshot() -> Dictionary:
	return flags.duplicate()


func apply_snapshot(s: Dictionary) -> void:
	for k in s:
		_apply(StringName(k), s[k])


@rpc("authority", "call_local", "reliable")
func _rpc_flag(flag: String, value: Variant) -> void:
	_apply(StringName(flag), value)


func _apply(flag: StringName, value: Variant) -> void:
	var changed: bool = not flags.has(flag) or flags[flag] != value
	flags[flag] = value
	if changed:
		flag_changed.emit(flag, value)
