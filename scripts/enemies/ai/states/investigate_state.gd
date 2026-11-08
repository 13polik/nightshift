class_name InvestigateState
extends AIState
## Move to a stimulus (noise, glimpse, event). On arrival, search the area.

var _pos := Vector3.ZERO


func state_name() -> StringName:
	return EnemyBrain.INVESTIGATE


func enter(data: Dictionary) -> void:
	_pos = enemy.reachable_point(data.get("position", enemy.global_position))
	brain.investigate_position = _pos
	enemy.move_to(_pos, enemy.data.investigate_speed * enemy.speed_mult())
	enemy.emit_event(&"investigate")


func on_noise(stimulus: Dictionary) -> bool:
	# re-target to newer noises without restarting the state
	_pos = enemy.reachable_point(stimulus.position)
	brain.investigate_position = _pos
	enemy.move_to(_pos, enemy.data.investigate_speed * enemy.speed_mult())
	return true


func update(_delta: float) -> void:
	if enemy.arrived() or enemy.is_stuck() or elapsed > 25.0:
		goto(EnemyBrain.SEARCH, {"center": _pos})
