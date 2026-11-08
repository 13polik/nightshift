class_name StunnedState
extends AIState
## Disabled by an arc emitter. Players get a window to escape; afterwards the Hunter
## searches around where it was hit.

var _duration := 3.0


func state_name() -> StringName:
	return EnemyBrain.STUNNED


func reacts_to_sight() -> bool:
	return false


func enter(data: Dictionary) -> void:
	_duration = float(data.get("duration", 3.0)) * (1.0 - enemy.data.stun_resistance)
	enemy.stop()
	enemy.emit_event(&"stunned")


func on_noise(_stimulus: Dictionary) -> bool:
	return true


func update(_delta: float) -> void:
	if elapsed >= _duration:
		enemy.perception.calm_down()
		goto(EnemyBrain.SEARCH, {"center": enemy.global_position})
