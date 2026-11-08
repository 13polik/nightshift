class_name PowerFailureEvent
extends MissionEvent
## Main power drops; emergency lighting takes over. Restored automatically after the
## duration, or early by resetting any breaker.

var _zones: PackedStringArray = PackedStringArray(["power_main", "power_underground"])
var _breakers: Array[ObjectiveDevice] = []


func can_start() -> bool:
	return bool(mission.state.get_flag(&"power_main", false)) and not bool(mission.state.get_flag(&"evac", false))


func start() -> void:
	for z in _zones:
		mission.state.set_flag(StringName(z), false)
	mission.state.set_flag(&"blackout", true)
	for d in mission.facility.devices_with_tag(&"power_breaker"):
		d.always_usable = true
		d.done = false
		d.condition = func() -> bool: return bool(mission.state.get_flag(&"blackout", false))
		d.interacted.connect(_on_breaker)
		d.mark_dirty()
		_breakers.append(d)


func _on_breaker(_peer: int) -> void:
	finish()


func stop() -> void:
	for z in _zones:
		mission.state.set_flag(StringName(z), true)
	mission.state.set_flag(&"blackout", false)
	for d in _breakers:
		if d.interacted.is_connected(_on_breaker):
			d.interacted.disconnect(_on_breaker)
		d.always_usable = false
		d.done = true
		d.mark_dirty()
