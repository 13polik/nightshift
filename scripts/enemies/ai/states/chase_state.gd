class_name ChaseState
extends AIState
## Pursue the target. Tracks it while visible; when sight is lost for longer than
## lose_target_time the Hunter falls back to the last known position (LOST_TARGET).

var _repath := 0.0


func state_name() -> StringName:
	return EnemyBrain.CHASE


func reacts_to_sight() -> bool:
	return false


func enter(_data: Dictionary) -> void:
	_repath = 0.0
	enemy.emit_event(&"chase")


func update(delta: float) -> void:
	var t := brain.target
	if not enemy.target_valid(t):
		# target went down / extracted / left: switch to someone visible, else linger
		var other := enemy.perception.most_aware_target()
		if other and enemy.perception.awareness_of(other) >= 0.6:
			brain.acquire(other)
			return
		goto(EnemyBrain.SEARCH, {"center": brain.last_known_position, "duration": enemy.data.linger_after_down})
		return
	var visible := enemy.perception.can_see(t)
	if visible:
		brain.last_known_position = t.global_position
		brain.last_known_velocity = t.velocity if t.is_local else t.remote_velocity
		brain.last_seen_time = enemy.now()
	var lose_time := enemy.data.lose_target_time * (1.0 + brain.aggression)
	if not visible and enemy.now() - brain.last_seen_time > lose_time:
		goto(EnemyBrain.LOST_TARGET)
		return
	var dist := enemy.global_position.distance_to(t.global_position)
	if visible and dist <= enemy.data.attack_range:
		goto(EnemyBrain.ATTACK)
		return
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.25
		var goal := t.global_position if visible or enemy.now() - brain.last_seen_time < 1.0 else brain.last_known_position
		enemy.move_to(goal, enemy.data.chase_speed * enemy.speed_mult())
