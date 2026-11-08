class_name SystemFailureEvent
extends MissionEvent
## A previously available system stops working for a while: the elevator goes offline or a
## secure door jams.

var _jammed: Door
var _system := ""


func start() -> void:
	var options: Array = ["elevator"]
	for d: Door in mission.facility.doors.values():
		if d.door_type == "secure" and d.lock_kind == "" and not d.broken:
			options.append(d)
	var pick: Variant = options[randi() % options.size()]
	if pick is Door:
		_jammed = pick
		_jammed.set_lock("jammed")
		_system = "door"
	else:
		_system = "elevator"
		mission.state.set_flag(&"elevator_online", false)


func stop() -> void:
	if _system == "elevator":
		mission.state.set_flag(&"elevator_online", true)
	elif _jammed and _jammed.lock_kind == "jammed":
		_jammed.set_lock("")
