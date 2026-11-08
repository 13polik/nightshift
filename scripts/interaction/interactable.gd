class_name Interactable
extends Node3D
## Base class for anything a player can use. Clients only *request* interactions; the
## InteractionService validates range/state/requirements on the server, runs hold timers
## and broadcasts the resulting state to every peer.

signal state_changed
## Server-side: emitted after a successful interaction.
signal interacted(peer_id: int)

@export var prompt_key: String = "PROMPT_INTERACT"
@export var hold_time: float = 0.0
@export var interact_range: float = 2.4
@export var tag: StringName
## Noise radius while holding / on use (attracts enemies).
@export var noise_radius: float = 0.0
@export var allow_while_downed: bool = false
## Height of the focus point above the node origin (for prompts and range checks).
@export var focus_height: float = 1.0
## Handled entirely on the local client (e.g. reading notes); never sent to the server.
@export var local_only: bool = false

var net_id: int = -1
var enabled: bool = true
## Highlighted as the current objective target (drives HUD markers and outline).
var objective_active: bool = false
var service: Node # InteractionService (untyped to avoid a cyclic class reference)
var room_id: StringName


func focus_point() -> Vector3:
	return global_position + Vector3.UP * focus_height


## Localised prompt shown to `player` (client side).
func get_prompt(_player: Node) -> String:
	return tr(prompt_key)


## "" when allowed, otherwise a translation key explaining why not. Runs on clients for
## prediction and on the server for validation, so only use replicated state here.
func can_interact(_player: Node) -> String:
	return "" if enabled else "REASON_UNAVAILABLE"


## Whether the prompt should be shown at all (inactive objective devices stay silent).
func is_visible_to(_player: Node) -> bool:
	return enabled


func get_hold_time(_player: Node) -> float:
	return hold_time


## Server only. Override in subclasses; call super to emit `interacted`.
func server_interact(player: Node) -> void:
	interacted.emit(int(player.get("peer_id")))


## Server only: called every physics frame while a player holds this interaction.
func server_hold_tick(_player: Node, _progress: float) -> void:
	pass


func get_state() -> Dictionary:
	return {"e": enabled, "o": objective_active}


func apply_state(s: Dictionary) -> void:
	enabled = bool(s.get("e", enabled))
	objective_active = bool(s.get("o", objective_active))
	_on_state_applied()
	state_changed.emit()


## Visual refresh hook for subclasses.
func _on_state_applied() -> void:
	pass


## Server: push our current state to all peers.
func mark_dirty() -> void:
	if service and multiplayer.is_server():
		service.broadcast_state(self)
	_on_state_applied()
	state_changed.emit()


func set_enabled(v: bool) -> void:
	if enabled == v:
		return
	enabled = v
	mark_dirty()


func set_objective_active(v: bool) -> void:
	if objective_active == v:
		return
	objective_active = v
	mark_dirty()
