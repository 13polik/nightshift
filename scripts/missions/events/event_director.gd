class_name EventDirector
extends Node
## Escalation director (server). Threat (0..1) rises with time and objective progress and
## gates which random events may fire. Scripted events are triggered by objectives.
## Enemy aggression = threat-driven base + temporary bonuses from events.

signal event_started(id: StringName)
signal event_ended(id: StringName)

const MIN_GAP := 40.0
const MAX_GAP := 95.0

var mission: Node # MissionController
var data: MissionData
var threat := 0.0
var aggression_bonus := 0.0
var active: Array[MissionEvent] = []
var _cooldowns: Dictionary = {}
var _counts: Dictionary = {}
var _next_random := 70.0
var _sync_t := 0.0
var rng := RandomNumberGenerator.new()
var history: Array[StringName] = []


func setup(p_mission: Node, p_data: MissionData, seed_rng: SeededRng) -> void:
	mission = p_mission
	data = p_data
	rng = seed_rng.stream("events")
	_next_random = rng.randf_range(60.0, 90.0)


func add_threat(amount: float) -> void:
	threat = clampf(threat + amount, 0.0, 1.0)


func event_data(id: StringName) -> EventData:
	for e in data.events:
		if e.id == id:
			return e
	return Content.events.get(id)


## Starts a specific event (scripted triggers from objectives). Returns success.
func trigger(id: StringName) -> bool:
	if not multiplayer.is_server():
		return false
	var ed := event_data(id)
	if ed == null or ed.event_script == null:
		Log.w("events", "unknown event %s" % id)
		return false
	for a in active:
		if a.data.id == id and not a.finished:
			return false
	var ev: MissionEvent = ed.event_script.new()
	ev.setup(ed, mission)
	if not ev.can_start():
		return false
	active.append(ev)
	_counts[id] = int(_counts.get(id, 0)) + 1
	_cooldowns[id] = ed.cooldown
	history.append(id)
	Log.i("events", "event started: %s (threat %.2f)" % [id, threat])
	ev.start()
	event_started.emit(id)
	_rpc_event_started.rpc(String(id), ed.banner_key, ed.duration)
	return true


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or mission == null or not mission.running:
		return
	add_threat(data.threat_per_minute * delta / 60.0)
	for id in _cooldowns.keys():
		_cooldowns[id] = float(_cooldowns[id]) - delta
	for ev in active.duplicate():
		if not ev.finished:
			ev.update(delta)
		if ev.finished:
			active.erase(ev)
			event_ended.emit(ev.data.id)
			_rpc_event_ended.rpc(String(ev.data.id))
	_next_random -= delta
	if _next_random <= 0.0:
		_next_random = rng.randf_range(MIN_GAP, MAX_GAP) * (1.0 - threat * 0.4)
		_pick_random()
	var aggr := clampf(threat * 0.7 + aggression_bonus, 0.0, 1.0)
	for e: EnemyBase in mission.enemies.all():
		e.set_aggression(aggr)
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 2.0
		mission.state.set_flag(&"threat", snappedf(threat, 0.01))


func _pick_random() -> void:
	var total := 0.0
	var cands: Array[EventData] = []
	for e in data.events:
		if not e.random or threat < e.min_threat or float(_cooldowns.get(e.id, 0.0)) > 0.0:
			continue
		if int(_counts.get(e.id, 0)) >= e.max_occurrences:
			continue
		cands.append(e)
		total += e.weight
	if cands.is_empty():
		return
	var r := rng.randf() * total
	for e in cands:
		r -= e.weight
		if r <= 0.0:
			if not trigger(e.id):
				_next_random = 10.0
			return


func stop_all() -> void:
	for ev in active:
		ev.finish()
	active.clear()


@rpc("authority", "call_local", "reliable")
func _rpc_event_started(id: String, banner_key: String, duration: float) -> void:
	if not banner_key.is_empty():
		mission.hud_event_banner(banner_key, duration)
	match id:
		"power_failure":
			Audio.play_2d("power_down", 0.0)
		"alarm", "emergency_evacuation":
			Audio.play_2d("alarm", -4.0)
		"lockdown":
			Audio.play_2d("door_close", 0.0)


@rpc("authority", "call_local", "reliable")
func _rpc_event_ended(_id: String) -> void:
	pass
