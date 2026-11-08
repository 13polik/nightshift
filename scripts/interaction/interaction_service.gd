class_name InteractionService
extends Node
## Server-authoritative interaction hub (node "Interactions" under the mission root).
## Every interactable has a deterministic net id (static ones by build order, dynamic ones
## assigned by the server) so RPCs never depend on node paths of runtime-built content.

signal interaction_completed(peer_id: int, interactable: Interactable)
signal hold_started(peer_id: int, interactable: Interactable)
signal hold_ended(peer_id: int, interactable: Interactable, completed: bool)
## Local client feedback.
signal local_hold_started(interactable: Interactable, duration: float)
signal local_hold_finished(interactable: Interactable, completed: bool)
signal local_denied(interactable: Interactable, reason_key: String)
signal local_inspect(interactable: Interactable)

const RANGE_TOLERANCE := 1.0
const DYNAMIC_ID_START := 100000

var registry: Dictionary = {}  # id -> Interactable
var _next_static_id := 1
var _next_dynamic_id := DYNAMIC_ID_START
## server: peer -> {id, elapsed, duration}
var _holds: Dictionary = {}
var mission: Node # MissionController
var noise: Node # NoiseSystem


func register_static(i: Interactable) -> int:
	i.net_id = _next_static_id
	_next_static_id += 1
	_add(i)
	return i.net_id


func register_dynamic(i: Interactable, id: int = -1) -> int:
	if id < 0:
		id = _next_dynamic_id
		_next_dynamic_id += 1
	else:
		_next_dynamic_id = maxi(_next_dynamic_id, id + 1)
	i.net_id = id
	_add(i)
	return id


func _add(i: Interactable) -> void:
	i.service = self
	registry[i.net_id] = i
	i.tree_exiting.connect(func() -> void:
		if registry.get(i.net_id) == i:
			registry.erase(i.net_id))


func get_interactable(id: int) -> Interactable:
	var i: Interactable = registry.get(id)
	return i if is_instance_valid(i) else null


func find_by_tag(tag: StringName) -> Array[Interactable]:
	var out: Array[Interactable] = []
	for i: Interactable in registry.values():
		if is_instance_valid(i) and i.tag == tag:
			out.append(i)
	out.sort_custom(func(a: Interactable, b: Interactable) -> bool: return a.net_id < b.net_id)
	return out


## Client: nearest usable interactable for `player`, preferring what the camera faces.
func find_focus(player: Node3D, facing: Vector3, max_range: float) -> Interactable:
	var best: Interactable = null
	var best_score := INF
	var origin := player.global_position + Vector3.UP * 1.0
	for i: Interactable in registry.values():
		if not is_instance_valid(i) or not i.is_visible_to(player):
			continue
		if i.get_parent() == player:
			continue
		var to := i.focus_point() - origin
		var d := to.length()
		var r := minf(max_range, i.interact_range)
		if d > r + 0.4:
			continue
		var flat := Vector3(to.x, 0, to.z).normalized()
		var dot := flat.dot(facing) if flat.length() > 0.01 else 1.0
		if dot < -0.2 and d > 1.2:
			continue
		var score := d * (1.6 - dot)
		if i.objective_active:
			score *= 0.7
		if score < best_score:
			best_score = score
			best = i
	return best


# --- client API -----------------------------------------------------------------------

func request_begin(i: Interactable) -> void:
	if i == null:
		return
	if i.local_only:
		local_inspect.emit(i)
		return
	Net.send_to_server(self, &"_srv_begin", [i.net_id])


func request_cancel() -> void:
	Net.send_to_server(self, &"_srv_cancel", [])


# --- server ---------------------------------------------------------------------------

func broadcast_state(i: Interactable) -> void:
	if multiplayer.is_server():
		_rpc_state.rpc(i.net_id, i.get_state())


## Full state of every interactable (sent once when the mission starts).
func snapshot() -> Dictionary:
	var out := {}
	for id: int in registry:
		var i: Interactable = registry[id]
		if is_instance_valid(i):
			out[id] = i.get_state()
	return out


func apply_snapshot(s: Dictionary) -> void:
	for id in s:
		var i := get_interactable(int(id))
		if i:
			i.apply_state(s[id])


func _player(peer_id: int) -> Node3D:
	return mission.get_player(peer_id) if mission else null


func validate(peer_id: int, i: Interactable) -> String:
	var p := _player(peer_id)
	if p == null or i == null:
		return "REASON_UNAVAILABLE"
	if not p.call("can_act") and not (i.allow_while_downed and p.call("is_downed")):
		return "REASON_UNAVAILABLE"
	if p.global_position.distance_to(i.focus_point()) > i.interact_range + RANGE_TOLERANCE + 1.0:
		return "REASON_TOO_FAR"
	return i.can_interact(p)


@rpc("any_peer", "call_remote", "reliable")
func _srv_begin(id: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := Net.sender_id()
	var i := get_interactable(id)
	var reason := validate(peer, i)
	if not reason.is_empty():
		_send_to(peer, &"_rpc_denied", [id, reason])
		return
	_end_hold(peer, false)
	var p := _player(peer)
	var duration := i.get_hold_time(p)
	if duration <= 0.0:
		_complete(peer, i)
		return
	_holds[peer] = {"id": id, "elapsed": 0.0, "duration": duration, "noise_t": 0.0}
	hold_started.emit(peer, i)
	_send_to(peer, &"_rpc_hold_started", [id, duration])


@rpc("any_peer", "call_remote", "reliable")
func _srv_cancel() -> void:
	if multiplayer.is_server():
		_end_hold(Net.sender_id(), true)


func cancel_holds_for(peer: int) -> void:
	_end_hold(peer, true)


func _end_hold(peer: int, notify: bool) -> void:
	if not _holds.has(peer):
		return
	var h: Dictionary = _holds[peer]
	_holds.erase(peer)
	var i := get_interactable(int(h.id))
	hold_ended.emit(peer, i, false)
	if notify:
		_send_to(peer, &"_rpc_hold_result", [int(h.id), false])


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _holds.is_empty():
		return
	for peer: int in _holds.keys():
		var h: Dictionary = _holds[peer]
		var i := get_interactable(int(h.id))
		var reason := validate(peer, i)
		if not reason.is_empty():
			_end_hold(peer, true)
			continue
		h.elapsed = float(h.elapsed) + delta
		var p := _player(peer)
		i.server_hold_tick(p, float(h.elapsed) / float(h.duration))
		if i.noise_radius > 0.0 and noise:
			h.noise_t = float(h.noise_t) - delta
			if float(h.noise_t) <= 0.0:
				h.noise_t = 1.0
				noise.emit_noise(i.focus_point(), i.noise_radius, &"interaction", peer)
		if float(h.elapsed) >= float(h.duration):
			_holds.erase(peer)
			hold_ended.emit(peer, i, true)
			_complete(peer, i)


func _complete(peer: int, i: Interactable) -> void:
	var p := _player(peer)
	i.server_interact(p)
	if i.noise_radius > 0.0 and noise:
		noise.emit_noise(i.focus_point(), i.noise_radius * 0.8, &"interaction", peer)
	interaction_completed.emit(peer, i)
	_send_to(peer, &"_rpc_hold_result", [i.net_id, true])


func _send_to(peer: int, method: StringName, args: Array) -> void:
	if peer == multiplayer.get_unique_id():
		callv(method, args)
	else:
		callv(&"rpc_id", [peer, method] + args)


# --- client RPCs ----------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _rpc_state(id: int, state: Dictionary) -> void:
	var i := get_interactable(id)
	if i:
		i.apply_state(state)


@rpc("authority", "call_remote", "reliable")
func _rpc_denied(id: int, reason_key: String) -> void:
	local_denied.emit(get_interactable(id), reason_key)


@rpc("authority", "call_remote", "reliable")
func _rpc_hold_started(id: int, duration: float) -> void:
	local_hold_started.emit(get_interactable(id), duration)


@rpc("authority", "call_remote", "reliable")
func _rpc_hold_result(id: int, completed: bool) -> void:
	local_hold_finished.emit(get_interactable(id), completed)
