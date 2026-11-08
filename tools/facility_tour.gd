extends Node
## Visual QA: runs a real solo mission, then walks a free camera through key rooms (power
## on and off) and the Hunter, saving screenshots. Also logs FPS per shot.
##   godot --path . res://tools/facility_tour.tscn -- --ns-shots=<dir> [--ns-quality=low]

const SHOTS := [
	# [label, room, power_on, cam offset from room centre, look offset]
	["corridor_dark", "corridor_main", false, Vector3(-8, 1.7, 0), Vector3(6, 1.2, 0)],
	["corridor_lit", "corridor_main", true, Vector3(-8, 1.7, 0), Vector3(6, 1.2, 0)],
	["lab_a", "lab_a", true, Vector3(-3.5, 2.2, 6), Vector3(2, 0.8, -2)],
	["medical", "medical", true, Vector3(-4, 2.0, 6), Vector3(3, 0.8, -3)],
	["server_room", "server_room", true, Vector3(-4, 2.0, 5), Vector3(3, 1.0, -3)],
	["generator", "generator_room", true, Vector3(-6, 2.4, 5), Vector3(4, 0.8, -2)],
	["maintenance", "maintenance", true, Vector3(-4, 2.0, 5), Vector3(4, 1.0, -3)],
	["storage", "storage", false, Vector3(-4, 2.0, 5), Vector3(4, 1.0, -3)],
	["containment", "containment", true, Vector3(-4, 2.2, 6), Vector3(3, 1.0, -3)],
	["offices", "offices", true, Vector3(-4, 2.0, 6), Vector3(4, 0.8, -3)],
	["hunter", "", true, Vector3(0, 0, 0), Vector3(0, 0, 0)],
]

## --ns-mission=signal_lost: Greywater harbour depot
const HARBOR_SHOTS := [
	["h_gate_yard", "gate_yard", false, Vector3(6, 1.7, 3), Vector3(-6, 1.0, -4)],
	["h_quay", "quay", false, Vector3(12, 1.7, 1), Vector3(-10, 1.0, 0)],
	["h_loading_bay", "loading_bay", true, Vector3(-12, 2.2, 6), Vector3(8, 0.8, -4)],
	["h_freezer_dark", "freezer_a", false, Vector3(-9, 1.8, 7), Vector3(6, 1.0, -5)],
	["h_freezer_lit", "freezer_b", true, Vector3(-8, 2.0, 7), Vector3(6, 1.0, -5)],
	["h_radio", "radio_room", true, Vector3(-2, 2.0, 7), Vector3(1, 1.0, -8)],
	["h_mast_yard", "mast_yard", true, Vector3(-5, 1.8, 5), Vector3(6, 1.2, -2)],
	["h_pier", "pier", false, Vector3(6, 1.8, 3), Vector3(-6, 0.8, 0)],
]

var mission: MissionController
var cam: Camera3D
var dir := ""
var shots: Array = SHOTS
var _i := 0
var _t := 0.0
var _fps_acc := 0.0
var _fps_n := 0


func _ready() -> void:
	dir = CmdArgs.value("shots", "user://tour")
	DirAccess.make_dir_recursive_absolute(dir)
	Net.start_solo()
	var mid := CmdArgs.value("mission", "power_restoration")
	if mid == "signal_lost":
		shots = HARBOR_SHOTS
	Net.pending_mission = {"mission_id": StringName(mid), "seed": 777, "roster": Net.players}
	mission = load(Router.MISSION).instantiate()
	mission.auto_route_results = false
	add_child(mission)


func _process(delta: float) -> void:
	if mission == null or not mission.running:
		return
	if cam == null:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		cam = Camera3D.new()
		cam.far = 80
		cam.fov = 70
		add_child(cam)
		mission.hud.visible = false
		for e: EnemyBase in mission.enemies.all():
			e.active = false
		_setup_shot()
		return
	_t += delta
	if _t > 0.6:
		_fps_acc += Engine.get_frames_per_second()
		_fps_n += 1
	if _t < 1.6:
		return
	var label: String = shots[_i][0]
	get_viewport().get_texture().get_image().save_png(dir.path_join("%02d_%s.png" % [_i, label]))
	var vp := get_viewport().get_viewport_rid()
	print("TIMES process=%.1fms physics=%.1fms nav=%.1fms" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0])
	print("TOUR %s fps=%d draws=%d objects=%d prims=%dk cpu_ms=%.1f gpu_ms=%.1f" % [label, int(_fps_acc / maxi(_fps_n, 1)),
		RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME) / 1000,
		RenderingServer.viewport_get_measured_render_time_cpu(vp), RenderingServer.viewport_get_measured_render_time_gpu(vp)])
	_i += 1
	_t = 0.0
	_fps_acc = 0.0
	_fps_n = 0
	if _i >= shots.size():
		get_tree().quit()
		return
	_setup_shot()


func _setup_shot() -> void:
	var s: Array = shots[_i]
	var power: bool = s[2]
	for z in ["power_main", "power_underground", "power_generator"]:
		mission.state.set_flag(StringName(z), power)
	cam.current = true
	if String(s[1]).is_empty():
		var e: EnemyBase = mission.enemies.all()[0]
		var p := e.global_position
		cam.global_position = p + (-e.global_basis.z) * 3.2 + Vector3(0.8, 1.9, 0)
		cam.look_at(p + Vector3(0, 1.7, 0))
		var light := OmniLight3D.new()
		light.light_energy = 2.0
		light.omni_range = 6.0
		add_child(light)
		light.global_position = cam.global_position + Vector3(0.5, 0.6, 0)
		return
	var aabb: AABB = mission.facility.room_info[StringName(s[1])].aabb
	var c := aabb.get_center()
	c.y = aabb.position.y
	cam.global_position = c + s[3]
	cam.look_at(c + s[4])
