class_name LostTargetState
extends AIState
## Go to where the target was last seen (extrapolated a little), then search there.

var _goal := Vector3.ZERO


func state_name() -> StringName:
	return EnemyBrain.LOST_TARGET


func enter(_data: Dictionary) -> void:
	var v := brain.last_known_velocity
	v.y = 0
	_goal = enemy.reachable_point(brain.last_known_position + v.limit_length(4.0) * 1.2)
	enemy.move_to(_goal, enemy.data.investigate_speed * 1.2 * enemy.speed_mult())
	enemy.emit_event(&"lost")


func update(_delta: float) -> void:
	if enemy.arrived() or enemy.is_stuck() or elapsed > 15.0:
		goto(EnemyBrain.SEARCH, {"center": _goal})
