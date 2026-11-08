extends Node
## Renders inventory icons from the items' 3D models with the game's own materials.
##   godot --path . res://tools/render_icons.tscn        (needs a GPU window, not --headless)
## Output: assets/ui/icons/<item_id>.png (256x256, transparent background)

const SIZE := 256
const OUT := "res://assets/ui/icons"

var _vp: SubViewport
var _cam: Camera3D
var _pivot: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.65)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, 35, 0)
	key.light_energy = 1.6
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 1.0
	rim.light_color = Color(0.6, 0.85, 1.0)
	_vp.add_child(rim)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp.add_child(_cam)
	_cam.current = true
	_render_all.call_deferred()


func _render_all() -> void:
	var ids: Array = Content.items.keys()
	ids.sort()
	for id: StringName in ids:
		var ps := PropFactory.model_for(String(id), "items")
		if ps == null:
			print("ICON skip %s (no model)" % id)
			continue
		if _pivot:
			_pivot.free()
		_pivot = Node3D.new()
		_vp.add_child(_pivot)
		var inst: Node3D = ps.instantiate()
		_pivot.add_child(inst)
		MaterialLibrary.apply_named(inst)
		# three-quarter view, framed to the model's bounds
		_pivot.rotation_degrees = Vector3(0, -35, 0)
		var aabb := _bounds(inst)
		var c := aabb.get_center()
		var r := maxf(aabb.size.length() * 0.5, 0.02)
		_cam.size = r * 2.15
		_cam.position = _pivot.global_transform * c + Vector3(0, r * 1.1, r * 2.2)
		_cam.look_at(_pivot.global_transform * c)
		for i in 4:
			await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		var path := OUT.path_join("%s.png" % id)
		img.save_png(ProjectSettings.globalize_path(path))
		print("ICON %s" % path)
	get_tree().quit()


func _bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.transform * m.get_aabb()
		var p := m.get_parent()
		while p and p != root:
			if p is Node3D:
				b = (p as Node3D).transform * b
			p = p.get_parent()
		out = b if first else out.merge(b)
		first = false
	return out
