class_name EnvironmentController
extends Node
## World environment tuned per quality preset: tonemapping, low ambient light (darkness is
## a gameplay element), depth fog, glow on emissives, optional volumetric fog where the
## renderer supports it (Forward+ only), dust particles near the camera.

var mission: Node
var world_env: WorldEnvironment
var env: Environment
var _dust: GPUParticles3D
var _moon: DirectionalLight3D


func setup(p_mission: Node) -> void:
	mission = p_mission
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.005, 0.006, 0.008)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.42)
	env.ambient_light_energy = 0.16
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.06, 0.07)
	env.fog_light_energy = 1.0
	env.fog_density = 0.035
	env.fog_sky_affect = 0.0
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.85
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	# faint moonlight for the outdoor yards
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.45, 0.55, 0.75)
	_moon.light_energy = 0.3
	_moon.rotation_degrees = Vector3(-55, 30, 0)
	_moon.shadow_enabled = false
	_moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(_moon)
	Events.graphics_quality_changed.connect(_apply)
	Events.settings_changed.connect(func(section: String) -> void:
		if section == "graphics":
			_apply_brightness())
	_apply(Settings.quality())
	_ambient_effects()


## Player brightness (Settings > Graphics): raises exposure and, more strongly, the ambient
## floor so dark corners stay readable on phone screens while lit areas don't blow out.
func _apply_brightness() -> void:
	var b := clampf(float(Settings.get_value("graphics", "brightness")), 0.7, 1.8)
	env.tonemap_exposure = 1.15 * b
	env.ambient_light_energy = 0.22 * b * b
	if _moon:
		_moon.light_energy = 0.35 * b
	# gamma curve on the final image: lifts the near-black shadows (what actually hides the
	# map on a phone screen) without blowing out lamps. 1.0 = neutral.
	var gamma := 1.0 + (b - 1.0) * 1.3
	if absf(gamma - 1.0) < 0.01:
		env.adjustment_color_correction = null
	else:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array()
		g.colors = PackedColorArray()
		for i in 17:
			var x := float(i) / 16.0
			var y := pow(x, 1.0 / gamma)
			g.add_point(x, Color(y, y, y))
		var tex := GradientTexture1D.new()
		tex.gradient = g
		tex.width = 256
		env.adjustment_color_correction = tex


func _apply(_q: int) -> void:
	_apply_brightness()
	var p := Settings.preset()
	env.glow_enabled = bool(p.glow)
	env.fog_enabled = bool(p.fog)
	var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	env.volumetric_fog_enabled = bool(p.volumetric) and forward_plus
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = 0.025
		env.volumetric_fog_albedo = Color(0.6, 0.65, 0.7)
		env.volumetric_fog_length = 32.0
	env.ssao_enabled = forward_plus and bool(p.shadows)
	_moon.shadow_enabled = false # a facility-wide directional shadow map is too costly for mobile
	if bool(p.particles) and _dust == null:
		_dust = _make_dust()
	elif not bool(p.particles) and _dust:
		_dust.queue_free()
		_dust = null


## Localised atmosphere: ground fog in damp/underground spaces, leaking steam near pipes.
func _ambient_effects() -> void:
	if not Effects.ambient_enabled():
		return
	var fac: FacilityRuntime = mission.facility
	for id: StringName in fac.room_info:
		var info: Dictionary = fac.room_info[id]
		var aabb: AABB = info.aabb
		match str(info.kind):
			"tunnel", "pump", "containment", "hall":
				Effects.fog_cards(info.node, aabb, clampi(int(aabb.size.x * aabb.size.z / 60.0), 2, 6))
			"maintenance", "generator", "stairs":
				Effects.fog_cards(info.node, aabb, 2)
			"freezer":
				# cold storage: dense frost mist hugging the floor + cold vapour from the vents
				Effects.fog_cards(info.node, aabb, clampi(int(aabb.size.x * aabb.size.z / 45.0), 3, 8))
				var cf := aabb.get_center()
				Effects.steam(info.node, Vector3(cf.x - aabb.size.x * 0.3, aabb.position.y + 3.6, cf.z), Vector3(0.2, -1, -0.1))
		if str(info.kind) in ["pump", "generator", "tunnel"]:
			var c := aabb.get_center()
			Effects.steam(info.node, Vector3(c.x + aabb.size.x * 0.3, aabb.position.y + 3.3, c.z), Vector3(-0.3, -1, 0.2))


func _make_dust() -> GPUParticles3D:
	var d := GPUParticles3D.new()
	d.amount = 90
	d.lifetime = 8.0
	d.preprocess = 4.0
	d.local_coords = false
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(7, 2.5, 7)
	m.direction = Vector3(0.2, 0.1, 0.1)
	m.spread = 180.0
	m.initial_velocity_min = 0.02
	m.initial_velocity_max = 0.12
	m.gravity = Vector3(0, -0.01, 0)
	m.scale_min = 0.6
	m.scale_max = 1.2
	d.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.025)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.8, 0.8, 0.75, 0.35)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	d.draw_pass_1 = quad
	d.visibility_aabb = AABB(Vector3(-9, -4, -9), Vector3(18, 8, 18))
	add_child(d)
	return d


func _process(_delta: float) -> void:
	if _dust:
		var cam := get_viewport().get_camera_3d()
		if cam:
			_dust.global_position = cam.global_position
