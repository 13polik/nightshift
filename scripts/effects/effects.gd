class_name Effects
extends RefCounted
## Optimised visual effects. Every effect scales with the graphics preset:
##   Low    : one-shots at reduced counts, no ambient effects
##   Medium : full one-shots, ambient fog/steam/sparks
##   High   : as Medium with higher counts
## Materials/meshes are shared statics; one-shot emitters free themselves.

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}


static func _scale() -> float:
	match Settings.quality():
		0: return 0.4
		2: return 1.3
	return 1.0


static func ambient_enabled() -> bool:
	return bool(Settings.preset().particles)


static func _billboard_mat(tex_name: String, color: Color, additive: bool) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [tex_name, color.to_html(), additive]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var p := "res://assets/effects/textures/%s.png" % tex_name
	if ResourceLoader.exists(p):
		m.albedo_texture = load(p)
	_mats[key] = m
	return m


static func _quad(size: float) -> QuadMesh:
	var key := "q%s" % size
	if not _meshes.has(key):
		var q := QuadMesh.new()
		q.size = Vector2(size, size)
		_meshes[key] = q
	return _meshes[key]


static func _particles(parent: Node, pos: Vector3, amount: int, lifetime: float, one_shot: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.explosiveness = 0.9 if one_shot else 0.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	if one_shot:
		p.emitting = true
		p.finished.connect(p.queue_free)
	return p


static func _proc(dir: Vector3, spread: float, vmin: float, vmax: float, gravity: Vector3, smin: float, smax: float) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = dir
	m.spread = spread
	m.initial_velocity_min = vmin
	m.initial_velocity_max = vmax
	m.gravity = gravity
	m.scale_min = smin
	m.scale_max = smax
	return m


## Electrical sparks (falling, bouncing streaks).
static func sparks(parent: Node, pos: Vector3, normal := Vector3.UP, amount: int = 24) -> void:
	var p := _particles(parent, pos, int(amount * _scale()), 0.7, true)
	var m := _proc(normal, 55.0, 2.0, 5.0, Vector3(0, -9.8, 0), 0.3, 0.6)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	ramp.set_color(1, Color(1.0, 0.4, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	m.color_ramp = gt
	p.process_material = m
	p.draw_pass_1 = _quad(0.05)
	p.material_override = _billboard_mat("spark", Color(1.0, 0.75, 0.35), true)
	Audio.play_3d("stun", pos, -10.0, 14.0, 1.6)


## Soft smoke puff / column.
static func smoke(parent: Node, pos: Vector3, amount: int = 14, lifetime: float = 2.5, color := Color(0.15, 0.15, 0.15, 0.55), one_shot := true) -> GPUParticles3D:
	var p := _particles(parent, pos, int(amount * _scale()), lifetime, one_shot)
	var m := _proc(Vector3.UP, 25.0, 0.4, 1.2, Vector3(0, 0.25, 0), 0.6, 1.4)
	m.damping_min = 0.6
	m.damping_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.add_point(0.15, Color(1, 1, 1, 1.0))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	m.color_ramp = gt
	p.process_material = m
	p.draw_pass_1 = _quad(0.9)
	p.material_override = _billboard_mat("smoke", color, false)
	return p


## Concrete/metal debris chips (door bashing, impacts).
static func debris(parent: Node, pos: Vector3, normal := Vector3.UP, amount: int = 16) -> void:
	var p := _particles(parent, pos, int(amount * _scale()), 1.2, true)
	var m := _proc(normal, 70.0, 1.5, 4.0, Vector3(0, -9.8, 0), 0.5, 1.2)
	m.angular_velocity_min = -360.0
	m.angular_velocity_max = 360.0
	p.process_material = m
	p.draw_pass_1 = MeshKit.box_mesh(Vector3(0.05, 0.03, 0.04))
	p.material_override = MaterialLibrary.get_mat("metal_painted")
	smoke(parent, pos, 6, 1.4, Color(0.35, 0.33, 0.3, 0.45))


## Small explosion: flash light + sparks + smoke + debris + sound.
static func explosion(parent: Node, pos: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.3)
	light.light_energy = 6.0
	light.omni_range = 7.0
	parent.add_child(light)
	light.global_position = pos
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.45)
	tw.tween_callback(light.queue_free)
	sparks(parent, pos, Vector3.UP, 40)
	debris(parent, pos, Vector3.UP, 20)
	smoke(parent, pos, 18, 3.0)
	Audio.play_3d("door_bash", pos, 2.0, 35.0, 0.8)


## Persistent ambient effects -------------------------------------------------------

## Low-lying fog cards (no depth reads: cheap on mobile).
static func fog_cards(parent: Node3D, aabb: AABB, count: int) -> void:
	if not ambient_enabled():
		return
	var key := "fogmat"
	if not _mats.has(key):
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/fog_card.gdshader")
		sm.set_shader_parameter("noise_tex", MaterialLibrary.noise_texture())
		_mats[key] = sm
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(aabb.position))
	for i in count:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(rng.randf_range(5, 9), rng.randf_range(5, 9))
		mi.mesh = pm
		mi.material_override = _mats[key]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 30.0
		parent.add_child(mi)
		mi.global_position = Vector3(rng.randf_range(aabb.position.x + 2, aabb.end.x - 2), aabb.position.y + rng.randf_range(0.15, 0.5), rng.randf_range(aabb.position.z + 2, aabb.end.z - 2))
		mi.rotation.y = rng.randf() * TAU


## Steam leaking from a pipe.
static func steam(parent: Node3D, pos: Vector3, dir: Vector3) -> void:
	if not ambient_enabled():
		return
	var p := smoke(parent, pos, 10, 1.8, Color(0.75, 0.78, 0.8, 0.25), false)
	(p.process_material as ParticleProcessMaterial).direction = dir
	(p.process_material as ParticleProcessMaterial).initial_velocity_min = 1.2
	(p.process_material as ParticleProcessMaterial).initial_velocity_max = 2.2
	p.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))


## Dust motes drifting inside the local player's flashlight beam.
static func beam_dust(light_parent: Node3D) -> GPUParticles3D:
	if not ambient_enabled():
		return null
	var p := GPUParticles3D.new()
	p.amount = int(60 * _scale())
	p.lifetime = 4.0
	p.local_coords = true
	p.preprocess = 2.0
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(1.2, 1.2, 4.0)
	m.direction = Vector3(0.2, 0.1, 0)
	m.spread = 180.0
	m.initial_velocity_min = 0.01
	m.initial_velocity_max = 0.06
	m.gravity = Vector3(0, -0.005, 0)
	m.scale_min = 0.5
	m.scale_max = 1.2
	p.process_material = m
	p.draw_pass_1 = _quad(0.02)
	p.material_override = _billboard_mat("dust", Color(1.0, 0.95, 0.85, 0.5), true)
	p.position = Vector3(0, 0, -4.5)
	p.visibility_aabb = AABB(Vector3(-2, -2, -6), Vector3(4, 4, 12))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	light_parent.add_child(p)
	return p
