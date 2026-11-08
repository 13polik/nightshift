class_name AIState
extends RefCounted
## One behaviour state. States are plain objects owned by an EnemyBrain; new enemy types
## reuse, subclass or replace states without touching EnemyBase.

var brain: EnemyBrain
var enemy: EnemyBase
var elapsed := 0.0


## Unique name, used for transitions and replication.
func state_name() -> StringName:
	return &"STATE"


func enter(_data: Dictionary) -> void:
	pass


func exit() -> void:
	pass


func update(_delta: float) -> void:
	pass


## Return true when the stimulus was handled (prevents the brain's default reaction).
func on_noise(_stimulus: Dictionary) -> bool:
	return false


## Whether the generic "target spotted -> ALERT" reaction applies in this state.
func reacts_to_sight() -> bool:
	return true


func goto(state: StringName, data: Dictionary = {}) -> void:
	brain.transition(state, data)
