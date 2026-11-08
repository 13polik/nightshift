class_name MenuBackdrop
extends SubViewportContainer
## Live 3D backdrop for the main menu: a stretch of facility corridor under failing
## emergency light, an operative sweeping a torch, and THE HUNTER barely visible deep in
## the dark - it slips in and out of the light. Uses the real game assets/materials and
## scales its render resolution with the graphics preset.

var _vp: SubViewport
var _cam: Camera3D
var _survivor: SkinnedCharacterVisual
var _hunter: SkinnedCharacterVisual
var _torch: SpotLight3D
var _emergency: OmniLight3D
var _fixture_light: OmniLight3D
var _t := 0.0
var _hunter_phase := 0.0


func _ready() -> void:
	stretch = true
	stretch_shrink = 2 if Settings.quality() == Settings.Quality.LOW else 1
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.scaling_3d_scale = 0.8 if Settings.quality() < 2 else 1.0
	add_child(_vp)
	_build()


func _build() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.005, 0.007)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.35, 0.42)
	env.ambient_light_energy = 0.08
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.045, 0.055)
	env.fog_density = 0.032
	env.glow_enabled = Settings.quality() > 0
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	# corridor: 4 m wide, 3.6 m high, 30 m deep
	_slab(Vector3(4, 0.2, 30), Vector3(0, -0.1, -12), "floor_tile")
	_slab(Vector3(4, 0.2, 30), Vector3(0, 3.7, -12), "ceiling")
	_slab(Vector3(0.2, 3.6, 30), Vector3(-2.1, 1.8, -12), "wall_panel")
	_slab(Vector3(0.2, 3.6, 30), Vector3(2.1, 1.8, -12), "wall_panel")
	_slab(Vector3(4, 3.6, 0.2), Vector3(0, 1.8, -27), "wall_industrial")
	for z in [-2.0, -10.0, -18.0]:
		_model("pipe_run", "environment", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-1.4, 3.05, z)))
		_model("pipe_run", "environment", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-1.4, 3.05, z - 2.0)))
		_model("light_fixture", "environment", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 3.6, z)))
	_model("locker", "props", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-1.7, 0, -4.0)))
	_model("locker", "props", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-1.7, 0, -4.65)))
	_model("crate_stack", "props", Transform3D(Basis(Vector3.UP, -0.3), Vector3(1.4, 0, -7.5)))
	_model("barrel", "props", Transform3D(Basis(), Vector3(1.55, 0, -9.0)))
	_model("debris", "props", Transform3D(Basis(Vector3.UP, 1.0), Vector3(0.4, 0, -6.0)))
	_model("door_frame", "environment", Transform3D(Basis(), Vector3(0, 0, -26.9)))
	# lighting: dying fixture, rotating emergency red, operative's torch
	_fixture_light = _omni(Vector3(0, 3.2, -10.0), Color(0.85, 0.92, 1.0), 1.4, 9.0)
	_emergency = _omni(Vector3(1.8, 3.0, -16.0), Color(1.0, 0.12, 0.06), 1.6, 12.0)
	_omni(Vector3(1.9, 2.5, 0.4), Color(0.55, 0.7, 0.9), 0.9, 4.5) # cold rim on the operative
	_survivor = load("res://assets/characters/survivor/survivor_visual.tscn").instantiate()
	_survivor.position = Vector3(0.75, 0, -1.4)
	_survivor.rotation.y = 0.15
	_vp.add_child(_survivor)
	_survivor.apply_cosmetics(Profile.cosmetic_payload())
	_torch = SpotLight3D.new()
	_torch.spot_range = 22.0
	_torch.spot_angle = 22.0
	_torch.light_energy = 4.0
	_torch.light_color = Color(1.0, 0.95, 0.85)
	_torch.shadow_enabled = Settings.quality() > 0
	if ResourceLoader.exists("res://assets/effects/textures/flashlight_cookie.png"):
		_torch.light_projector = load("res://assets/effects/textures/flashlight_cookie.png")
	_vp.add_child(_torch)
	_hunter = load("res://assets/creatures/hunter/hunter_visual.tscn").instantiate()
	_hunter.position = Vector3(-0.4, 0, -19.0)
	_vp.add_child(_hunter)
	_hunter.set_ai_state(&"SEARCH")
	_hunter.set_motion(0.0, CharacterVisual.Pose.STAND, false)
	if Effects.ambient_enabled():
		var fog_root := Node3D.new()
		_vp.add_child(fog_root)
		Effects.fog_cards(fog_root, AABB(Vector3(-2, 0, -26), Vector3(4, 3, 26)), 4)
	_cam = Camera3D.new()
	_cam.fov = 55
	_cam.current = true
	_vp.add_child(_cam)


func _slab(size: Vector3, pos: Vector3, mat: String) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = MaterialLibrary.get_mat(mat)
	mi.position = pos
	_vp.add_child(mi)


func _model(kind: String, folder: String, xf: Transform3D) -> void:
	var ps := PropFactory.model_for(kind, folder)
	if ps == null:
		return
	var inst: Node3D = ps.instantiate()
	inst.transform = xf
	_vp.add_child(inst)
	MaterialLibrary.apply_named(inst)


func _omni(pos: Vector3, col: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	_vp.add_child(l)
	return l


func _process(delta: float) -> void:
	if _cam == null:
		return
	_t += delta
	# slow handheld drift behind the operative's shoulder
	_cam.position = Vector3(-1.35 + sin(_t * 0.21) * 0.12, 1.7 + sin(_t * 0.37) * 0.05, 1.8 + sin(_t * 0.13) * 0.2)
	_cam.look_at(Vector3(1.1, 1.35, -12.0))
	# the torch sweeps the corridor; the operative's body follows
	var sweep := sin(_t * 0.35) * 0.35
	_survivor.rotation.y = 0.1 + sweep * 0.6
	_torch.position = _survivor.position + Vector3(0.1, 1.45, -0.2)
	_torch.look_at(_torch.position + Vector3(-sin(sweep) * 1.0 - 0.1, -0.08, -1.0))
	# failing fixture + rotating emergency beacon
	var n := sin(_t * 23.0) * sin(_t * 7.3)
	_fixture_light.light_energy = 0.1 if n > 0.6 else 1.3
	_emergency.light_energy = 0.6 + 1.2 * absf(sin(_t * 2.2))
	# the Hunter drifts across the far end, freezing when the torch finds it
	_hunter_phase += delta * 0.08
	var lit := absf(sweep + 0.05) < 0.1
	var hx := sin(_hunter_phase * TAU) * 1.4
	if not lit:
		_hunter.position.x = move_toward(_hunter.position.x, hx, delta * 0.6)
	_hunter.rotation.y = PI + (0.6 if hx > _hunter.position.x else -0.6) * (0.0 if lit else 1.0)
	_hunter.set_ai_state(&"SEARCH" if lit else &"PATROL")
	_hunter.set_motion(0.0 if lit else 0.35, CharacterVisual.Pose.STAND, false)
