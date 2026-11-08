class_name AlertState
extends AIState
## Telegraph: the Hunter freezes, faces its prey and screeches before charging. This gives
## players a fair moment to react.


func state_name() -> StringName:
	return EnemyBrain.ALERT


func reacts_to_sight() -> bool:
	return false


func enter(_data: Dictionary) -> void:
	enemy.stop()
	enemy.emit_event(&"alert")


func update(_delta: float) -> void:
	if brain.target and is_instance_valid(brain.target):
		enemy.face(brain.target.global_position)
	if elapsed >= enemy.data.alert_duration * (1.0 - brain.aggression * 0.4):
		if enemy.target_valid(brain.target):
			goto(EnemyBrain.CHASE)
		else:
			goto(EnemyBrain.SEARCH, {"center": brain.last_known_position})
