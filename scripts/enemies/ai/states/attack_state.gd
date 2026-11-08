class_name AttackState
extends AIState
## Wind-up, strike (hit check at the end of the wind-up), recover.

var _struck := false


func state_name() -> StringName:
	return EnemyBrain.ATTACK


func reacts_to_sight() -> bool:
	return false


func enter(_data: Dictionary) -> void:
	_struck = false
	enemy.stop()
	enemy.emit_event(&"attack")


func update(_delta: float) -> void:
	var t := brain.target
	if t and is_instance_valid(t):
		enemy.face(t.global_position)
	if not _struck and elapsed >= enemy.data.attack_windup:
		_struck = true
		if enemy.target_valid(t) and enemy.global_position.distance_to(t.global_position) <= enemy.data.attack_range * 1.3 and enemy.perception.has_line_of_sight(t):
			t.health.server_damage(enemy.data.attack_damage * (1.0 + brain.aggression * 0.15), enemy.global_position)
			enemy.emit_event(&"hit")
	if elapsed >= enemy.data.attack_windup + enemy.data.attack_cooldown * (1.0 - brain.aggression * 0.3):
		if enemy.target_valid(brain.target):
			goto(EnemyBrain.CHASE)
		else:
			goto(EnemyBrain.SEARCH, {"center": enemy.global_position, "duration": enemy.data.linger_after_down})
