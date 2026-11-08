class_name AlarmEvent
extends MissionEvent
## Facility alarm: sirens pull the Hunter around and raise its aggression. Can be silenced
## at the security alarm panel.

var _pulse := 0.0
var _panels: Array[ObjectiveDevice] = []


func can_start() -> bool:
	return not bool(mission.state.get_flag(&"alarm", false))


func start() -> void:
	mission.state.set_flag(&"alarm", true)
	mission.events.aggression_bonus += 0.3
	for d in mission.facility.devices_with_tag(&"alarm_panel"):
		d.always_usable = true
		d.done = false
		d.condition = func() -> bool: return bool(mission.state.get_flag(&"alarm", false))
		d.interacted.connect(_on_panel)
		d.mark_dirty()
		_panels.append(d)


func _on_panel(_peer: int) -> void:
	finish()


func update(delta: float) -> void:
	super.update(delta)
	_pulse -= delta
	if _pulse <= 0.0 and not finished:
		_pulse = 6.0
		var rooms: Array = mission.facility.room_info.keys()
		var r: StringName = rooms[randi() % rooms.size()]
		var aabb: AABB = mission.facility.room_info[r].aabb
		mission.noise.emit_noise(aabb.get_center(), 22.0, &"alarm", 0)


func stop() -> void:
	mission.state.set_flag(&"alarm", false)
	mission.events.aggression_bonus = maxf(0.0, mission.events.aggression_bonus - 0.3)
	for d in _panels:
		if d.interacted.is_connected(_on_panel):
			d.interacted.disconnect(_on_panel)
		d.always_usable = false
		d.done = false
		d.mark_dirty()
