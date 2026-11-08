class_name ObjectiveHandler
extends RefCounted
## Server-side runtime of one objective. Subclass per ObjectiveData.Type and register it
## in ObjectiveHandler.create(); the MissionDirector never needs to change.

var director: Node # MissionDirector
var def: ObjectiveData
var rt: Dictionary
var completed := false
var elapsed := 0.0
## Extra data shown on clients (counts, hint rooms, timers).
var detail: Dictionary = {}


static func create(p_def: ObjectiveData, p_rt: Dictionary, p_director: Node) -> ObjectiveHandler:
	var h: ObjectiveHandler
	match p_def.type:
		ObjectiveData.Type.REACH_ZONE:
			h = ObjectiveHandlers.ReachZone.new()
		ObjectiveData.Type.INTERACT, ObjectiveData.Type.DELIVER:
			h = ObjectiveHandlers.UseDevices.new()
		ObjectiveData.Type.COLLECT:
			h = ObjectiveHandlers.Collect.new()
		ObjectiveData.Type.SURVIVE:
			h = ObjectiveHandlers.Survive.new()
		ObjectiveData.Type.EXTRACT:
			h = ObjectiveHandlers.Extract.new()
		_:
			h = ObjectiveHandler.new()
	h.def = p_def
	h.rt = p_rt
	h.director = p_director
	return h


func mission() -> Node:
	return director.mission


func start() -> void:
	pass


func stop() -> void:
	pass


func update(_delta: float) -> void:
	pass


func on_interaction(_peer: int, _i: Interactable) -> void:
	pass


func progress() -> float:
	return 1.0 if completed else 0.0


func complete() -> void:
	if completed:
		return
	completed = true
	stop()
