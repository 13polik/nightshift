class_name ElevatorPanel
extends Interactable
## Calls the elevator between two levels. Requires power and (if the mission's route lock
## picked the elevator) a keycard. Everyone standing in the car rides along; the server
## commands each owning client to move, keeping movement authority consistent.

signal ride_started
signal ride_finished

const RIDE_TIME := 4.0
const DOOR_TIME := 1.2

var link: ElevatorPanel
var car_aabb: AABB          # world-space car volume on this level
var power_zone: StringName = &"main"
var needs_keycard := false
var unlocked := false
var moving := false
var visual: DeviceVisual
var _ride_t := -1.0


func setup(p_tag: StringName, p_car: AABB, zone: StringName) -> void:
	tag = p_tag
	car_aabb = p_car
	power_zone = zone
	prompt_key = "PROMPT_ELEVATOR"
	interact_range = 2.2
	focus_height = 1.3
	noise_radius = 10.0
	visual = DeviceVisual.new()
	add_child(visual)
	visual.build("elevator_panel")


func can_interact(player: Node) -> String:
	if not enabled:
		return "REASON_UNAVAILABLE"
	if moving or (link and link.moving):
		return "REASON_ELEVATOR_MOVING"
	if service and service.mission and not service.mission.is_powered(power_zone):
		return "REASON_NO_POWER"
	if service and service.mission and not service.mission.state.get_flag(&"elevator_online", true):
		return "REASON_SYSTEM_OFFLINE"
	if needs_keycard and not unlocked:
		var inv: Variant = player.get("inventory") if player else null
		if inv == null or not inv.has_item(&"keycard"):
			return "REASON_NEEDS_KEYCARD"
	return ""


func get_prompt(player: Node) -> String:
	var r := can_interact(player)
	return tr(r) if not r.is_empty() else tr(prompt_key)


func get_hold_time(_player: Node) -> float:
	return 0.6


func server_interact(player: Node) -> void:
	if needs_keycard:
		unlocked = true
		if link:
			link.unlocked = true
			link.mark_dirty()
	moving = true
	_ride_t = 0.0
	mark_dirty()
	ride_started.emit()
	super.server_interact(player)


func _physics_process(delta: float) -> void:
	if _ride_t < 0.0 or not multiplayer.is_server():
		return
	_ride_t += delta
	if _ride_t >= DOOR_TIME and _ride_t - delta < DOOR_TIME:
		_transport()
	if _ride_t >= RIDE_TIME:
		_ride_t = -1.0
		moving = false
		mark_dirty()
		ride_finished.emit()


func _transport() -> void:
	if link == null or service == null or service.mission == null:
		return
	var offset := link.car_aabb.get_center() - car_aabb.get_center()
	for p: Node3D in service.mission.get_players():
		if p.call("is_extracted"):
			continue
		var grown := car_aabb.grow(0.4)
		if grown.has_point(p.global_position + Vector3.UP * 0.5):
			p.call("server_teleport", p.global_position + offset)


func get_state() -> Dictionary:
	var s := super.get_state()
	s.mv = moving
	s.ul = unlocked
	s.kc = needs_keycard
	return s


func apply_state(s: Dictionary) -> void:
	var was := moving
	moving = bool(s.get("mv", moving))
	unlocked = bool(s.get("ul", unlocked))
	needs_keycard = bool(s.get("kc", needs_keycard))
	if moving and not was:
		Audio.play_3d("elevator", global_position, -2.0, 18.0)
	super.apply_state(s)


func _on_state_applied() -> void:
	if visual:
		var powered: bool = service == null or service.mission == null or service.mission.is_powered(power_zone)
		visual.set_status(not moving and powered and (unlocked or not needs_keycard), powered, false)


func refresh_power() -> void:
	_on_state_applied()
