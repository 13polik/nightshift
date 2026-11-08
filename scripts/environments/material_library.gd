class_name MaterialLibrary
extends RefCounted
## Shared PBR materials built from the project's texture sets in res://assets/textures
## (see tools/textures/gen_textures.py). Materials are created once and shared, so every
## mesh using the same material batches together. A hand-authored material at
## res://assets/materials/<name>.tres overrides the generated one.
##
## Imported models (glTF from tools/blender) name their surfaces after these materials;
## apply_named() swaps in the shared material so models carry geometry only.

const TEX := "res://assets/textures/%s/%s_%s.png"

static var _cache: Dictionary = {}
static var _noise: Texture2D


static func get_mat(mat_name: String) -> Material:
	if _cache.has(mat_name):
		return _cache[mat_name]
	var path := "res://assets/materials/%s.tres" % mat_name
	var m: Material = load(path) if ResourceLoader.exists(path) else _create(mat_name)
	_cache[mat_name] = m
	return m


static func has_mat(mat_name: String) -> bool:
	return _cache.has(mat_name) or _create_known(mat_name)


static func noise_texture() -> Texture2D:
	if _noise:
		return _noise
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.03
	n.fractal_octaves = 3
	var t := NoiseTexture2D.new()
	t.width = 128
	t.height = 128
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = n
	_noise = t
	return t


static func _tex(set_name: String, kind: String) -> Texture2D:
	var p := TEX % [set_name, set_name, kind]
	return load(p) if ResourceLoader.exists(p) else null


## Architecture surface (shader with macro variation + grime + stripe).
static func _surface(set_name: String, uv_scale: float, stripe := Color(0, 0, 0, 0), tint := Color.WHITE, rough_mul := 1.0, grime := 0.45) -> Material:
	var alb := _tex(set_name, "albedo")
	if alb == null:
		return _fallback(tint)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/facility_surface.gdshader")
	m.set_shader_parameter("albedo_tex", alb)
	m.set_shader_parameter("normal_tex", _tex(set_name, "normal"))
	m.set_shader_parameter("orm_tex", _tex(set_name, "orm"))
	m.set_shader_parameter("macro_noise", noise_texture())
	m.set_shader_parameter("uv_scale", uv_scale)
	m.set_shader_parameter("stripe_color", stripe)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("roughness_mul", rough_mul)
	m.set_shader_parameter("floor_grime", grime)
	return m


## Standard PBR material for props/characters (UV-mapped models, 1 UV unit = 1 m).
static func _pbr(set_name: String, uv_scale := 1.0, tint := Color.WHITE, emission := Color(0, 0, 0), energy := 0.0) -> Material:
	var alb := _tex(set_name, "albedo")
	if alb == null:
		return _fallback(tint)
	var m := ORMMaterial3D.new()
	m.albedo_texture = alb
	m.normal_enabled = Settings.quality() > 0
	m.albedo_color = tint
	m.normal_texture = _tex(set_name, "normal")
	m.orm_texture = _tex(set_name, "orm")
	m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m


static func _std(albedo: Color, rough: float = 0.6, metal: float = 0.0, emission := Color(0, 0, 0), energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m


static func _fallback(tint: Color) -> Material:
	push_warning("MaterialLibrary: texture set missing - using flat fallback")
	return _std(tint * Color(0.5, 0.5, 0.5), 0.7)


static func _create_known(mat_name: String) -> bool:
	return mat_name in ["floor_concrete", "floor_tile", "floor_lab", "floor_grate", "floor_asphalt", "wall_panel", "wall_lab",
		"wall_concrete", "wall_medical", "wall_industrial", "wall_freezer", "floor_freezer", "ceiling", "metal_dark", "steel_dark", "metal_painted", "metal_bright",
		"steel_bright", "metal_yellow", "rust_metal", "plastic_white", "plastic_dark", "wood", "fabric", "fabric_suit",
		"fabric_dark", "rubber", "glass", "cardboard", "screen_on", "screen_off", "screen_red", "emissive_white", "emissive_off",
		"emissive_red", "emissive_amber", "emissive_cyan", "emissive_green", "hazard", "biohazard_liquid", "blood",
		"hunter_skin", "hunter_eyes", "hunter_glow", "concrete", "skin", "visor", "lens", "scorch"]


static func _create(mat_name: String) -> Material:
	var amber := Color(0.85, 0.62, 0.1, 1.0)
	match mat_name:
		# --- architecture ---
		"floor_concrete", "concrete": return _surface("concrete", 0.25, Color(0, 0, 0, 0), Color.WHITE, 1.0, 0.0)
		"floor_tile": return _surface("floor_tile", 0.5, Color(0, 0, 0, 0), Color.WHITE, 1.0, 0.0)
		"floor_lab": return _surface("floor_lab", 0.5, Color(0, 0, 0, 0), Color.WHITE, 1.0, 0.0)
		"floor_grate": return _surface("metal_grate", 1.0, Color(0, 0, 0, 0), Color.WHITE, 1.0, 0.0)
		"floor_asphalt": return _surface("asphalt", 0.2, Color(0, 0, 0, 0), Color.WHITE, 1.0, 0.0)
		"wall_panel": return _surface("wall_panel", 0.5, amber)
		"wall_lab": return _surface("wall_lab", 0.34, Color(0.18, 0.5, 0.55, 1.0), Color.WHITE, 1.0, 0.3)
		"wall_concrete": return _surface("concrete", 0.25, Color(0, 0, 0, 0), Color(0.9, 0.9, 0.9), 1.0, 0.6)
		"wall_medical": return _surface("wall_medical", 0.25, Color(0.55, 0.13, 0.12, 1.0), Color.WHITE, 1.0, 0.3)
		"wall_industrial": return _surface("wall_industrial", 0.5, amber, Color.WHITE, 1.0, 0.6)
		# cold storage: insulated white panels with a blue safety stripe, frosted floor
		"wall_freezer": return _surface("wall_panel", 0.5, Color(0.2, 0.5, 0.75, 1.0), Color(1.15, 1.25, 1.4), 0.6, 0.1)
		"floor_freezer": return _surface("concrete", 0.25, Color(0, 0, 0, 0), Color(1.0, 1.1, 1.25), 0.45, 0.0)
		"ceiling": return _surface("ceiling", 0.42, Color(0, 0, 0, 0), Color(0.8, 0.8, 0.8), 1.0, 0.0)
		# --- props ---
		"metal_dark", "steel_dark": return _pbr("steel_dark", 1.0)
		"metal_bright", "steel_bright": return _pbr("steel_bright", 1.0)
		"metal_painted": return _pbr("metal_painted", 0.6)
		"metal_yellow": return _pbr("metal_yellow", 0.6)
		"rust_metal": return _pbr("rust_metal", 0.7)
		"plastic_white": return _pbr("plastic_white", 1.0)
		"plastic_dark": return _pbr("plastic_dark", 1.0)
		"wood": return _pbr("wood", 1.0)
		"fabric", "fabric_dark": return _pbr("fabric_dark", 2.0)
		"fabric_suit": return _pbr("fabric_suit", 2.0)
		"rubber": return _pbr("rubber", 2.0)
		"cardboard": return _pbr("cardboard", 1.0)
		"hazard": return _pbr("hazard", 1.0)
		"glass":
			var g := _std(Color(0.55, 0.7, 0.75, 0.18), 0.04, 0.2)
			g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			g.cull_mode = BaseMaterial3D.CULL_DISABLED
			return g
		"visor", "lens":
			var v := _std(Color(0.03, 0.05, 0.06), 0.05, 0.85, Color(0.2, 0.9, 1.0), 0.18)
			return v
		"skin": return _std(Color(0.55, 0.42, 0.36), 0.55)
		"screen_on": return _std(Color(0.02, 0.05, 0.05), 0.15, 0.0, Color(0.2, 0.8, 0.75), 1.6)
		"screen_off": return _std(Color(0.02, 0.025, 0.03), 0.12, 0.2)
		"screen_red": return _std(Color(0.05, 0.01, 0.01), 0.15, 0.0, Color(0.9, 0.12, 0.08), 1.8)
		"emissive_white": return _std(Color(0.9, 0.9, 0.85), 0.5, 0.0, Color(1.0, 0.96, 0.88), 3.0)
		"emissive_off": return _std(Color(0.25, 0.25, 0.24), 0.4, 0.1)
		"emissive_red": return _std(Color(0.4, 0.02, 0.02), 0.5, 0.0, Color(1.0, 0.1, 0.05), 3.0)
		"emissive_amber": return _std(Color(0.4, 0.25, 0.02), 0.5, 0.0, Color(1.0, 0.62, 0.15), 3.0)
		"emissive_cyan": return _std(Color(0.02, 0.3, 0.32), 0.5, 0.0, Color(0.2, 0.9, 1.0), 2.5)
		"emissive_green": return _std(Color(0.02, 0.3, 0.05), 0.5, 0.0, Color(0.2, 1.0, 0.35), 2.5)
		"biohazard_liquid":
			var b := _std(Color(0.1, 0.35, 0.2, 0.75), 0.05, 0.0, Color(0.15, 0.9, 0.4), 0.8)
			b.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			return b
		"blood":
			var bl := StandardMaterial3D.new()
			bl.albedo_texture = load("res://assets/textures/decals/blood_albedo.png")
			bl.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			bl.roughness = 0.2
			bl.albedo_color = Color(0.9, 0.9, 0.9)
			return bl
		"scorch":
			var sc := StandardMaterial3D.new()
			sc.albedo_texture = load("res://assets/textures/decals/scorch_albedo.png")
			sc.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sc.roughness = 0.95
			return sc
		"hunter_skin":
			var h := _pbr("hunter_skin", 1.5) as ORMMaterial3D
			if h and ResourceLoader.exists("res://assets/textures/hunter_skin/hunter_skin_emission.png"):
				h.emission_enabled = true
				h.emission = Color.WHITE
				h.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
				h.emission_texture = load("res://assets/textures/hunter_skin/hunter_skin_emission.png")
				h.emission_energy_multiplier = 1.4
				h.rim_enabled = true
				h.rim = 0.35
				h.rim_tint = 0.6
			return h
		"hunter_eyes", "hunter_glow": return _std(Color(0.8, 0.9, 1.0), 0.2, 0.0, Color(0.75, 0.95, 1.0), 6.0)
	push_warning("MaterialLibrary: unknown material %s" % mat_name)
	return _std(Color(1, 0, 1))


## Per-instance tinted copy for cosmetics (cached by colour).
static func tinted(base_name: String, color: Color) -> Material:
	var key := "%s#%s" % [base_name, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var m: Material = get_mat(base_name).duplicate()
	if m is BaseMaterial3D:
		(m as BaseMaterial3D).albedo_color = color
	elif m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter("tint", color)
	_cache[key] = m
	return m


## Replaces imported surface materials by name with the shared library materials.
## Names may carry a Blender ".001" suffix, which is ignored.
static func apply_named(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(i)
			if src == null:
				continue
			var n := String(src.resource_name).get_slice(".", 0)
			if _create_known(n):
				m.set_surface_override_material(i, get_mat(n))


## Scales material cost with the graphics preset (normal maps off on Low).
static func apply_quality(q: int) -> void:
	RenderingServer.global_shader_parameter_set(&"ns_quality", float(q))
	for m in _cache.values():
		if m is BaseMaterial3D and (m as BaseMaterial3D).normal_texture != null:
			(m as BaseMaterial3D).normal_enabled = q > 0
