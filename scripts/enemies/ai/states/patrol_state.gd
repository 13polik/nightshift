class_name PatrolState
extends AIState
## Walk the assigned patrol route, pausing occasionally at waypoints.


func state_name() -> StringName:
	return EnemyBrain.PATROL


func enter(_data: Dictionary) -> void:
	enemy.move_to(brain.next_patrol_point(), enemy.data.patrol_speed)


func update(_delta: float) -> void:
	if enemy.arrived() or enemy.is_stuck():
		brain.advance_patrol()
		if randf() < 0.3:
			goto(EnemyBrain.IDLE, {"duration": randf_range(1.5, 3.5)})
			return
		enemy.move_to(brain.next_patrol_point(), enemy.data.patrol_speed)
