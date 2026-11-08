class_name PlayerHealth
extends Node
## Server-authoritative health / downed / revive / death state for one player.
## Clients receive state through _rpc_sync and only use it for presentation.

enum State { ALIVE, DOWNED, DEAD, EXTRACTED }

signal health_changed(health: float, max_health: float)
signal state_changed(new_state: int, old_state: int)
signal damaged(amount: float, source_position: Vector3)
signal revive_progress_changed(progress: float)

var player: Node3D # PlayerCharacter
var state: State = State.ALIVE
var health: float = 100.0
var max_health: float = 100.0
var bleed_left: float = 45.0
var revive_progress: float = 0.0
var reviver: int = 0
var _invuln := 0.0
var _revive_seen := 0.0
var _sync_t := 0.0
## stats: times this player revived someone (for rewards)
var revives_given := 0


func setup(p_player: Node3D, stats: PlayerStatsData) -> void:
	player = p_player
	max_health = stats.max_health
	health = max_health
	bleed_left = stats.bleed_out_time


func is_alive() -> bool:
	return state == State.ALIVE


func is_downed() -> bool:
	return state == State.DOWNED


func is_active() -> bool:
	return state == State.ALIVE or state == State.DOWNED


# --- server ---------------------------------------------------------------------------

func server_damage(amount: float, source_position: Vector3) -> void:
	if not multiplayer.is_server() or state != State.ALIVE or _invuln > 0.0:
		return
	health = maxf(0.0, health - amount)
	_rpc_damaged.rpc(amount, source_position)
	if health <= 0.0:
		_set_state(State.DOWNED)
		bleed_left = player.stats.bleed_out_time
		revive_progress = 0.0
	_broadcast()


func server_heal(amount: float) -> void:
	if not multiplayer.is_server() or state != State.ALIVE:
		return
	health = minf(max_health, health + amount)
	_broadcast()


func server_set_revive_progress(p: float, by_peer: int) -> void:
	if state != State.DOWNED:
		return
	revive_progress = p
	reviver = by_peer
	_revive_seen = 0.35
	_broadcast()


func server_revive(by_peer: int) -> void:
	if state != State.DOWNED:
		return
	health = player.stats.revive_health
	revive_progress = 0.0
	_invuln = player.stats.invulnerable_after_revive
	var rescuer: Node = player.mission.get_player(by_peer) if player.mission else null
	if rescuer:
		rescuer.health.revives_given += 1
	_set_state(State.ALIVE)
	_broadcast()


func server_kill() -> void:
	if state == State.DEAD or state == State.EXTRACTED:
		return
	health = 0.0
	_set_state(State.DEAD)
	_broadcast()


func server_extract() -> void:
	if not is_active():
		return
	_set_state(State.EXTRACTED)
	_broadcast()


func _set_state(s: State) -> void:
	if s == state:
		return
	var old := state
	state = s
	state_changed.emit(s, old)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_invuln = maxf(0.0, _invuln - delta)
	if state == State.DOWNED:
		if _revive_seen > 0.0:
			_revive_seen -= delta
			if _revive_seen <= 0.0:
				revive_progress = 0.0
				_broadcast()
		else:
			bleed_left -= delta
			if bleed_left <= 0.0:
				server_kill()
				return
		_sync_t += delta
		if _sync_t >= 1.0:
			_sync_t = 0.0
			_broadcast()


func _broadcast() -> void:
	if multiplayer.is_server():
		_rpc_sync.rpc(state, health, bleed_left, revive_progress)


## Full state for snapshots.
func get_state() -> Array:
	return [state, health, bleed_left, revive_progress]


# --- clients --------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _rpc_sync(p_state: int, p_health: float, p_bleed: float, p_revive: float) -> void:
	var old_state := state
	health = p_health
	bleed_left = p_bleed
	if not is_equal_approx(revive_progress, p_revive):
		revive_progress = p_revive
		revive_progress_changed.emit(p_revive)
	health_changed.emit(health, max_health)
	if p_state != old_state:
		state = p_state as State
		if not multiplayer.is_server():
			state_changed.emit(state, old_state)


@rpc("authority", "call_local", "reliable")
func _rpc_damaged(amount: float, source_position: Vector3) -> void:
	damaged.emit(amount, source_position)
