class_name ReturnToPatrolState
extends AIState
## Walk back to the nearest point of a patrol route (possibly a different route).


func state_name() -> StringName:
	return EnemyBrain.RETURN_TO_PATROL


func enter(_data: Dictionary) -> void:
	brain.target = null
	enemy.perception.calm_down()
	enemy.maybe_switch_route()
	brain.patrol_index = brain.nearest_patrol_index(enemy.global_position)
	enemy.move_to(brain.next_patrol_point(), enemy.data.patrol_speed)


func update(_delta: float) -> void:
	if enemy.arrived() or enemy.is_stuck():
		brain.advance_patrol()
		goto(EnemyBrain.PATROL)
