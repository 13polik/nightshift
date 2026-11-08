class_name SearchState
extends AIState
## Sweep random reachable points around the last known location, pausing to listen.

var _duration := 18.0
var _pause := 0.0


func state_name() -> StringName:
	return EnemyBrain.SEARCH


func enter(data: Dictionary) -> void:
	brain.search_center = data.get("center", enemy.global_position)
	_duration = float(data.get("duration", enemy.data.search_duration * (1.0 + brain.aggression * 0.5)))
	_pause = randf_range(0.8, 1.6)
	enemy.stop()


func update(delta: float) -> void:
	if elapsed >= _duration:
		goto(EnemyBrain.RETURN_TO_PATROL)
		return
	if _pause > 0.0:
		_pause -= delta
		enemy.look_around(elapsed)
		if _pause <= 0.0:
			var radius := enemy.data.search_radius * (1.0 + brain.aggression * 0.4)
			enemy.move_to(enemy.random_nav_point_near(brain.search_center, radius), enemy.data.search_speed * enemy.speed_mult())
		return
	if enemy.arrived() or enemy.is_stuck():
		_pause = randf_range(1.0, 2.5)
		enemy.stop()
