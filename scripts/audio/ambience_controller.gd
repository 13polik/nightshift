class_name AmbienceController
extends Node
## Facility soundscape + adaptive music (client side, all peers).
##  * Ambient beds: low drone everywhere, vent air in corridors, electrical hum in powered
##    rooms (positional), drips underground, random distant mechanical noises / creaks.
##  * Tension layers driven by the Hunter's replicated state and distance, so audio tells
##    players how much danger they are in before they see anything.
##  * Alarm siren while the alarm flag is set.

var mission: Node
var _drone: AudioStreamPlayer
var _layers: Dictionary = {} # name -> AudioStreamPlayer
var _alarm: AudioStreamPlayer
var _heartbeat: AudioStreamPlayer
var _hums: Array[Dictionary] = [] # {player, zone}
var _distant_t := 8.0
var intensity := 0.0


func setup(p_mission: Node) -> void:
	mission = p_mission
	_drone = _bed("amb_drone", &"Ambience", -14.0)
	_layers.tension = _bed("music_tension", &"Music", -80.0)
	_layers.pulse = _bed("music_pulse", &"Music", -80.0)
	_layers.chase = _bed("music_chase", &"Music", -80.0)
	_heartbeat = _bed("heartbeat", &"SFX", -80.0)
	_alarm = _bed("alarm", &"SFX", -80.0)
	for room: Dictionary in mission.layout.rooms:
		var node: Node3D = mission.facility.room_info[room.id].node
		var aabb: AABB = mission.facility.room_info[room.id].aabb
		var center := aabb.get_center()
		if room.kind in ["corridor", "tunnel", "hall", "stairs"]:
			var vent := Audio.create_emitter(node, "amb_vent", -14.0, 16.0)
			vent.global_position = center + Vector3.UP * 1.5
		if not room.outdoor:
			var hum := Audio.create_emitter(node, "amb_hum", -18.0, 12.0)
			hum.global_position = center + Vector3.UP * 1.8
			_hums.append({"player": hum, "zone": room.power_zone})
	mission.state.flag_changed.connect(_on_flag)
	_update_hums()


func _bed(id: String, bus: StringName, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = Audio.cue(id)
	p.bus = bus
	p.volume_db = db
	add_child(p)
	if not Audio.muted_for_tests:
		p.play()
	return p


func _on_flag(flag: StringName, _value: Variant) -> void:
	if String(flag).begins_with("power_"):
		_update_hums()


func _update_hums() -> void:
	for h: Dictionary in _hums:
		var p: AudioStreamPlayer3D = h.player
		p.volume_db = -16.0 if mission.is_powered(h.zone) else -80.0


func _process(delta: float) -> void:
	if mission == null or mission.enemies == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var pos := cam.global_position
	var threat: Dictionary = mission.enemies.nearest_threat(pos)
	var d: float = threat.distance
	var st: StringName = threat.state
	var target := 0.0
	var chase := 0.0
	if st in [EnemyBrain.CHASE, EnemyBrain.ATTACK, EnemyBrain.ALERT] and d < 35.0:
		chase = 1.0
		target = 1.0
	elif st in [EnemyBrain.INVESTIGATE, EnemyBrain.SEARCH, EnemyBrain.LOST_TARGET] and d < 30.0:
		target = 0.65
	elif d < 20.0:
		target = 0.4
	target = maxf(target, float(mission.state.get_flag(&"threat", 0.0)) * 0.3)
	if mission.state.get_flag(&"evac", false):
		target = maxf(target, 0.7)
	intensity = lerpf(intensity, target, 1.0 - exp(-delta * (2.5 if target > intensity else 0.6)))
	_set_db(_layers.tension, lerpf(-40.0, -10.0, clampf(intensity * 1.5, 0.0, 1.0)), delta)
	_set_db(_layers.pulse, lerpf(-40.0, -6.0, clampf((intensity - 0.3) * 1.6, 0.0, 1.0)), delta)
	_set_db(_layers.chase, -4.0 if chase > 0.5 else -60.0, delta * 2.0)
	var near := clampf(1.0 - d / 12.0, 0.0, 1.0)
	_set_db(_heartbeat, lerpf(-50.0, -2.0, near), delta)
	_set_db(_alarm, -10.0 if mission.state.get_flag(&"alarm", false) else -80.0, delta * 3.0)
	_distant_t -= delta
	if _distant_t <= 0.0:
		_distant_t = randf_range(9.0, 22.0)
		var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		var cue: String = ["amb_distant", "amb_creak", "amb_drip"][randi() % 3]
		Audio.play_3d(cue, pos + dir * randf_range(10.0, 20.0), -6.0, 30.0)


func _set_db(p: AudioStreamPlayer, db: float, delta: float) -> void:
	p.volume_db = lerpf(p.volume_db, db, 1.0 - exp(-delta * 3.0))
