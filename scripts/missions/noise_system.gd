class_name NoiseSystem
extends Node
## Server-side sound propagation for AI. Everything audible to enemies goes through here:
## footsteps (derived from replicated movement), doors, interactions, machines, alarms.

signal noise_emitted(position: Vector3, loudness: float, kind: StringName, peer: int)

const FOOTSTEP_INTERVAL := 0.4

var mission: Node # MissionController
var _step_t := 0.0
var debug_count := 0


func emit_noise(pos: Vector3, loudness: float, kind: StringName, peer: int) -> void:
	if not multiplayer.is_server() or loudness <= 0.0:
		return
	debug_count += 1
	noise_emitted.emit(pos, loudness, kind, peer)
	for e: EnemyBase in mission.enemies.all():
		e.server_hear(pos, loudness, kind, peer)


## Loudness (radius in m) of a player's movement this instant (used by AI and the HUD).
static func movement_loudness(p: PlayerCharacter) -> float:
	if not p.is_active():
		return 0.0
	var speed := p.ground_speed()
	if speed < 0.4:
		return 0.0
	var s := p.stats
	if p.is_downed():
		return s.noise_crouch
	if p.is_crouched():
		return s.noise_crouch
	if p.is_sprinting() or speed > s.walk_speed * 1.25:
		return s.noise_sprint
	return s.noise_walk * clampf(speed / s.walk_speed, 0.4, 1.0)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or mission == null or not mission.running:
		return
	_step_t -= delta
	if _step_t > 0.0:
		return
	_step_t = FOOTSTEP_INTERVAL
	for p: PlayerCharacter in mission.get_players():
		var l := movement_loudness(p)
		if l > 0.0:
			emit_noise(p.global_position, l, &"footstep", p.peer_id)
