class_name MissionDirector
extends Node
## Runs the objective chain (server) and mirrors objective progress to clients.
## Main objectives run in sequence; optional objectives run in parallel.

signal objective_started(index: int)
signal objective_completed(index: int, optional: bool)
signal chain_finished
## Client-side: progress/detail updated.
signal client_updated

const SYNC_INTERVAL := 0.25

var mission: Node # MissionController
var data: MissionData
var main: Array[ObjectiveHandler] = []
var optional: Array[ObjectiveHandler] = []
var index := -1
var finished := false
var completed_main: Array[int] = []
var completed_optional: Array[int] = []
var _sync_t := 0.0

# client mirror
var client_index := -1
var client_progress := 0.0
var client_detail: Dictionary = {}
var client_optional: Array = []   # [{index, done, progress}]


func setup(p_mission: Node, p_data: MissionData) -> void:
	mission = p_mission
	data = p_data


func server_start(setup_data: Dictionary) -> void:
	for rt: Dictionary in setup_data.objectives:
		main.append(ObjectiveHandler.create(data.objectives[int(rt.index)], rt, self))
	for rt: Dictionary in setup_data.optional:
		optional.append(ObjectiveHandler.create(data.optional_objectives[int(rt.optional_index)], rt, self))
	mission.interactions.interaction_completed.connect(_on_interaction)
	for h in optional:
		h.start()
	_advance()


func current() -> ObjectiveHandler:
	return main[index] if index >= 0 and index < main.size() else null


func current_def() -> ObjectiveData:
	var i := client_index if not multiplayer.is_server() else index
	return data.objectives[i] if i >= 0 and i < data.objectives.size() else null


func _advance() -> void:
	index += 1
	if index >= main.size():
		finished = true
		chain_finished.emit()
		_sync()
		return
	var h := main[index]
	Log.i("mission", "objective %d/%d: %s" % [index + 1, main.size(), h.def.id])
	for ev in h.def.events_on_start:
		mission.events.trigger(StringName(ev))
	h.start()
	objective_started.emit(index)
	_rpc_objective_started.rpc(index)
	_sync()


func _on_interaction(peer: int, i: Interactable) -> void:
	var h := current()
	if h:
		h.on_interaction(peer, i)
	for o in optional:
		if not o.completed:
			o.on_interaction(peer, i)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or finished or not mission.running:
		return
	var h := current()
	if h:
		h.update(delta)
		if h.completed:
			_on_completed(h, false)
			_advance()
	for o in optional:
		if not o.completed:
			o.update(delta)
			if o.completed:
				_on_completed(o, true)
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = SYNC_INTERVAL
		_sync()


func _on_completed(h: ObjectiveHandler, is_optional: bool) -> void:
	var def := h.def
	Log.i("mission", "objective complete: %s%s" % [def.id, " (optional)" if is_optional else ""])
	if not String(def.sets_flag).is_empty():
		for f in String(def.sets_flag).split(",", false):
			mission.state.set_flag(StringName(f.strip_edges()), true)
	if def.unlock_tag != &"":
		for i: Interactable in mission.interactions.find_by_tag(def.unlock_tag):
			i.set_enabled(true)
	for ev in def.events_on_complete:
		mission.events.trigger(StringName(ev))
	mission.events.add_threat(def.threat_on_complete)
	var idx := int(h.rt.optional_index) if is_optional else int(h.rt.index)
	if is_optional:
		completed_optional.append(idx)
	else:
		completed_main.append(idx)
	objective_completed.emit(idx, is_optional)
	_rpc_objective_completed.rpc(idx, is_optional)


func _sync() -> void:
	var h := current()
	var opt: Array = []
	for o in optional:
		opt.append({"i": int(o.rt.optional_index), "d": o.completed, "p": o.progress(), "x": o.detail})
	_rpc_progress.rpc(index, h.progress() if h else 1.0, h.detail if h else {}, opt)


## Reward inputs for the result screen (objective XP / currency).
func earned() -> Dictionary:
	var xp := 0
	var cur := 0
	var opt_xp := 0
	for i in completed_main:
		xp += data.objectives[i].reward_xp
		cur += data.objectives[i].reward_currency
	for i in completed_optional:
		opt_xp += data.optional_objectives[i].reward_xp
		cur += data.optional_objectives[i].reward_currency
	return {"objectives_xp": xp, "objectives_currency": cur, "optional_xp": opt_xp,
		"objectives_completed": completed_main.size() + completed_optional.size()}


## Runtime dictionary (targets/rooms/items) for the current objective, on any peer.
func runtime_for(i: int, is_optional: bool = false) -> Dictionary:
	var list: Array = mission.setup.get("optional" if is_optional else "objectives", [])
	for rt: Dictionary in list:
		if (is_optional and int(rt.optional_index) == i) or (not is_optional and int(rt.index) == i):
			return rt
	return {}


@rpc("authority", "call_local", "reliable")
func _rpc_objective_started(i: int) -> void:
	client_index = i
	client_progress = 0.0
	client_detail = {}
	if i > 0:
		Audio.play_2d("objective", -3.0, &"UI")
	client_updated.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_objective_completed(i: int, is_optional: bool) -> void:
	var d: ObjectiveData = data.optional_objectives[i] if is_optional else data.objectives[i]
	Events.toast(tr("TOAST_OBJECTIVE_COMPLETE").format({"name": tr(d.title_key)}), Events.ToastKind.SUCCESS)


@rpc("authority", "call_local", "unreliable_ordered")
func _rpc_progress(i: int, p: float, detail: Dictionary, opt: Array) -> void:
	client_index = i
	client_progress = p
	client_detail = detail
	client_optional = opt
	client_updated.emit()
