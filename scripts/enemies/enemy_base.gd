class_name EnemyBase
extends CharacterBody3D
## Generic networked enemy body. The server runs perception + brain + navigation; clients
## receive compact snapshots from EnemyManager and only interpolate and present.

signal ai_event(event_name: StringName)

const PERCEPTION_HZ := 10.0
const DOOR_CHECK_INTERVAL := 0.2

var enemy_id: int = 0
var data: EnemyData
var brain: EnemyBrain
var perception: EnemyPerception
var mission: Node # MissionController
var noise: Node # NoiseSystem
var agent: NavigationAgent3D
var visual: CharacterVisual
var home_position := Vector3.ZERO
var active := false
var replicated_state: StringName = &"IDLE"

var _move_speed := 0.0
var _has_target := false
var _perception_t := 0.0
var _stuck_t := 0.0
var _progress_ref := Vector3.ZERO
var _stuck := false
var _door_t := 0.0
var _bash_door: Door
var _bash_t := 0.0
var _door_wait := 0.0
var _face_override := Vector3.INF
var _look_yaw := 0.0
var _route_index := 0
var _move_frames := 0
var _sim_time := 0.0

# client interpolation
var _snapshots: Array = []
var replicated_speed := 0.0


func setup(p_id: int, p_data: EnemyData, p_mission: Node) -> void:
	enemy_id = p_id
	data = p_data
	mission = p_mission
	name = "Enemy_%d" % p_id
	collision_layer = 4
	collision_mask = 1 | 32
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.5


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 2.3
	shape.shape = cap
	shape.position.y = 1.15
	add_child(shape)
	visual = data.scene.instantiate() as CharacterVisual if data.scene else HunterVisual.new()
	if visual == null:
		Log.e("ai", "enemy scene for %s does not extend CharacterVisual - using dev visual" % data.id)
		visual = HunterVisual.new()
	add_child(visual)
	visual.footstep.connect(_on_footstep)
	if multiplayer.is_server():
		agent = NavigationAgent3D.new()
		agent.path_desired_distance = 0.7
		agent.target_desired_distance = 0.9
		agent.path_max_distance = 3.0
		agent.avoidance_enabled = false
		agent.height = 2.3
		agent.radius = 0.45
		add_child(agent)
		perception = EnemyPerception.new(self)
		var script: Script = data.brain_script if data.brain_script else HunterBrain
		brain = script.new()
		brain.setup(self)
		brain.state_changed.connect(_on_state_changed)


## Presence sounds (all peers). Audio is the players' main early-warning system, so it
## is driven by the replicated AI state and layered by distance:
##   close (<10 m)  wet breathing loop        mid (<24 m) sub-bass presence rumble
##   any range      chitin clicks when calm/searching, growls while hunting, heavy steps
var _voice_t := 3.0
var _breath: AudioStreamPlayer3D
var _presence: AudioStreamPlayer3D


func _process(delta: float) -> void:
	if _breath == null:
		_breath = Audio.create_emitter(self, "hunter_breath", -80.0, 10.0, &"SFX")
		_breath.position.y = 2.0
		_presence = Audio.create_emitter(self, "hunter_presence", -80.0, 24.0, &"SFX")
		_presence.position.y = 1.0
	var calm := replicated_state in [EnemyBrain.IDLE, EnemyBrain.PATROL, EnemyBrain.RETURN_TO_PATROL, EnemyBrain.SEARCH, EnemyBrain.INVESTIGATE]
	var hunting := replicated_state in [EnemyBrain.CHASE, EnemyBrain.ATTACK, EnemyBrain.ALERT, EnemyBrain.LOST_TARGET]
	var shown := visible_in_world()
	_breath.volume_db = lerpf(_breath.volume_db, (-1.0 if calm else -10.0) if shown else -80.0, 1.0 - exp(-delta * 3.0))
	_presence.volume_db = lerpf(_presence.volume_db, (2.0 if hunting else -9.0) if shown else -80.0, 1.0 - exp(-delta * 2.0))
	_voice_t -= delta
	if _voice_t > 0.0 or not visible_in_world():
		return
	match replicated_state:
		EnemyBrain.CHASE, EnemyBrain.LOST_TARGET:
			_voice_t = randf_range(2.5, 4.0)
			Audio.play_3d("hunter_growl", global_position + Vector3.UP * 2.0, 0.0, 30.0, randf_range(0.85, 1.05))
		EnemyBrain.INVESTIGATE, EnemyBrain.SEARCH:
			_voice_t = randf_range(3.0, 6.0)
			Audio.play_3d("hunter_click", global_position + Vector3.UP * 2.0, -2.0, 18.0, randf_range(0.9, 1.1))
		_:
			_voice_t = randf_range(5.0, 10.0)
			Audio.play_3d("hunter_click", global_position + Vector3.UP * 2.0, -6.0, 14.0, randf_range(0.8, 1.0))


func visible_in_world() -> bool:
	return visual != null and visual.visible


## Simulation clock for AI memory/timers. Advances with physics steps, so hitches,
## pauses or time scaling never make the Hunter "forget" or "remember" wrongly.
func now() -> float:
	return _sim_time


## Wall clock for network snapshot interpolation (arrival times are real time).
func wall_time() -> float:
	return Time.get_ticks_msec() / 1000.0


## Server: begin hunting.
func activate(route: PackedVector3Array) -> void:
	active = true
	home_position = global_position
	brain.patrol_route = route
	brain.start(EnemyBrain.PATROL if not route.is_empty() else EnemyBrain.IDLE)
	Log.i("ai", "%s activated (%d patrol points)" % [name, route.size()])


func set_aggression(a: float) -> void:
	if brain:
		brain.aggression = clampf(a, 0.0, 1.0)


func speed_mult() -> float:
	return 1.0 + (brain.aggression * 0.15 if brain else 0.0)


# --- movement API used by states ------------------------------------------------------

func move_to(pos: Vector3, speed: float) -> void:
	_move_speed = speed
	_has_target = true
	_stuck_t = 0.0
	_stuck = false
	_progress_ref = global_position
	_face_override = Vector3.INF
	_move_frames = 0
	agent.target_position = pos


func stop() -> void:
	_has_target = false
	_move_speed = 0.0
	_face_override = Vector3.INF


## NavigationAgent3D only refreshes its "finished" flag once the new path has been
## queried, so a target set this frame must not count as reached.
func arrived() -> bool:
	if not _has_target:
		return true
	if _move_frames < 3:
		return false
	return agent.is_navigation_finished()


func is_stuck() -> bool:
	return _stuck


func face(pos: Vector3) -> void:
	_face_override = pos


func look_around(t: float) -> void:
	_look_yaw = sin(t * 1.3) * 0.9


## Untyped on purpose: the target may be a player that just disconnected (freed object),
## which a typed parameter would reject before we can check it.
func target_valid(t: Variant) -> bool:
	return t != null and is_instance_valid(t) and bool((t as Object).call("can_act"))


func reachable_point(p: Vector3) -> Vector3:
	var map := get_world_3d().navigation_map
	return NavigationServer3D.map_get_closest_point(map, p)


func random_nav_point_near(center: Vector3, radius: float) -> Vector3:
	var map := get_world_3d().navigation_map
	for i in 6:
		var a := randf() * TAU
		var r := randf_range(radius * 0.3, radius)
		var cand := NavigationServer3D.map_get_closest_point(map, center + Vector3(cos(a) * r, 0, sin(a) * r))
		if absf(cand.y - center.y) < 2.0:
			return cand
	return NavigationServer3D.map_get_closest_point(map, center)


func maybe_switch_route() -> void:
	var routes: Array = mission.enemy_routes()
	if routes.size() > 1 and randf() < 0.4:
		_route_index = (_route_index + 1 + randi() % (routes.size() - 1)) % routes.size()
		brain.patrol_route = routes[_route_index]


func emit_event(event_name: StringName) -> void:
	if mission and mission.enemies:
		mission.enemies.broadcast_event(enemy_id, event_name)


func server_stun(duration: float) -> void:
	if brain and active:
		brain.on_stunned(duration)


func server_hear(pos: Vector3, loudness: float, kind: StringName, peer: int) -> void:
	if not active or perception == null:
		return
	var stim := perception.hear(pos, loudness, kind, peer)
	if not stim.is_empty():
		brain.on_noise(stim)


# --- server simulation ----------------------------------------------------------------

func server_tick(delta: float) -> void:
	if not active:
		return
	_perception_t -= delta
	if _perception_t <= 0.0:
		_perception_t = 1.0 / PERCEPTION_HZ
		perception.update(1.0 / PERCEPTION_HZ, mission.get_players())
	brain.update(delta)
	_move(delta)
	replicated_state = brain.state_name()


func _move(delta: float) -> void:
	_move_frames += 1
	var desired := Vector3.ZERO
	if _bash_door:
		_bash_t += delta
		if fmod(_bash_t, 0.7) < delta:
			emit_event(&"bash")
			if noise:
				noise.emit_noise(global_position, 16.0, &"bash", 0)
		if _bash_t >= data.door_bash_time:
			_bash_door.enemy_break()
			_bash_door = null
		face(_bash_door.global_position if _bash_door else global_position - global_basis.z)
	elif _door_wait > 0.0:
		_door_wait -= delta
	elif _has_target and not agent.is_navigation_finished():
		var next := agent.get_next_path_position()
		var to := next - global_position
		to.y = 0
		if to.length() > 0.05:
			desired = to.normalized() * _move_speed
		_door_t -= delta
		if _door_t <= 0.0:
			_door_t = DOOR_CHECK_INTERVAL
			_handle_doors(desired)
		# stuck detection
		_stuck_t += delta
		if _stuck_t >= 2.5:
			if global_position.distance_to(_progress_ref) < 0.6:
				_stuck = true
			_progress_ref = global_position
			_stuck_t = 0.0
	velocity.x = move_toward(velocity.x, desired.x, 18.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z, 18.0 * delta)
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	var face_dir := Vector3.ZERO
	if _face_override != Vector3.INF:
		face_dir = _face_override - global_position
	elif Vector2(velocity.x, velocity.z).length() > 0.2:
		face_dir = velocity
	if Vector2(face_dir.x, face_dir.z).length() > 0.05:
		var yaw := atan2(-face_dir.x, -face_dir.z)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-delta * data.turn_speed))
	elif _look_yaw != 0.0:
		rotation.y += _look_yaw * delta * 0.8


func _handle_doors(desired: Vector3) -> void:
	if desired.length() < 0.1:
		return
	var ahead := global_position + desired.normalized() * 1.2
	for door: Door in mission.facility.doors.values():
		if door.is_open:
			continue
		if door.global_position.distance_to(ahead) > 1.6:
			continue
		if door.enemy_open():
			_door_wait = 0.35
			emit_event(&"door")
		else:
			_bash_door = door
			_bash_t = 0.0
		return


func _on_state_changed(new_state: StringName, old_state: StringName) -> void:
	replicated_state = new_state
	Log.d("ai", "%s: %s -> %s" % [name, old_state, new_state])
	if mission and mission.enemies:
		mission.enemies.broadcast_state_change(enemy_id, new_state)


# --- client presentation --------------------------------------------------------------

func push_snapshot(pos: Vector3, yaw: float, speed: float) -> void:
	_snapshots.append({"t": wall_time(), "pos": pos, "yaw": yaw, "speed": speed})
	if _snapshots.size() > 10:
		_snapshots.pop_front()


func _physics_process(delta: float) -> void:
	_sim_time += delta
	if multiplayer.is_server():
		server_tick(delta)
		replicated_speed = Vector2(velocity.x, velocity.z).length()
	else:
		_interpolate()
	if visual:
		visual.set_motion(replicated_speed / 2.0, CharacterVisual.Pose.HIDDEN if not active else CharacterVisual.Pose.STAND, replicated_state == EnemyBrain.CHASE)
		if visual.has_method("set_ai_state"):
			visual.call("set_ai_state", replicated_state)


func _interpolate() -> void:
	if _snapshots.is_empty():
		return
	var render_t := wall_time() - 0.12
	var a: Dictionary = _snapshots[0]
	var b: Dictionary = a
	for i in range(_snapshots.size() - 1, -1, -1):
		if float(_snapshots[i].t) <= render_t:
			a = _snapshots[i]
			b = _snapshots[mini(i + 1, _snapshots.size() - 1)]
			break
	var span := float(b.t) - float(a.t)
	var k := 1.0 if span <= 0.0001 else clampf((render_t - float(a.t)) / span, 0.0, 1.0)
	global_position = (a.pos as Vector3).lerp(b.pos, k)
	rotation.y = lerp_angle(float(a.yaw), float(b.yaw), k)
	replicated_speed = lerpf(float(a.speed), float(b.speed), k)


func _on_footstep(strength: float) -> void:
	Audio.play_3d("step_hunter", global_position, -4.0 + strength * 4.0, 26.0, randf_range(0.85, 1.0))
