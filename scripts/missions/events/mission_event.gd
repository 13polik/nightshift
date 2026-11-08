class_name MissionEvent
extends RefCounted
## Base class for facility events (server side). Effects are expressed through mission
## flags, doors, devices and enemies so clients get them via normal replication.
## New events: subclass, then reference the script from an EventData resource.

var data: EventData
var mission: Node # MissionController
var elapsed := 0.0
var duration := 30.0
var finished := false


func setup(p_data: EventData, p_mission: Node) -> void:
	data = p_data
	mission = p_mission
	duration = p_data.duration


## Return false to refuse starting (conditions not met) - the director picks another.
func can_start() -> bool:
	return true


func start() -> void:
	pass


func update(delta: float) -> void:
	elapsed += delta
	if duration > 0.0 and elapsed >= duration:
		finish()


func finish() -> void:
	if finished:
		return
	finished = true
	stop()


func stop() -> void:
	pass


func param(key: String, default_value: Variant) -> Variant:
	return data.params.get(key, default_value) if data else default_value
