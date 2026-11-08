class_name EnemyBrain
extends RefCounted
## Finite state machine + shared blackboard for an enemy. Subclass and override
## `create_states()` / reactions to build a new enemy type.

signal state_changed(new_state: StringName, old_state: StringName)

const IDLE := &"IDLE"
const PATROL := &"PATROL"
const INVESTIGATE := &"INVESTIGATE"
const SEARCH := &"SEARCH"
const ALERT := &"ALERT"
const CHASE := &"CHASE"
const ATTACK := &"ATTACK"
const LOST_TARGET := &"LOST_TARGET"
const RETURN_TO_PATROL := &"RETURN_TO_PATROL"
const STUNNED := &"STUNNED"

## Replication index for each state (clients receive ints).
const STATE_IDS: Array[StringName] = [IDLE, PATROL, INVESTIGATE, SEARCH, ALERT, CHASE, ATTACK, LOST_TARGET, RETURN_TO_PATROL, STUNNED]

var enemy: EnemyBase
var states: Dictionary = {}
var current: AIState
var history: Array[StringName] = []

# blackboard
var target: Node3D            # PlayerCharacter currently hunted
var last_known_position := Vector3.ZERO
var last_known_velocity := Vector3.ZERO
var last_seen_time := -100.0
var investigate_position := Vector3.ZERO
var search_center := Vector3.ZERO
var patrol_route: PackedVector3Array = PackedVector3Array()
var patrol_index := 0
var aggression := 0.0         # 0..1, from escalation / events


func setup(p_enemy: EnemyBase) -> void:
	enemy = p_enemy
	for s: AIState in create_states():
		s.brain = self
		s.enemy = enemy
		states[s.state_name()] = s


func create_states() -> Array[AIState]:
	return [IdleState.new(), PatrolState.new(), InvestigateState.new(), SearchState.new(), AlertState.new(),
		ChaseState.new(), AttackState.new(), LostTargetState.new(), ReturnToPatrolState.new(), StunnedState.new()]


func start(initial: StringName = IDLE) -> void:
	transition(initial)


func state_name() -> StringName:
	return current.state_name() if current else &""


func transition(next: StringName, data: Dictionary = {}) -> void:
	if not states.has(next):
		push_error("EnemyBrain: unknown state %s" % next)
		return
	var old := state_name()
	if current:
		current.exit()
	current = states[next]
	current.elapsed = 0.0
	history.append(next)
	if history.size() > 32:
		history.pop_front()
	current.enter(data)
	state_changed.emit(next, old)


func update(delta: float) -> void:
	if current == null:
		return
	current.elapsed += delta
	# generic sight reaction: fully aware of a target -> alert (states may opt out)
	if current.reacts_to_sight():
		var best := enemy.perception.most_aware_target()
		if best and enemy.perception.awareness_of(best) >= 1.0:
			acquire(best)
			if state_name() in [CHASE, ATTACK, LOST_TARGET]:
				transition(CHASE)
			else:
				transition(ALERT)
			return
		elif best and enemy.perception.awareness_of(best) >= 0.4 and state_name() in [IDLE, PATROL, RETURN_TO_PATROL, SEARCH]:
			transition(INVESTIGATE, {"position": best.global_position, "suspicious": true})
			return
	# a hunted player can disappear mid-chase (disconnect): forget them
	if target != null and not is_instance_valid(target):
		target = null
	current.update(delta)


func acquire(t: Node3D) -> void:
	target = t
	last_known_position = t.global_position
	last_known_velocity = Vector3.ZERO
	last_seen_time = enemy.now()


func on_noise(stimulus: Dictionary) -> void:
	if current and current.on_noise(stimulus):
		return
	if state_name() in [IDLE, PATROL, RETURN_TO_PATROL, SEARCH] or (state_name() == INVESTIGATE and float(stimulus.strength) > 0.3):
		transition(INVESTIGATE, {"position": stimulus.position})


func on_stunned(duration: float) -> void:
	transition(STUNNED, {"duration": duration})


## Event-driven aggression ("hunter alert"): investigate a rough player location.
func force_investigate(pos: Vector3) -> void:
	if state_name() in [CHASE, ATTACK, ALERT, STUNNED]:
		return
	transition(INVESTIGATE, {"position": pos})


func next_patrol_point() -> Vector3:
	if patrol_route.is_empty():
		return enemy.home_position
	var p := patrol_route[patrol_index % patrol_route.size()]
	return p


func advance_patrol() -> void:
	if not patrol_route.is_empty():
		patrol_index = (patrol_index + 1) % patrol_route.size()


func nearest_patrol_index(from: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in patrol_route.size():
		var d := from.distance_squared_to(patrol_route[i])
		if d < best_d:
			best_d = d
			best = i
	return best


static func state_id(s: StringName) -> int:
	return STATE_IDS.find(s)


static func state_from_id(i: int) -> StringName:
	return STATE_IDS[i] if i >= 0 and i < STATE_IDS.size() else IDLE
