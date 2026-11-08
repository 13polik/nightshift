extends Node3D
## Visual QA: survivors holding items (screenshot then quit).
##   godot --path . res://tools/held_preview.tscn -- --ns-shots=<dir>

const ITEMS := [&"medkit", &"crowbar", &"sample_case", &"arc_emitter"]


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.055, 0.06)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.6)
	e.ambient_light_energy = 0.5
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 30, 0)
	key.light_energy = 1.4
	add_child(key)
	for i in ITEMS.size():
		var v: SkinnedCharacterVisual = load("res://assets/characters/survivor/survivor_visual.tscn").instantiate()
		v.position = Vector3(-2.4 + i * 1.6, 0, 0)
		v.rotation.y = deg_to_rad(200)
		add_child(v)
		v.set_held_item(ITEMS[i])
		v.set_motion(1.0 if i == 1 else 0.0, CharacterVisual.Pose.STAND, false)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.3, 4.6)
	cam.fov = 50
	add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))
	cam.current = true
	await get_tree().create_timer(1.6).timeout
	var dir := CmdArgs.value("shots", "user://")
	get_viewport().get_texture().get_image().save_png(dir.path_join("held.png"))
	get_tree().quit()
