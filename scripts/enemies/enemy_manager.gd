class_name EnemyManager
extends Node3D
## Spawns enemies and replicates them. One compact unreliable snapshot per tick for all
## enemies (15 Hz) + reliable discrete events (alert screech, attack, door bash...).

signal enemy_event(enemy: EnemyBase, event_name: StringName)
signal enemy_state_changed(enemy: EnemyBase, state: StringName)

const SEND_RATE := 15.0

var mission: Node # MissionController
var enemies: Dictionary = {} # id -> EnemyBase
var _next_id := 1
var _send_t := 0.0


func all() -> Array:
	return enemies.values()


func server_spawn(data: EnemyData, pos: Vector3) -> EnemyBase:
	var id := _next_id
	_next_id += 1
	_rpc_spawn.rpc(id, String(data.id), pos)
	return enemies.get(id)


func server_activate(id: int, route: PackedVector3Array) -> void:
	var e: EnemyBase = enemies.get(id)
	if e == null:
		return
	e.activate(route)
	_rpc_set_active.rpc(id, true)


func snapshot() -> Array:
	var out: Array = []
	for e: EnemyBase in enemies.values():
		out.append([e.enemy_id, String(e.data.id), e.global_position, e.active, String(e.replicated_state)])
	return out


func apply_snapshot(list: Array) -> void:
	for s: Array in list:
		_spawn_local(int(s[0]), StringName(s[1]), s[2])
		var e: EnemyBase = enemies.get(int(s[0]))
		if e:
			e.active = bool(s[3])
			e.replicated_state = StringName(s[4])


@rpc("authority", "call_local", "reliable")
func _rpc_spawn(id: int, enemy_type: String, pos: Vector3) -> void:
	_spawn_local(id, StringName(enemy_type), pos)


func _spawn_local(id: int, enemy_type: StringName, pos: Vector3) -> void:
	if enemies.has(id):
		return
	var data: EnemyData = Content.enemies.get(enemy_type)
	if data == null:
		Log.e("ai", "unknown enemy type %s" % enemy_type)
		return
	var e := EnemyBase.new()
	e.setup(id, data, mission)
	e.noise = mission.noise
	add_child(e)
	e.global_position = pos
	enemies[id] = e
	_next_id = maxi(_next_id, id + 1)


@rpc("authority", "call_local", "reliable")
func _rpc_set_active(id: int, active: bool) -> void:
	var e: EnemyBase = enemies.get(id)
	if e:
		e.active = active


func broadcast_event(id: int, event_name: StringName) -> void:
	if multiplayer.is_server():
		_rpc_event.rpc(id, String(event_name))


func broadcast_state_change(id: int, state: StringName) -> void:
	if multiplayer.is_server():
		_rpc_state_change.rpc(id, EnemyBrain.state_id(state))


@rpc("authority", "call_local", "reliable")
func _rpc_event(id: int, event_name: String) -> void:
	var e: EnemyBase = enemies.get(id)
	if e == null:
		return
	var head := e.global_position + Vector3.UP * 2.0
	if e.visual and event_name in ["attack", "alert", "door"]:
		e.visual.play_action(StringName(event_name))
	match event_name:
		"alert":
			Audio.play_3d("hunter_screech", head, 4.0, 45.0)
		"attack":
			Audio.play_3d("hunter_growl", head, 2.0, 25.0, 1.2)
		"hit":
			Audio.play_3d("hunter_attack", head, 3.0, 25.0)
		"bash":
			Audio.play_3d("door_bash", e.global_position + Vector3.UP, 6.0, 40.0)
			Effects.debris(self, e.global_position + (-e.global_basis.z) * 0.9 + Vector3.UP * 1.4, -e.global_basis.z, 14)
		"stunned":
			Audio.play_3d("stun", head, 2.0, 30.0)
		"investigate":
			Audio.play_3d("hunter_click", head, 0.0, 22.0)
	enemy_event.emit(e, StringName(event_name))


@rpc("authority", "call_local", "reliable")
func _rpc_state_change(id: int, state_id: int) -> void:
	var e: EnemyBase = enemies.get(id)
	if e == null:
		return
	e.replicated_state = EnemyBrain.state_from_id(state_id)
	enemy_state_changed.emit(e, e.replicated_state)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshots(data: Array) -> void:
	for s: Array in data:
		var e: EnemyBase = enemies.get(int(s[0]))
		if e:
			e.push_snapshot(s[1], float(s[2]), float(s[3]))


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or enemies.is_empty():
		return
	_send_t += delta
	if _send_t < 1.0 / SEND_RATE:
		return
	_send_t = 0.0
	var data: Array = []
	for e: EnemyBase in enemies.values():
		data.append([e.enemy_id, e.global_position, e.rotation.y, e.replicated_speed])
	_rpc_snapshots.rpc(data)


## Client helper for tension music / HUD danger cues.
func nearest_threat(pos: Vector3) -> Dictionary:
	var best: EnemyBase = null
	var best_d := INF
	for e: EnemyBase in enemies.values():
		if not e.active:
			continue
		var d := e.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = e
	return {"enemy": best, "distance": best_d, "state": best.replicated_state if best else &""}
