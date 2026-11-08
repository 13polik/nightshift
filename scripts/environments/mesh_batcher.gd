class_name MeshBatcher
extends RefCounted
## Collects instances of authored models (props, pipes, fixtures) and emits one
## MultiMeshInstance3D per (model mesh) per batch. A room with 12 lockers costs one draw
## per locker surface instead of 12 - essential for mobile draw-call budgets.
## Meshes are copied once with the shared MaterialLibrary materials baked in.

static var _mesh_cache: Dictionary = {}   # "folder/kind" -> Array[{mesh, xform, name}]

var _items: Dictionary = {}               # "folder/kind" -> Array[Transform3D]


## Mesh parts of a model (name, mesh with library materials, transform relative to root).
static func parts(kind: String, folder: String) -> Array:
	var key := folder + "/" + kind
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var out: Array = []
	var ps := PropFactory.model_for(kind, folder)
	if ps:
		var inst: Node3D = ps.instantiate()
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var mesh: Mesh = m.mesh.duplicate()
			for i in mesh.get_surface_count():
				var src := mesh.surface_get_material(i)
				var n := String(src.resource_name).get_slice(".", 0) if src else ""
				if MaterialLibrary.has_mat(n):
					mesh.surface_set_material(i, MaterialLibrary.get_mat(n))
			out.append({"mesh": mesh, "xform": _relative(inst, m), "name": String(m.name)})
		inst.free()
	_mesh_cache[key] = out
	return out


static func _relative(root: Node3D, n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p and p != root:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func has_model(kind: String, folder: String) -> bool:
	return not parts(kind, folder).is_empty()


func add(kind: String, folder: String, xform: Transform3D) -> void:
	var key := folder + "/" + kind
	if not _items.has(key):
		_items[key] = []
	(_items[key] as Array).append(xform)


func count() -> int:
	var n := 0
	for k in _items:
		n += (_items[k] as Array).size()
	return n


## Creates the MultiMeshInstance3D nodes under `parent`. Returns {"<kind>/<part>": MMI}.
func flush(parent: Node3D, draw_distance: float, shadows: bool = true, name_prefix: String = "Batch") -> Dictionary:
	var made := {}
	for key: String in _items:
		var xforms: Array = _items[key]
		var bits := key.rsplit("/", true, 1)
		for p: Dictionary in parts(bits[1], bits[0]):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = p.mesh
			mm.instance_count = xforms.size()
			var xf: Transform3D = p.xform
			for i in xforms.size():
				mm.set_instance_transform(i, (xforms[i] as Transform3D) * xf)
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%s_%s" % [name_prefix, bits[1], p.name]
			mmi.multimesh = mm
			mmi.visibility_range_end = draw_distance
			mmi.visibility_range_end_margin = 4.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mmi)
			made["%s/%s" % [bits[1], p.name]] = mmi
	_items.clear()
	return made
