extends Node3D
## Visual QA scene: shows the survivor and THE HUNTER with production materials under
## facility-style lighting, cycles their animation states, saves screenshots and quits.
##   godot --path . res://tools/asset_preview.tscn -- --ns-shots=<dir>

var survivor: SkinnedCharacterVisual
var hunter: SkinnedCharacterVisual
var cam: Camera3D
var shots_dir := ""
var _t := 0.0
var _step := 0
const STEPS := [
	["survivor_idle", 1.2], ["survivor_walk", 1.2], ["survivor_run", 1.2], ["survivor_crouch", 1.2],
	["survivor_interact", 1.2], ["survivor_downed", 1.4], ["hunter_patrol", 1.2], ["hunter_chase", 1.2],
	["hunter_attack", 0.55], ["hunter_alert", 0.5], ["closeup", 1.0],
]


func _ready() -> void:
	shots_dir = CmdArgs.value("shots", "user://shots")
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.022, 0.026)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.45, 0.5)
	e.ambient_light_energy = 0.3
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	floor_mesh.mesh = pm
	floor_mesh.material_override = MaterialLibrary.get_mat("floor_tile")
	add_child(floor_mesh)
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(12, 4, 0.2)
	wall.mesh = bm
	wall.position = Vector3(0, 2, -3)
	wall.material_override = MaterialLibrary.get_mat("wall_panel")
	add_child(wall)
	var key := OmniLight3D.new()
	key.position = Vector3(1.5, 3.2, 2.5)
	key.light_energy = 2.5
	key.omni_range = 12
	key.shadow_enabled = true
	add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-2.5, 2.5, -2)
	rim.light_color = Color(1.0, 0.2, 0.1)
	rim.light_energy = 2.0
	rim.omni_range = 8
	add_child(rim)
	survivor = load("res://assets/characters/survivor/survivor_visual.tscn").instantiate()
	survivor.position = Vector3(-1.2, 0, 0)
	survivor.rotation.y = deg_to_rad(200)
	add_child(survivor)
	survivor.apply_cosmetics({"0": "suit_hazard", "2": "helmet_cyan"})
	hunter = load("res://assets/creatures/hunter/hunter_visual.tscn").instantiate()
	hunter.position = Vector3(1.4, 0, -0.5)
	hunter.rotation.y = deg_to_rad(150)
	add_child(hunter)
	cam = Camera3D.new()
	cam.position = Vector3(0, 1.5, 5.2)
	cam.fov = 50
	add_child(cam)
	cam.look_at(Vector3(0, 1.1, 0))
	cam.current = true
	_apply_step()


func _apply_step() -> void:
	var s: String = STEPS[_step][0]
	survivor.set_ai_state(&"IDLE")
	match s:
		"survivor_idle": survivor.set_motion(0.0, CharacterVisual.Pose.STAND, false)
		"survivor_walk": survivor.set_motion(1.0, CharacterVisual.Pose.STAND, false)
		"survivor_run": survivor.set_motion(1.8, CharacterVisual.Pose.STAND, true)
		"survivor_crouch": survivor.set_motion(0.5, CharacterVisual.Pose.CROUCH, false)
		"survivor_interact":
			survivor.set_motion(0.0, CharacterVisual.Pose.STAND, false)
			survivor.play_action(&"interact")
		"survivor_downed":
			survivor.play_action(&"none")
			survivor.set_motion(0.2, CharacterVisual.Pose.DOWNED, false)
		"hunter_patrol":
			hunter.set_ai_state(&"PATROL")
			hunter.set_motion(0.8, CharacterVisual.Pose.STAND, false)
		"hunter_chase":
			hunter.set_ai_state(&"CHASE")
			hunter.set_motion(2.4, CharacterVisual.Pose.STAND, true)
		"hunter_attack": hunter.play_action(&"attack")
		"hunter_alert": hunter.play_action(&"alert")
		"closeup":
			cam.position = Vector3(1.0, 2.0, 1.6)
			cam.look_at(hunter.global_position + Vector3(0, 1.9, 0.3))
			hunter.set_ai_state(&"IDLE")
			hunter.set_motion(0.0, CharacterVisual.Pose.STAND, false)


func _process(delta: float) -> void:
	_t += delta
	if _t < float(STEPS[_step][1]):
		return
	_t = 0.0
	var img := get_viewport().get_texture().get_image()
	img.save_png(shots_dir.path_join("%02d_%s.png" % [_step, STEPS[_step][0]]))
	_step += 1
	if _step >= STEPS.size():
		get_tree().quit()
		return
	_apply_step()
