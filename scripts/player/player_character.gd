class_name PlayerCharacter
extends CharacterBody3D
## Networked third-person survivor.
##
## Authority model:
##  * Movement: the owning peer simulates its own body (responsive on mobile) and streams
##    state to the server at 20 Hz. The server validates speed/teleports, then relays to
##    the other peers, who interpolate ~100 ms in the past.
##  * Health, inventory, flashlight battery, interactions: server authoritative.

signal pose_changed(pose: int)

const SEND_RATE := 20.0
const INTERP_DELAY := 0.1
const SPEED_TOLERANCE := 1.6
const FLAG_SPRINT := 1
const FLAG_CROUCH := 2
const FLAG_LIGHT := 4
const FLAG_INTERACT := 8
const FLAG_REVIVE := 16

var peer_id: int = 1
var is_local := false
var info: Dictionary = {}
var stats: PlayerStatsData
var mission: Node # MissionController

@onready var health: PlayerHealth = $Health
@onready var inventory: PlayerInventory = $Inventory
@onready var flashlight: PlayerFlashlight = $Flashlight
@onready var visual_root: Node3D = $VisualRoot
@onready var revive_point: ReviveInteractable = $Revive

var visual: CharacterVisual
var camera: PlayerCamera
var interactor: PlayerInteractor
var bot: Node

# owner simulation
var sprinting := false
var crouched := false
var stamina := 100.0
var look_pitch := 0.0
var _stamina_delay := 0.0
var _send_t := 0.0
var _seq := 0
var speed_ratio := 0.0
var _was_on_floor := true
var _was_using := false

# remote interpolation
var _snapshots: Array = []
var remote_velocity := Vector3.ZERO
var net_flags := 0

# server validation
var _srv_last_pos := Vector3.ZERO
var _srv_last_t := 0.0
var _srv_seq := -1
var _teleport_grace := 0.0


func setup(p_peer: int, p_info: Dictionary, p_mission: Node) -> void:
	peer_id = p_peer
	info = p_info
	mission = p_mission
	name = str(p_peer)
	is_local = p_peer == Net.local_id()
	stats = (Content.player_stats if Content.player_stats else PlayerStatsData.new()).duplicate()
	var perk := Content.perk(StringName(str(info.get("perk", ""))))
	if perk:
		perk.apply_to(stats)


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 32
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.45
	health.setup(self, stats)
	inventory.setup(self, stats.inventory_slots)
	flashlight.setup(self, stats, is_local)
	revive_point.owner_player = self
	_build_visual()
	health.state_changed.connect(_on_health_state)
	health.damaged.connect(_on_damaged)
	_srv_last_pos = global_position
	_srv_last_t = _now()
	if is_local:
		camera = PlayerCamera.new()
		camera.name = "Camera"
		add_child(camera)
		camera.global_position = global_position + Vector3.UP * 1.5
		camera.yaw = rotation_degrees.y
		camera.set_target(self)
		interactor = PlayerInteractor.new()
		interactor.name = "Interactor"
		add_child(interactor)
		interactor.setup(self, mission.interactions)
		GameInput.action_pressed.connect(_on_action_pressed)
		GameInput.action_released.connect(_on_action_released)
		stamina = stats.stamina_max
		if CmdArgs.has("bot"):
			bot = PlayerTestBot.new()
			add_child(bot)


func _build_visual() -> void:
	var model_path := "res://data/player/character_model.tres"
	var scene: PackedScene = null
	if ResourceLoader.exists(model_path):
		var cm: CharacterModelData = load(model_path)
		scene = cm.scene if cm else null
	if scene:
		visual = scene.instantiate()
	else:
		visual = ProceduralSurvivorVisual.new()
	visual_root.add_child(visual)
	visual.apply_cosmetics(info.get("cosmetics", {}))
	visual.footstep.connect(_on_footstep)
	inventory.changed.connect(func() -> void:
		_refresh_held_item()
		var using := inventory.using_slot >= 0
		if using and not _was_using and visual:
			visual.play_action(&"use_item")
		_was_using = using)


## The selected inventory item is shown in the character's hand on every peer
## (selection + slots are replicated by PlayerInventory).
func _refresh_held_item() -> void:
	if visual == null:
		return
	var data := inventory.slot_item(inventory.selected)
	visual.set_held_item(data.id if data else &"")


func display_name() -> String:
	return str(info.get("name", "?"))


func can_act() -> bool:
	return health.state == PlayerHealth.State.ALIVE


func is_downed() -> bool:
	return health.state == PlayerHealth.State.DOWNED


func is_dead() -> bool:
	return health.state == PlayerHealth.State.DEAD


func is_extracted() -> bool:
	return health.state == PlayerHealth.State.EXTRACTED


func is_active() -> bool:
	return health.is_active()


func current_pose() -> int:
	match health.state:
		PlayerHealth.State.DOWNED:
			return CharacterVisual.Pose.DOWNED
		PlayerHealth.State.DEAD:
			return CharacterVisual.Pose.DEAD
		PlayerHealth.State.EXTRACTED:
			return CharacterVisual.Pose.HIDDEN
	return CharacterVisual.Pose.CROUCH if _flag(FLAG_CROUCH) else CharacterVisual.Pose.STAND


func _flag(f: int) -> bool:
	if is_local:
		match f:
			FLAG_SPRINT: return sprinting
			FLAG_CROUCH: return crouched
			FLAG_LIGHT: return flashlight.on
	return (net_flags & f) != 0


func is_sprinting() -> bool:
	return _flag(FLAG_SPRINT)


func is_crouched() -> bool:
	return _flag(FLAG_CROUCH)


func is_flashlight_on() -> bool:
	return flashlight.on


## Horizontal speed in m/s (works for local and remote players).
func ground_speed() -> float:
	var v := velocity if is_local else remote_velocity
	return Vector2(v.x, v.z).length()


func aim_direction() -> Vector3:
	return Basis.from_euler(Vector3(look_pitch, rotation.y, 0)) * Vector3.FORWARD


# --- input (local) --------------------------------------------------------------------

func _on_action_pressed(action: StringName) -> void:
	if not is_local:
		return
	match action:
		&"crouch":
			if Settings.get_value("controls", "crouch_toggle"):
				crouched = not crouched
			else:
				crouched = true
			if crouched:
				sprinting = false
		&"sprint":
			if Settings.get_value("controls", "sprint_toggle"):
				sprinting = not sprinting
			else:
				sprinting = true
			if sprinting:
				crouched = false
		&"flashlight":
			if not is_dead() and not is_extracted():
				flashlight.set_on(not flashlight.on)
		&"use_item":
			if inventory.using_slot >= 0:
				inventory.request_cancel_use()
			else:
				inventory.request_use(inventory.selected)
		&"drop_item":
			inventory.request_drop(inventory.selected)
		&"next_item":
			inventory.request_select((inventory.selected + 1) % inventory.slots.size())
		&"slot_1", &"slot_2", &"slot_3", &"slot_4":
			var idx := int(String(action).substr(5)) - 1
			if idx < inventory.slots.size():
				inventory.request_select(idx)
		&"ping":
			mission.request_ping(self)


func _on_action_released(action: StringName) -> void:
	if not is_local:
		return
	if action == &"sprint" and not Settings.get_value("controls", "sprint_toggle"):
		sprinting = false
	if action == &"crouch" and not Settings.get_value("controls", "crouch_toggle"):
		crouched = false


# --- simulation -----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_local:
		_simulate_local(delta)
		_send_t += delta
		if _send_t >= 1.0 / SEND_RATE:
			_send_t = 0.0
			_send_state()
	else:
		_interpolate_remote()
	_update_presentation(delta)
	if multiplayer.is_server():
		_teleport_grace = maxf(0.0, _teleport_grace - delta)


func _simulate_local(delta: float) -> void:
	var input: Vector2 = GameInput.move_vector() if bot == null else bot.call("move_vector")
	var can_move := health.state == PlayerHealth.State.ALIVE or health.state == PlayerHealth.State.DOWNED
	if interactor and interactor.is_holding():
		can_move = false
	if inventory.using_slot >= 0:
		input *= 0.35
	if not can_move:
		input = Vector2.ZERO
	var downed := is_downed()
	if downed:
		sprinting = false
		crouched = false
	# stamina
	var moving := input.length() > 0.1
	var want_sprint := sprinting and moving and not crouched and not downed
	if want_sprint and stamina > 0.0:
		stamina = maxf(0.0, stamina - stats.stamina_drain * delta)
		_stamina_delay = stats.stamina_regen_delay
		if stamina <= 0.0:
			sprinting = false
	else:
		_stamina_delay -= delta
		if _stamina_delay <= 0.0:
			stamina = minf(stats.stamina_max, stamina + stats.stamina_regen * delta)
	var actually_sprinting := want_sprint and stamina > 0.0
	var speed := stats.walk_speed
	if downed:
		speed = stats.downed_speed
	elif crouched:
		speed = stats.crouch_speed
	elif actually_sprinting:
		speed = stats.sprint_speed
	speed *= input.length()
	var basis_flat := camera.flat_basis() if camera else Basis.IDENTITY
	var dir := basis_flat * Vector3(input.x, 0, input.y)
	dir.y = 0
	if dir.length() > 0.001:
		dir = dir.normalized()
	var target_v := dir * speed
	var accel := stats.acceleration if is_on_floor() else stats.acceleration * stats.air_control
	velocity.x = move_toward(velocity.x, target_v.x, accel * delta * maxf(speed, 1.0))
	velocity.z = move_toward(velocity.z, target_v.z, accel * delta * maxf(speed, 1.0))
	if not is_on_floor():
		velocity.y -= stats.gravity * delta
	else:
		velocity.y = maxf(velocity.y, -0.5)
	move_and_slide()
	if is_on_floor() and not _was_on_floor and velocity.y < -4.0:
		Audio.play_3d("step_player", global_position, 0.0, 12.0)
	_was_on_floor = is_on_floor()
	# facing: toward movement, or toward the camera when standing still
	var face_yaw := rotation.y
	if dir.length() > 0.1:
		face_yaw = atan2(-dir.x, -dir.z)
	elif camera:
		face_yaw = deg_to_rad(camera.yaw)
	rotation.y = lerp_angle(rotation.y, face_yaw, 1.0 - exp(-delta * (12.0 if dir.length() > 0.1 else 4.0)))
	if camera:
		look_pitch = deg_to_rad(camera.pitch)
		camera.set_sprint(actually_sprinting)
		camera.set_pose_height(current_pose())
	speed_ratio = Vector2(velocity.x, velocity.z).length() / stats.walk_speed
	if global_position.y < -30.0:
		Log.w("player", "fell out of the world - respawning at spawn")
		global_position = mission.safe_respawn_point()
		velocity = Vector3.ZERO


func _send_state() -> void:
	_seq += 1
	var flags := (FLAG_SPRINT if sprinting and speed_ratio > 1.2 else 0) | (FLAG_CROUCH if crouched else 0) | (FLAG_LIGHT if flashlight.on else 0) | _work_flags()
	if multiplayer.is_server():
		_rpc_state.rpc(global_position, velocity, rotation.y, look_pitch, flags, _seq)
	else:
		_srv_state.rpc_id(1, global_position, velocity, rotation.y, look_pitch, flags, _seq)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _srv_state(pos: Vector3, vel: Vector3, yaw: float, pitch: float, flags: int, seq: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id:
		return
	if seq <= _srv_seq:
		return
	_srv_seq = seq
	var now := _now()
	var dt := maxf(now - _srv_last_t, 0.02)
	var max_speed := stats.sprint_speed * SPEED_TOLERANCE + 2.0
	var moved := Vector2(pos.x - _srv_last_pos.x, pos.z - _srv_last_pos.z).length()
	if _teleport_grace <= 0.0 and moved > max_speed * dt + 0.75 and dt < 1.0:
		Log.w("net", "peer %d moved %.1fm in %.2fs - correcting" % [peer_id, moved, dt])
		_rpc_correct.rpc_id(peer_id, _srv_last_pos)
		return
	if not pos.is_finite() or not is_finite(yaw):
		return
	_srv_last_pos = pos
	_srv_last_t = now
	_push_snapshot(pos, vel, yaw, pitch, flags)
	_rpc_state.rpc(pos, vel, yaw, pitch, flags, seq)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_state(pos: Vector3, vel: Vector3, yaw: float, pitch: float, flags: int, _seq_in: int) -> void:
	if is_local:
		return
	_push_snapshot(pos, vel, yaw, pitch, flags)


@rpc("authority", "call_remote", "reliable")
func _rpc_correct(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO


## Server: move a player (elevator ride, unstuck). Works for any owner.
func server_teleport(pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	_teleport_grace = 1.5
	_srv_last_pos = pos
	_srv_last_t = _now()
	if is_local:
		global_position = pos
		velocity = Vector3.ZERO
	else:
		global_position = pos
		_snapshots.clear()
		_rpc_correct.rpc_id(peer_id, pos)


## Server: small message for this player (e.g. "full health").
func server_notify(reason_key: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		_rpc_notify(reason_key)
	else:
		_rpc_notify.rpc_id(peer_id, reason_key)


@rpc("authority", "call_remote", "reliable")
func _rpc_notify(reason_key: String) -> void:
	Events.toast(reason_key, Events.ToastKind.WARNING)
	Audio.play_ui("ui_error", -6.0)


func _push_snapshot(pos: Vector3, vel: Vector3, yaw: float, pitch: float, flags: int) -> void:
	_snapshots.append({"t": _now(), "pos": pos, "vel": vel, "yaw": yaw, "pitch": pitch, "flags": flags})
	if _snapshots.size() > 12:
		_snapshots.pop_front()
	var light_on := (flags & FLAG_LIGHT) != 0
	if light_on != flashlight.on:
		flashlight.set_on(light_on)
	net_flags = flags


func _interpolate_remote() -> void:
	if _snapshots.is_empty():
		return
	var render_t := _now() - INTERP_DELAY
	var a: Dictionary = _snapshots[0]
	var b: Dictionary = a
	for i in range(_snapshots.size() - 1, -1, -1):
		if float(_snapshots[i].t) <= render_t:
			a = _snapshots[i]
			b = _snapshots[mini(i + 1, _snapshots.size() - 1)]
			break
	var span := float(b.t) - float(a.t)
	var k := 1.0 if span <= 0.0001 else clampf((render_t - float(a.t)) / span, 0.0, 1.0)
	var pos: Vector3 = (a.pos as Vector3).lerp(b.pos, k)
	if a == b and render_t > float(a.t):
		pos += (a.vel as Vector3) * clampf(render_t - float(a.t), 0.0, 0.25)
	global_position = pos
	rotation.y = lerp_angle(float(a.yaw), float(b.yaw), k)
	look_pitch = lerpf(float(a.pitch), float(b.pitch), k)
	remote_velocity = (a.vel as Vector3).lerp(b.vel, k)
	speed_ratio = Vector2(remote_velocity.x, remote_velocity.z).length() / stats.walk_speed


## Interaction animations: derived locally for the owner, replicated via state flags.
func _work_flags() -> int:
	if interactor == null or not interactor.is_holding():
		return 0
	return FLAG_REVIVE if interactor.holding is ReviveInteractable else FLAG_INTERACT


func _update_presentation(_delta: float) -> void:
	if visual:
		visual.set_motion(speed_ratio, current_pose(), is_sprinting())
		visual.set_look_pitch(look_pitch)
		var wf := _work_flags() if is_local else (net_flags & (FLAG_INTERACT | FLAG_REVIVE))
		var work := &"none"
		if can_act():
			if wf & FLAG_REVIVE:
				work = &"revive"
			elif wf & FLAG_INTERACT:
				work = &"interact"
		visual.play_action(work)
	var anchor := visual.flashlight_anchor() if visual else self
	var aim := camera.aim_direction() if camera else aim_direction()
	flashlight.set_aim(anchor.global_position + Vector3.UP * 0.05, aim)
	collision_layer = 2 if is_active() else 0


func _on_footstep(strength: float) -> void:
	var vol := -14.0 + strength * 7.0
	Audio.play_3d("step_player", global_position, vol, 8.0 + strength * 8.0, randf_range(0.9, 1.1))


func _on_damaged(amount: float, source_position: Vector3) -> void:
	Audio.play_3d("player_hurt", global_position + Vector3.UP, 0.0, 15.0)
	if visual and can_act():
		visual.play_action(&"hit")
	if camera:
		camera.add_trauma(clampf(amount / 40.0, 0.2, 0.9))
	if is_local and Settings.get_value("controls", "haptics") and Settings.is_mobile():
		Input.vibrate_handheld(180)
	mission.on_player_damaged(self, amount, source_position)


func _on_health_state(new_state: int, _old: int) -> void:
	pose_changed.emit(current_pose())
	if new_state == PlayerHealth.State.DOWNED:
		Audio.play_3d("downed", global_position, 0.0, 25.0)
		if is_local:
			crouched = false
			sprinting = false
	elif new_state == PlayerHealth.State.EXTRACTED or new_state == PlayerHealth.State.DEAD:
		flashlight.set_on(false)
		if interactor:
			interactor.cancel()
	mission.on_player_state_changed(self, new_state)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
