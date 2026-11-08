class_name PowerGrid
extends Node
## Facility power + light budget. Zones (main, underground, generator, exterior) are
## powered through mission flags. Lights are enabled only near the local camera and capped
## per quality preset (mobile renderers have strict per-object light limits).

const BUDGET_INTERVAL := 0.25

var mission: Node # MissionController
var facility: FacilityRuntime
var _budget_t := 0.0
var _t := 0.0
var _alarm := false
var _lit_rooms: Dictionary = {}


func setup(p_mission: Node, p_facility: FacilityRuntime) -> void:
	mission = p_mission
	facility = p_facility
	mission.state.flag_changed.connect(_on_flag)
	Events.graphics_quality_changed.connect(func(_q: int) -> void: _budget_t = 0.0)
	_refresh_all()


func is_zone_powered(zone: StringName) -> bool:
	if zone == &"exterior":
		return true
	return bool(mission.state.get_flag(StringName("power_" + String(zone)), false))


func is_room_lit(room: StringName) -> bool:
	return is_zone_powered(facility.zone_of_room(room))


func _on_flag(flag: StringName, value: Variant) -> void:
	if String(flag).begins_with("power_"):
		_refresh_all()
		var zone := String(flag).substr(6)
		if bool(value):
			Audio.play_2d("power_up", -4.0)
		else:
			Audio.play_2d("power_down", -2.0)
			_spark_near_camera(3)
		Log.i("power", "zone %s %s" % [zone, "ON" if value else "OFF"])
	elif flag == &"alarm":
		_alarm = bool(value)


func _refresh_all() -> void:
	for d: Door in facility.doors.values():
		d.refresh_power()
	for dev: ObjectiveDevice in facility.devices:
		dev.refresh_power()
	for e: ElevatorPanel in facility.elevators:
		e.refresh_power()
	for l: Dictionary in facility.lights:
		var powered := is_zone_powered(l.zone)
		var on: bool = powered != bool(l.emergency)
		if l.fixture is GeometryInstance3D:
			var mat := "emissive_white"
			if l.emergency:
				mat = "emissive_red" if on else "emissive_off"
			elif not on:
				mat = "emissive_off"
			(l.fixture as GeometryInstance3D).material_override = MaterialLibrary.get_mat(mat)
		l.on = on
	_budget_t = 0.0


func _process(delta: float) -> void:
	if facility == null:
		return
	_t += delta
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = randf_range(7.0, 16.0)
		if Effects.ambient_enabled():
			_spark_near_camera(1, true)
	_budget_t -= delta
	if _budget_t <= 0.0:
		_budget_t = BUDGET_INTERVAL
		_apply_budget()
	# per-frame cheap animation: flicker + alarm pulse
	for l: Dictionary in facility.lights:
		var light: Light3D = l.light
		if light == null or not light.visible:
			continue
		var e: float = l.base_energy
		if l.emergency and _alarm:
			e *= 0.6 + 0.6 * absf(sin(_t * 3.2))
		elif l.flicker:
			var n := sin(_t * 23.0 + float(light.get_instance_id() % 97)) * sin(_t * 7.3)
			e *= 0.15 if n > 0.82 else 1.0
		light.light_energy = e


var _spark_t := 8.0


## Sparks from fixtures near the camera (power cuts, flickering broken lights).
func _spark_near_camera(count: int, flicker_only: bool = false) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var picked := 0
	for l: Dictionary in facility.lights:
		var light: Light3D = l.light
		if light == null or l.emergency or (flicker_only and not l.flicker):
			continue
		if light.global_position.distance_to(cam.global_position) < 14.0:
			Effects.sparks(self, light.global_position + Vector3.UP * 0.2, Vector3.DOWN, 18)
			picked += 1
			if picked >= count:
				return


func _apply_budget() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var origin := cam.global_position
	var p := Settings.preset()
	var max_lights := int(p.max_room_lights)
	var max_dist := float(p.light_range)
	var candidates: Array = []
	for l: Dictionary in facility.lights:
		var light: Light3D = l.light
		if light == null:
			continue
		if not l.get("on", false):
			light.visible = false
			continue
		var d := light.global_position.distance_to(origin)
		if d > max_dist:
			light.visible = false
			continue
		candidates.append([d, l])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in candidates.size():
		var l: Dictionary = candidates[i][1]
		var light: Light3D = l.light
		light.visible = i < max_lights
		if light is OmniLight3D:
			(light as OmniLight3D).shadow_enabled = bool(p.shadows) and i < 1 and not l.emergency
