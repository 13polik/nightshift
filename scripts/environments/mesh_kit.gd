class_name MeshKit
extends RefCounted
## Helpers to assemble development art from shared primitive meshes. Meshes are cached by
## dimensions so identical props share one Mesh resource (GPU instancing friendly).

static var _mesh_cache: Dictionary = {}


static func box_mesh(size: Vector3) -> BoxMesh:
	var key := "box:%s" % size
	if not _mesh_cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func cyl_mesh(radius: float, height: float, top_radius: float = -1.0, segments: int = 16) -> CylinderMesh:
	var key := "cyl:%s:%s:%s:%d" % [radius, height, top_radius, segments]
	if not _mesh_cache.has(key):
		var m := CylinderMesh.new()
		m.bottom_radius = radius
		m.top_radius = radius if top_radius < 0.0 else top_radius
		m.height = height
		m.radial_segments = segments
		m.rings = 1
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func sphere_mesh(radius: float, segments: int = 16) -> SphereMesh:
	var key := "sph:%s:%d" % [radius, segments]
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = segments
		m.rings = maxi(4, segments / 2)
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func capsule_mesh(radius: float, height: float) -> CapsuleMesh:
	var key := "cap:%s:%s" % [radius, height]
	if not _mesh_cache.has(key):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = height
		m.radial_segments = 12
		m.rings = 4
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func add_mesh(parent: Node3D, mesh: Mesh, mat_name: String, pos: Vector3, rot_deg := Vector3.ZERO, draw_distance: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = MaterialLibrary.get_mat(mat_name)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	if draw_distance > 0.0:
		mi.visibility_range_end = draw_distance
		mi.visibility_range_end_margin = 2.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	parent.add_child(mi)
	return mi


static func add_box(parent: Node3D, size: Vector3, mat_name: String, pos: Vector3, rot_deg := Vector3.ZERO, draw_distance: float = 0.0) -> MeshInstance3D:
	return add_mesh(parent, box_mesh(size), mat_name, pos, rot_deg, draw_distance)


static func add_cyl(parent: Node3D, radius: float, height: float, mat_name: String, pos: Vector3, rot_deg := Vector3.ZERO, draw_distance: float = 0.0) -> MeshInstance3D:
	return add_mesh(parent, cyl_mesh(radius, height), mat_name, pos, rot_deg, draw_distance)


## Adds a static collision box to `body` (local to the body).
static func add_collider(body: CollisionObject3D, size: Vector3, pos: Vector3, rot_deg := Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	cs.rotation_degrees = rot_deg
	body.add_child(cs)
	return cs


## Appends an axis-aligned box (6 quads) to a SurfaceTool (used for merged room geometry).
static func st_box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var c := center
	var faces := [
		[Vector3(1, 0, 0), [Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z)]],
		[Vector3(-1, 0, 0), [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z)]],
		[Vector3(0, 1, 0), [Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z)]],
		[Vector3(0, -1, 0), [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z)]],
		[Vector3(0, 0, 1), [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]],
		[Vector3(0, 0, -1), [Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z)]],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var v: Array = f[1]
		st_quad(st, c + v[0], c + v[1], c + v[2], c + v[3], n)


## Quad with counter-clockwise winding (as seen from the normal side).
static func st_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	for p in [a, c, b, a, d, c]:
		st.set_normal(n)
		st.set_uv(planar_uv(p, n))
		st.add_vertex(p)


## World-scale planar UV (1 unit = 1 m) chosen by the face's dominant axis, so tiling
## textures keep a constant texel density across merged architecture.
static func planar_uv(p: Vector3, n: Vector3) -> Vector2:
	var a := n.abs()
	if a.y >= a.x and a.y >= a.z:
		return Vector2(p.x, p.z)
	if a.x >= a.z:
		return Vector2(p.z * signf(n.x), -p.y)
	return Vector2(-p.x * signf(n.z), -p.y)
