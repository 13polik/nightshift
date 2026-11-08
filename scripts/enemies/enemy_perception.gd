class_name EnemyPerception
extends RefCounted
## Server-side senses for an enemy: gradual sight awareness per player (fair detection
## instead of instant spotting), flashlight glare, darkness, crouching, and hearing.

const LOS_MASK := 1 | 32
const EYE_HEIGHT := 2.05
const TARGET_HEIGHT := 1.1

var enemy: EnemyBase
var awareness: Dictionary = {}   # peer_id -> 0..1.5
var _visible: Dictionary = {}    # peer_id -> bool
var _players: Dictionary = {}    # peer_id -> PlayerCharacter


func _init(p_enemy: EnemyBase) -> void:
	enemy = p_enemy


func update(delta: float, players: Array) -> void:
	var data := enemy.data
	var aggr := enemy.brain.aggression
	var eye := enemy.global_position + Vector3.UP * EYE_HEIGHT
	var fwd := -enemy.global_basis.z
	var seen_ids := {}
	for raw: Variant in players:
		if raw == null or not is_instance_valid(raw):
			continue
		var p := raw as PlayerCharacter
		if not p.can_act():
			awareness.erase(p.peer_id)
			_visible.erase(p.peer_id)
			continue
		_players[p.peer_id] = p
		seen_ids[p.peer_id] = true
		var target := p.global_position + Vector3.UP * TARGET_HEIGHT
		var to := target - eye
		var dist := to.length()
		var range_m := data.sight_range * (1.0 + aggr * 0.3)
		if p.is_flashlight_on():
			range_m *= data.flashlight_sight_multiplier
		elif not enemy.mission.is_position_lit(p.global_position):
			range_m *= data.darkness_sight_multiplier
		if p.is_crouched():
			range_m *= data.crouch_sight_multiplier
		var in_cone := fwd.dot(to.normalized()) >= cos(deg_to_rad(data.fov_degrees * 0.5))
		var visible := false
		if dist <= data.close_detect_radius:
			visible = has_line_of_sight(p)
		elif dist <= range_m and in_cone:
			visible = has_line_of_sight(p)
		_visible[p.peer_id] = visible
		var a: float = awareness.get(p.peer_id, 0.0)
		if visible:
			var closeness := clampf(1.0 - dist / maxf(range_m, 0.1), 0.05, 1.0)
			var motion := 1.35 if p.is_sprinting() else (0.6 if p.is_crouched() else 1.0)
			a += data.awareness_gain * sqrt(closeness) * motion * (1.0 + aggr) * delta
			if dist <= data.close_detect_radius:
				a += 2.0 * delta
		else:
			a -= data.awareness_decay * delta
		# flashlight shone directly at the creature
		if p.is_flashlight_on() and dist < 18.0:
			var aim := p.aim_direction()
			var from_player := (eye - (p.global_position + Vector3.UP * 1.4)).normalized()
			if aim.dot(from_player) > 0.94 and has_line_of_sight(p):
				a += 1.4 * delta
				_visible[p.peer_id] = true
		a = clampf(a, 0.0, 1.5)
		if a <= 0.0:
			awareness.erase(p.peer_id)
		else:
			awareness[p.peer_id] = a
	for id in awareness.keys():
		if not seen_ids.has(id):
			awareness.erase(id)


func has_line_of_sight(p: Node3D) -> bool:
	var space := enemy.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(enemy.global_position + Vector3.UP * EYE_HEIGHT, p.global_position + Vector3.UP * TARGET_HEIGHT, LOS_MASK)
	q.exclude = [enemy.get_rid()]
	return space.intersect_ray(q).is_empty()


func can_see(p: Node3D) -> bool:
	return p != null and bool(_visible.get(p.get("peer_id"), false))


func awareness_of(p: Node3D) -> float:
	return float(awareness.get(p.get("peer_id"), 0.0)) if p else 0.0


func most_aware_target() -> PlayerCharacter:
	var best: PlayerCharacter = null
	var best_a := 0.0
	for id: int in awareness.keys():
		# untyped: the player may have disconnected (freed) since the last perception tick
		var raw: Variant = _players.get(id)
		if raw == null or not is_instance_valid(raw):
			_players.erase(id)
			awareness.erase(id)
			_visible.erase(id)
			continue
		var p := raw as PlayerCharacter
		if p.can_act() and float(awareness[id]) > best_a:
			best_a = awareness[id]
			best = p
	return best


func calm_down() -> void:
	for id in awareness.keys():
		awareness[id] = float(awareness[id]) * 0.3


## Hearing: returns the stimulus if the enemy perceives the noise, else {}.
func hear(pos: Vector3, loudness: float, kind: StringName, peer: int) -> Dictionary:
	var effective := loudness * enemy.data.hearing_multiplier * (1.0 + enemy.brain.aggression * 0.5)
	var d := enemy.global_position.distance_to(pos)
	if d > effective:
		return {}
	# walls muffle sound: occluded noises carry ~55% as far
	var space := enemy.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(enemy.global_position + Vector3.UP * 1.5, pos + Vector3.UP * 0.5, 1)
	q.exclude = [enemy.get_rid()]
	if not space.intersect_ray(q).is_empty():
		effective *= 0.55
		if d > effective:
			return {}
	return {"position": pos, "strength": 1.0 - d / maxf(effective, 0.1), "loudness": loudness, "kind": kind, "peer": peer, "time": enemy.now()}
