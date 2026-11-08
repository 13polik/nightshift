class_name IdleState
extends AIState
## Stand still, listen, look around. Then patrol.

var _duration := 3.0


func state_name() -> StringName:
	return EnemyBrain.IDLE


func enter(data: Dictionary) -> void:
	enemy.stop()
	_duration = float(data.get("duration", randf_range(enemy.data.idle_time_min, enemy.data.idle_time_max)))


func update(_delta: float) -> void:
	enemy.look_around(elapsed)
	if elapsed >= _duration:
		goto(EnemyBrain.PATROL)
