class_name PropFactory
extends RefCounted
## Room dressing + development prop models. Dressing is deterministic per room (seeded by
## the room id). Props register loot points and searchable containers with the runtime.
## Real art: put a scene at res://scenes/environments/props/<kind>.tscn and it is used
## instead of the procedural model (collision is still provided here unless the scene
## contains its own StaticBody3D).

const DRAW_DIST := 45.0

## kind -> [[prop_kind, weight], ...] for wall slots
const WALL_PROPS := {
	"corridor": [["pipe_cluster", 2], ["bench", 1], ["crate_stack", 1], ["wall_cabinet", 1], ["vending", 0.4], ["", 6]],
	"office": [["filing_cabinet", 3], ["bookshelf", 2], ["plant", 1], ["water_cooler", 0.6], ["", 2]],
	"lab": [["fume_hood", 2], ["lab_cabinet", 3], ["specimen_tank", 1.5], ["", 2]],
	"storage": [["shelf_unit", 4], ["crate_stack", 2], ["barrel", 1], ["", 1]],
	"medical": [["med_bed", 3], ["med_cabinet", 2], ["iv_stand", 1], ["", 1.5]],
	"maintenance": [["tool_locker", 3], ["workbench", 2], ["barrel", 2], ["pipe_cluster", 2], ["", 1]],
	"server": [["server_rack", 4], ["", 1]],
	"generator": [["tank", 2], ["barrel", 2], ["tool_locker", 1], ["pipe_cluster", 2], ["", 2]],
	"security": [["locker", 3], ["monitor_desk", 2], ["", 1]],
	"lobby": [["bench", 2], ["plant", 2], ["", 2]],
	"elevator": [["bench", 1], ["plant", 1], ["", 4]],
	"tunnel": [["pipe_cluster", 3], ["crate_stack", 1], ["barrel", 1], ["", 4]],
	"pump": [["pump_unit", 2], ["tank", 1], ["pipe_cluster", 2], ["tool_locker", 1], ["", 2]],
	"hall": [["locker", 2], ["crate_stack", 2], ["barrel", 1], ["", 3]],
	"containment": [["containment_cell", 4], ["lab_cabinet", 1], ["", 1]],
	"control": [["monitor_desk", 4], ["filing_cabinet", 1], ["", 1]],
	"archive": [["bookshelf", 4], ["filing_cabinet", 2], ["", 1]],
	"outdoor": [["barrier", 2], ["crate_stack", 1], ["", 3]],
	"freezer": [["shelf_unit", 3], ["crate_stack", 3], ["tank", 1], ["", 1]],
	"dock": [["crate_stack", 3], ["barrel", 2], ["barrier", 1], ["", 2]],
	"stairs": [],
}

## Interior rows: kind -> [prop, length_tiles, row_spacing]
const INTERIOR := {
	"lab": ["lab_bench", 2, 3], "storage": ["shelf_row", 2, 3], "server": ["server_row", 2, 3],
	"office": ["desk_pair", 1, 3], "archive": ["shelf_row", 2, 3], "hall": ["pillar", 1, 4],
	"control": ["console_island", 2, 4], "freezer": ["shelf_row", 2, 3],
}

const CONTAINERS := ["filing_cabinet", "lab_cabinet", "med_cabinet", "tool_locker", "locker", "desk_pair"]
const NOTE_KEYS := ["NOTE_01", "NOTE_02", "NOTE_03", "NOTE_04", "NOTE_05", "NOTE_06", "NOTE_07"]

var b: FacilityBuilder
var _note_index := 0


func _init(builder: FacilityBuilder) -> void:
	b = builder


func _note_keys() -> Array:
	return Array(b.layout.notes) if b.layout and not b.layout.notes.is_empty() else NOTE_KEYS


func dress_room(room: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(room.id) + "_dress")
	var list: Array = WALL_PROPS.get(room.kind, [])
	if not list.is_empty():
		var slots: Array = b.wall_slots(room).duplicate()
		var used: Dictionary = {}
		for s: Dictionary in slots:
			var t: Vector2i = s.tile
			if b.is_blocked(room, t) or used.has(t):
				continue
			var kind := _weighted(list, rng)
			if kind.is_empty():
				continue
			used[t] = true
			var d: Vector2i = s.dir
			var depth := _depth(kind)
			var tx := t.x + 0.5 + d.x * (0.5 - (depth * 0.5 + FacilityBuilder.WALL_T * 0.5) / b.ts)
			var tz := t.y + 0.5 + d.y * (0.5 - (depth * 0.5 + FacilityBuilder.WALL_T * 0.5) / b.ts)
			var yaw := atan2(float(-d.x), float(-d.y))
			place(room, kind, b.world(room, tx, tz), yaw)
	_dress_interior(room, rng)
	_storytelling(room, rng)


func _dress_interior(room: Dictionary, rng: RandomNumberGenerator) -> void:
	if not INTERIOR.has(room.kind):
		return
	var spec: Array = INTERIOR[room.kind]
	var r: Rect2i = room.rect
	if r.size.x < 5 or r.size.y < 5:
		return
	var length: int = spec[1]
	var spacing: int = spec[2]
	var z := r.position.y + 2
	while z <= r.end.y - 3:
		var x := r.position.x + 2
		while x + length <= r.end.x - 2:
			var ok := true
			for i in length:
				var t := Vector2i(x + i, z)
				if b.is_blocked(room, t) or _near_door(room, t):
					ok = false
			if ok and rng.randf() < 0.85:
				for i in length:
					b.block(room, Vector2i(x + i, z))
				place(room, str(spec[0]), b.world(room, x + length * 0.5, z + 0.5), 0.0 if rng.randf() < 0.5 else PI)
			x += length + 1
		z += spacing


func _near_door(room: Dictionary, t: Vector2i) -> bool:
	for d: Dictionary in b.layout.doors:
		if (d.room_a == room.id and (d.a - t).length_squared() <= 2) or (d.room_b == room.id and (d.b - t).length_squared() <= 2):
			return true
	return false


func _storytelling(room: Dictionary, rng: RandomNumberGenerator) -> void:
	if room.outdoor or room.kind == "stairs":
		return
	var r: Rect2i = room.rect
	var node := b.room_node(room)
	# blood trails, debris and papers - placed on free floor tiles
	for i in rng.randi_range(1, 3):
		var t := Vector2i(rng.randi_range(r.position.x, r.end.x - 1), rng.randi_range(r.position.y, r.end.y - 1))
		var p := b.world(room, t.x + rng.randf(), t.y + rng.randf())
		var kind := rng.randf()
		if kind < 0.35:
			var smear := MeshKit.add_box(node, Vector3(rng.randf_range(0.4, 1.4), 0.01, rng.randf_range(0.2, 0.6)), "blood", p + Vector3.UP * 0.01, Vector3(0, rng.randf_range(0, 180), 0), DRAW_DIST)
			smear.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif kind < 0.75:
			for j in 4:
				var paper := MeshKit.add_box(node, Vector3(0.21, 0.004, 0.29), "plastic_white", p + Vector3(rng.randf_range(-0.5, 0.5), 0.01, rng.randf_range(-0.5, 0.5)), Vector3(0, rng.randf_range(0, 180), 0), 25.0)
				paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif not b.is_blocked(room, t):
			place(room, "debris", p, rng.randf_range(0, TAU))
	# readable notes (inspect) in rooms with people history
	if room.kind in ["office", "lab", "security", "medical", "control", "archive", "maintenance", "containment", "freezer"] and _note_index < _note_keys().size():
		var slots: Array = b.wall_slots(room)
		if not slots.is_empty():
			var s: Dictionary = slots[rng.randi_range(0, slots.size() - 1)]
			var t: Vector2i = s.tile
			var note := NoteInteractable.new()
			note.text_key = _note_keys()[_note_index]
			note.position = b.world(room, t.x + 0.5, t.y + 0.5) + Vector3.UP * 0.02
			note.rotation.y = rng.randf_range(0, TAU)
			node.add_child(note)
			note.room_id = room.id
			b.interactions.register_static(note)
			_note_index += 1


static func _weighted(list: Array, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for e: Array in list:
		total += float(e[1])
	var r := rng.randf() * total
	for e: Array in list:
		r -= float(e[1])
		if r <= 0.0:
			return str(e[0])
	return ""


static func _depth(kind: String) -> float:
	match kind:
		"shelf_unit", "bookshelf": return 0.6
		"med_bed": return 2.0
		"workbench", "fume_hood", "monitor_desk": return 0.8
		"server_rack": return 1.0
		"containment_cell": return 1.8
		"tank": return 1.4
		"pump_unit": return 1.2
		"pipe_cluster": return 0.4
	return 0.6


# --- placement ------------------------------------------------------------------------

func place(room: Dictionary, kind: String, pos: Vector3, yaw: float) -> Node3D:
	var node := Node3D.new()
	node.name = "%s_%d" % [kind, b.room_node(room).get_child_count()]
	node.position = pos
	node.rotation.y = yaw
	b.room_node(room).add_child(node)
	# collision, loot points and functional data always come from _build(); the visual is
	# the authored model when one exists (assets/props/<kind>.glb or a designer scene)
	_build(node, kind)
	var batch := batch_for(room)
	if batch.has_model(kind, "props"):
		for c in node.get_children():
			if c is MeshInstance3D:
				c.free()
		batch.add(kind, "props", node.transform)
	if kind in CONTAINERS:
		_make_container(room, node, kind)
	return node


static var _model_cache: Dictionary = {}
var _batches: Dictionary = {}  # room id -> MeshBatcher


func batch_for(room: Dictionary) -> MeshBatcher:
	if not _batches.has(room.id):
		_batches[room.id] = MeshBatcher.new()
	return _batches[room.id]


## Authored visual for a prop kind: designer scene first, then the generated model.
static func model_for(kind: String, folder: String = "props") -> PackedScene:
	var key := folder + "/" + kind
	if _model_cache.has(key):
		return _model_cache[key]
	var ps: PackedScene = null
	for path in ["res://scenes/environments/%s/%s.tscn" % [folder, kind], "res://assets/%s/%s.glb" % [folder, kind]]:
		if ResourceLoader.exists(path):
			ps = load(path)
			break
	_model_cache[key] = ps
	return ps


## Visibility-range culling + shadow policy for model instances.
static func set_draw_distance(root: Node, dist: float, shadows: bool = true) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.visibility_range_end = dist
		m.visibility_range_end_margin = 3.0
		m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if not shadows:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _body(node: Node3D, size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = FacilityBuilder.LAYER_WORLD
	body.collision_mask = 0
	node.add_child(body)
	MeshKit.add_collider(body, size, center)


func _loot(room: Dictionary, node: Node3D, local: Vector3) -> void:
	b.runtime.loot_points.append({"pos": node.global_transform * local if node.is_inside_tree() else node.transform * local, "room": room.id, "tags": room.loot_tags})


func _make_container(room: Dictionary, node: Node3D, kind: String) -> void:
	if room.loot_tags.is_empty():
		return
	var s := Searchable.new()
	s.container_kind = kind
	s.loot_tags = room.loot_tags
	s.position = Vector3(0, 0, 0.35)
	s.drop_offset = Vector3(0, 0.15, 0.5)
	s.room_id = room.id
	node.add_child(s)
	b.interactions.register_static(s)
	b.runtime.containers.append(s)


func elevator_car(room: Dictionary, aabb: AABB) -> void:
	var node := Node3D.new()
	node.name = "ElevatorCar"
	b.room_node(room).add_child(node)
	var c := aabb.get_center()
	var s := aabb.size
	var model := model_for("elevator_car", "environment")
	if model:
		var inst: Node3D = model.instantiate()
		inst.position = Vector3(c.x, aabb.position.y, c.z)
		node.add_child(inst)
		MaterialLibrary.apply_named(inst)
		set_draw_distance(inst, 45.0)
		return
	MeshKit.add_box(node, Vector3(s.x, 0.06, s.z), "floor_grate", Vector3(c.x, aabb.position.y + 0.03, c.z))
	MeshKit.add_box(node, Vector3(s.x + 0.3, 0.12, 0.3), "hazard", Vector3(c.x, aabb.position.y + 0.06, aabb.end.z + 0.1))
	MeshKit.add_box(node, Vector3(s.x, 0.25, s.z), "metal_dark", Vector3(c.x, aabb.position.y + 3.2, c.z))
	var lamp := MeshKit.add_box(node, Vector3(1.0, 0.05, 0.3), "emissive_white", Vector3(c.x, aabb.position.y + 3.06, c.z))
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build(n: Node3D, kind: String) -> void:
	var D := DRAW_DIST
	match kind:
		"pipe_cluster":
			for i in 3:
				MeshKit.add_cyl(n, 0.08 + i * 0.02, 2.0, "metal_dark" if i % 2 == 0 else "metal_painted", Vector3(-0.1 + i * 0.12, 3.2 - i * 0.18, 0), Vector3(0, 0, 90), D)
			MeshKit.add_cyl(n, 0.07, 3.4, "metal_painted", Vector3(0.6, 1.7, 0.05), Vector3.ZERO, D)
		"bench":
			MeshKit.add_box(n, Vector3(1.6, 0.08, 0.45), "metal_painted", Vector3(0, 0.45, 0), Vector3.ZERO, D)
			for s in [-0.7, 0.7]:
				MeshKit.add_box(n, Vector3(0.06, 0.45, 0.4), "metal_dark", Vector3(s, 0.22, 0), Vector3.ZERO, D)
			_body(n, Vector3(1.6, 0.5, 0.45), Vector3(0, 0.25, 0))
		"crate_stack":
			MeshKit.add_box(n, Vector3(0.9, 0.8, 0.9), "cardboard", Vector3(0, 0.4, 0), Vector3(0, 7, 0), D)
			MeshKit.add_box(n, Vector3(0.7, 0.6, 0.7), "cardboard", Vector3(0.05, 1.1, 0), Vector3(0, -12, 0), D)
			_body(n, Vector3(0.95, 1.4, 0.95), Vector3(0, 0.7, 0))
		"wall_cabinet":
			MeshKit.add_box(n, Vector3(0.9, 0.8, 0.4), "metal_painted", Vector3(0, 1.5, 0), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(0.86, 0.02, 0.38), "metal_dark", Vector3(0, 1.5, 0.01), Vector3.ZERO, D)
		"vending":
			MeshKit.add_box(n, Vector3(1.0, 1.9, 0.8), "plastic_dark", Vector3(0, 0.95, 0), Vector3.ZERO, D)
			var front := MeshKit.add_box(n, Vector3(0.7, 1.2, 0.02), "screen_on", Vector3(-0.1, 1.15, 0.41), Vector3.ZERO, D)
			front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_body(n, Vector3(1.0, 1.9, 0.8), Vector3(0, 0.95, 0))
		"filing_cabinet":
			MeshKit.add_box(n, Vector3(0.5, 1.3, 0.6), "metal_painted", Vector3(0, 0.65, 0), Vector3.ZERO, D)
			for i in 3:
				MeshKit.add_box(n, Vector3(0.15, 0.03, 0.03), "metal_bright", Vector3(0, 0.3 + i * 0.4, 0.31), Vector3.ZERO, D)
			_body(n, Vector3(0.5, 1.3, 0.6), Vector3(0, 0.65, 0))
		"bookshelf", "shelf_unit":
			var mat := "wood" if kind == "bookshelf" else "metal_painted"
			for s in [-0.85, 0.85]:
				MeshKit.add_box(n, Vector3(0.05, 2.1, 0.55), mat, Vector3(s, 1.05, 0), Vector3.ZERO, D)
			for i in 4:
				MeshKit.add_box(n, Vector3(1.7, 0.04, 0.55), mat, Vector3(0, 0.2 + i * 0.6, 0), Vector3.ZERO, D)
				if i < 3:
					MeshKit.add_box(n, Vector3(0.5, 0.3, 0.4), "cardboard", Vector3(-0.4 + (i % 2) * 0.7, 0.37 + i * 0.6, 0), Vector3(0, i * 9, 0), D)
			_body(n, Vector3(1.8, 2.1, 0.55), Vector3(0, 1.05, 0))
			_loot_on(n, Vector3(0.45, 0.83, 0))
			_loot_on(n, Vector3(-0.4, 1.43, 0))
		"plant":
			MeshKit.add_cyl(n, 0.22, 0.45, "plastic_dark", Vector3(0, 0.22, 0), Vector3.ZERO, D)
			MeshKit.add_mesh(n, MeshKit.sphere_mesh(0.4, 8), "fabric", Vector3(0, 0.8, 0), Vector3.ZERO, D)
		"water_cooler":
			MeshKit.add_box(n, Vector3(0.35, 1.0, 0.35), "plastic_white", Vector3(0, 0.5, 0), Vector3.ZERO, D)
			MeshKit.add_cyl(n, 0.14, 0.45, "glass", Vector3(0, 1.22, 0), Vector3.ZERO, D)
		"fume_hood":
			MeshKit.add_box(n, Vector3(1.6, 0.9, 0.8), "plastic_white", Vector3(0, 0.45, 0), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(1.6, 1.1, 0.8), "metal_bright", Vector3(0, 1.45, -0.05), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(1.5, 0.7, 0.02), "glass", Vector3(0, 1.35, 0.36), Vector3(-10, 0, 0), D)
			_body(n, Vector3(1.6, 2.0, 0.8), Vector3(0, 1.0, 0))
			_loot_on(n, Vector3(0.3, 0.93, 0.1))
		"lab_cabinet", "med_cabinet":
			MeshKit.add_box(n, Vector3(0.9, 1.9, 0.5), "plastic_white", Vector3(0, 0.95, 0), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(0.8, 0.9, 0.02), "glass", Vector3(0, 1.4, 0.26), Vector3.ZERO, D)
			if kind == "med_cabinet":
				MeshKit.add_box(n, Vector3(0.2, 0.06, 0.02), "emissive_red", Vector3(0, 1.75, 0.27), Vector3.ZERO, D)
			_body(n, Vector3(0.9, 1.9, 0.5), Vector3(0, 0.95, 0))
		"specimen_tank":
			MeshKit.add_cyl(n, 0.45, 0.2, "metal_dark", Vector3(0, 0.1, 0), Vector3.ZERO, D)
			MeshKit.add_cyl(n, 0.4, 1.6, "glass", Vector3(0, 1.0, 0), Vector3.ZERO, D)
			MeshKit.add_cyl(n, 0.36, 1.2, "biohazard_liquid", Vector3(0, 0.8, 0), Vector3.ZERO, D)
			MeshKit.add_cyl(n, 0.45, 0.2, "metal_dark", Vector3(0, 1.9, 0), Vector3.ZERO, D)
			_body(n, Vector3(0.9, 2.0, 0.9), Vector3(0, 1.0, 0))
		"med_bed":
			MeshKit.add_box(n, Vector3(0.9, 0.12, 1.9), "metal_bright", Vector3(0, 0.6, 0), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(0.85, 0.12, 1.85), "plastic_white", Vector3(0, 0.72, 0), Vector3.ZERO, D)
			for sx in [-0.4, 0.4]:
				for sz in [-0.85, 0.85]:
					MeshKit.add_cyl(n, 0.03, 0.6, "metal_dark", Vector3(sx, 0.3, sz), Vector3.ZERO, D)
			_body(n, Vector3(0.9, 0.8, 1.9), Vector3(0, 0.4, 0))
			_loot_on(n, Vector3(0.1, 0.8, 0.4))
		"iv_stand":
			MeshKit.add_cyl(n, 0.02, 1.9, "metal_bright", Vector3(0, 0.95, 0), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(0.12, 0.2, 0.05), "glass", Vector3(0.1, 1.7, 0), Vector3.ZERO, D)
		"tool_locker", "locker":
			MeshKit.add_box(n, Vector3(0.6, 1.95, 0.55), "metal_painted" if kind == "locker" else "metal_yellow", Vector3(0, 0.975, 0), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(0.4, 0.04, 0.02), "metal_dark", Vector3(0, 1.7, 0.28), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(0.4, 0.04, 0.02), "metal_dark", Vector3(0, 1.6, 0.28), Vector3.ZERO, D)
			_body(n, Vector3(0.6, 1.95, 0.55), Vector3(0, 0.975, 0))
		"workbench":
			MeshKit.add_box(n, Vector3(1.8, 0.08, 0.8), "wood", Vector3(0, 0.9, 0), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(1.8, 0.8, 0.05), "metal_dark", Vector3(0, 1.4, -0.38), Vector3.ZERO, D)
			for sx in [-0.85, 0.85]:
				MeshKit.add_box(n, Vector3(0.06, 0.9, 0.7), "metal_dark", Vector3(sx, 0.45, 0), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(0.35, 0.2, 0.25), "metal_yellow", Vector3(-0.5, 1.04, 0.1), Vector3.ZERO, D)
			_body(n, Vector3(1.8, 1.0, 0.8), Vector3(0, 0.5, 0))
			_loot_on(n, Vector3(0.4, 0.97, 0.1))
		"barrel":
			MeshKit.add_cyl(n, 0.3, 0.9, "metal_yellow" if int(n.position.x) % 2 == 0 else "metal_painted", Vector3(0, 0.45, 0), Vector3.ZERO, D)
			_body(n, Vector3(0.6, 0.9, 0.6), Vector3(0, 0.45, 0))
		"server_rack", "server_row":
			var count := 1 if kind == "server_rack" else 3
			for i in count:
				var x := (i - (count - 1) * 0.5) * 0.66
				MeshKit.add_box(n, Vector3(0.62, 2.1, 1.0), "plastic_dark", Vector3(x, 1.05, 0), Vector3.ZERO, D)
				for j in 5:
					var led := MeshKit.add_box(n, Vector3(0.5, 0.025, 0.02), "emissive_cyan" if (i + j) % 3 != 0 else "emissive_green", Vector3(x, 0.4 + j * 0.35, 0.51), Vector3.ZERO, 30.0)
					led.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_body(n, Vector3(0.66 * count, 2.1, 1.0), Vector3(0, 1.05, 0))
			if kind == "server_row":
				_loot_on(n, Vector3(0, 2.12, 0))
		"tank":
			MeshKit.add_cyl(n, 0.7, 2.4, "metal_painted", Vector3(0, 1.2, 0), Vector3.ZERO, D)
			MeshKit.add_cyl(n, 0.1, 0.8, "metal_dark", Vector3(0, 2.6, 0), Vector3.ZERO, D)
			_body(n, Vector3(1.4, 2.4, 1.4), Vector3(0, 1.2, 0))
		"pump_unit":
			MeshKit.add_box(n, Vector3(1.4, 0.2, 1.2), "metal_dark", Vector3(0, 0.1, 0), Vector3.ZERO, D)
			MeshKit.add_cyl(n, 0.4, 1.0, "metal_yellow", Vector3(0, 0.7, 0), Vector3(0, 0, 90), D)
			MeshKit.add_cyl(n, 0.12, 2.4, "metal_dark", Vector3(0.5, 1.6, 0), Vector3.ZERO, D)
			_body(n, Vector3(1.4, 1.2, 1.2), Vector3(0, 0.6, 0))
		"monitor_desk":
			MeshKit.add_box(n, Vector3(1.6, 0.06, 0.8), "plastic_dark", Vector3(0, 0.75, 0), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(1.5, 0.72, 0.7), "metal_painted", Vector3(0, 0.36, -0.03), Vector3.ZERO, D)
			for s in [-0.4, 0.4]:
				var scr := MeshKit.add_box(n, Vector3(0.6, 0.38, 0.03), "screen_on" if s < 0 else "screen_red", Vector3(s, 1.05, -0.2), Vector3(-8, 0, 0), 30.0)
				scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_body(n, Vector3(1.6, 0.8, 0.8), Vector3(0, 0.4, 0))
			_loot_on(n, Vector3(0.3, 0.8, 0.2))
		"containment_cell":
			MeshKit.add_box(n, Vector3(1.9, 0.15, 1.7), "metal_dark", Vector3(0, 0.07, 0), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(1.9, 0.2, 1.7), "metal_dark", Vector3(0, 2.9, 0), Vector3.ZERO, D)
			var gl := MeshKit.add_box(n, Vector3(1.8, 2.7, 0.05), "glass", Vector3(0, 1.45, 0.82), Vector3.ZERO, D)
			gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var crack := MeshKit.add_box(n, Vector3(0.6, 1.2, 0.06), "blood", Vector3(0.3, 1.0, 0.8), Vector3(0, 0, 18), D)
			crack.visible = int(abs(n.position.z * 7.0)) % 3 == 0
			MeshKit.add_box(n, Vector3(1.8, 0.05, 0.05), "emissive_cyan", Vector3(0, 2.75, 0.8), Vector3.ZERO, D)
			_body(n, Vector3(1.9, 3.0, 1.7), Vector3(0, 1.5, 0))
		"lab_bench":
			MeshKit.add_box(n, Vector3(3.6, 0.08, 1.2), "plastic_white", Vector3(0, 0.92, 0), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(3.5, 0.86, 1.1), "metal_painted", Vector3(0, 0.44, 0), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(0.4, 0.45, 0.35), "plastic_dark", Vector3(-1.1, 1.18, 0.1), Vector3.ZERO, D)
			MeshKit.add_cyl(n, 0.07, 0.25, "glass", Vector3(0.6, 1.08, -0.2), Vector3.ZERO, 30.0)
			MeshKit.add_cyl(n, 0.05, 0.2, "biohazard_liquid", Vector3(0.8, 1.06, -0.25), Vector3.ZERO, 30.0)
			var scr2 := MeshKit.add_box(n, Vector3(0.55, 0.35, 0.03), "screen_on", Vector3(1.2, 1.2, 0.0), Vector3(0, 180, 0), 30.0)
			scr2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_body(n, Vector3(3.6, 1.0, 1.2), Vector3(0, 0.5, 0))
			_loot_on(n, Vector3(0.0, 0.98, 0.3))
			_loot_on(n, Vector3(-0.5, 0.98, -0.3))
		"shelf_row":
			for i in 2:
				var x2 := -0.9 + i * 1.8
				for s in [-0.85, 0.85]:
					MeshKit.add_box(n, Vector3(0.05, 2.1, 0.7), "metal_painted", Vector3(x2 + s, 1.05, 0), Vector3.ZERO, D)
				for j in 4:
					MeshKit.add_box(n, Vector3(1.7, 0.04, 0.7), "metal_painted", Vector3(x2, 0.2 + j * 0.6, 0), Vector3.ZERO, D)
					if (i + j) % 2 == 0:
						MeshKit.add_box(n, Vector3(0.6, 0.35, 0.5), "cardboard", Vector3(x2 - 0.3, 0.4 + j * 0.6, 0), Vector3(0, j * 11, 0), D)
			_body(n, Vector3(3.6, 2.1, 0.7), Vector3(0, 1.05, 0))
			_loot_on(n, Vector3(0.6, 0.83, 0))
			_loot_on(n, Vector3(-1.2, 1.43, 0))
		"desk_pair":
			MeshKit.add_box(n, Vector3(1.6, 0.05, 0.8), "wood", Vector3(0, 0.74, 0), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(0.45, 0.7, 0.75), "metal_painted", Vector3(0.55, 0.36, 0), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(0.05, 0.7, 0.75), "metal_painted", Vector3(-0.75, 0.36, 0), Vector3.ZERO, D)
			var mon := MeshKit.add_box(n, Vector3(0.55, 0.35, 0.03), "screen_off", Vector3(-0.1, 1.0, -0.25), Vector3.ZERO, 30.0)
			mon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			MeshKit.add_box(n, Vector3(0.5, 0.5, 0.5), "fabric", Vector3(-0.2, 0.45, 0.75), Vector3(0, 20, 0), D)
			_body(n, Vector3(1.6, 0.78, 0.8), Vector3(0, 0.39, 0))
			_loot_on(n, Vector3(0.4, 0.79, 0.15))
		"pillar":
			MeshKit.add_box(n, Vector3(0.7, 4.0, 0.7), "wall_concrete", Vector3(0, 2.0, 0), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(0.72, 0.15, 0.72), "hazard", Vector3(0, 0.3, 0), Vector3.ZERO, D)
			_body(n, Vector3(0.7, 4.0, 0.7), Vector3(0, 2.0, 0))
		"console_island":
			MeshKit.add_box(n, Vector3(3.4, 1.0, 1.0), "metal_painted", Vector3(0, 0.5, 0), Vector3.ZERO, D)
			for i in 3:
				var s3 := MeshKit.add_box(n, Vector3(0.8, 0.45, 0.03), "screen_on", Vector3(-1.1 + i * 1.1, 1.3, 0.1), Vector3(-15, 0, 0), 30.0)
				s3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_body(n, Vector3(3.4, 1.0, 1.0), Vector3(0, 0.5, 0))
			_loot_on(n, Vector3(1.2, 1.03, 0.3))
		"barrier":
			MeshKit.add_box(n, Vector3(2.0, 0.9, 0.5), "wall_concrete", Vector3(0, 0.45, 0), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(2.0, 0.12, 0.52), "hazard", Vector3(0, 0.75, 0), Vector3.ZERO, D)
			_body(n, Vector3(2.0, 0.9, 0.5), Vector3(0, 0.45, 0))
		"lamp_post":
			MeshKit.add_cyl(n, 0.08, 5.0, "metal_dark", Vector3(0, 2.5, 0), Vector3.ZERO, 70.0)
			MeshKit.add_box(n, Vector3(0.9, 0.08, 0.08), "metal_dark", Vector3(0.4, 4.95, 0.4), Vector3(0, -45, 0), 70.0)
			var bulb := MeshKit.add_box(n, Vector3(0.4, 0.1, 0.25), "emissive_amber", Vector3(0.6, 4.88, 0.6), Vector3(0, -45, 0), 70.0)
			bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_body(n, Vector3(0.2, 5.0, 0.2), Vector3(0, 2.5, 0))
		"evac_beacon":
			MeshKit.add_cyl(n, 0.5, 0.3, "metal_dark", Vector3(0, 0.15, 0), Vector3.ZERO, 80.0)
			MeshKit.add_cyl(n, 0.12, 2.2, "metal_yellow", Vector3(0, 1.3, 0), Vector3.ZERO, 80.0)
			var beacon := MeshKit.add_mesh(n, MeshKit.sphere_mesh(0.22, 10), "emissive_off", Vector3(0, 2.5, 0), Vector3.ZERO, 120.0)
			beacon.name = "Beacon"
			_body(n, Vector3(0.6, 2.4, 0.6), Vector3(0, 1.2, 0))
		"vehicle":
			MeshKit.add_box(n, Vector3(2.2, 1.2, 4.6), "metal_painted", Vector3(0, 0.95, 0), Vector3.ZERO, 70.0)
			MeshKit.add_box(n, Vector3(2.1, 0.9, 2.0), "metal_painted", Vector3(0, 1.95, -0.8), Vector3.ZERO, 70.0)
			MeshKit.add_box(n, Vector3(2.0, 0.6, 0.04), "glass", Vector3(0, 2.0, 0.21), Vector3.ZERO, 70.0)
			for sx in [-1.05, 1.05]:
				for sz in [-1.5, 1.5]:
					MeshKit.add_cyl(n, 0.42, 0.3, "rubber", Vector3(sx, 0.42, sz), Vector3(0, 0, 90), 70.0)
			var hl := MeshKit.add_box(n, Vector3(1.8, 0.12, 0.05), "emissive_amber", Vector3(0, 1.3, -2.31), Vector3.ZERO, 70.0)
			hl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_body(n, Vector3(2.2, 2.4, 4.6), Vector3(0, 1.2, 0))
		"reception_desk":
			MeshKit.add_box(n, Vector3(4.0, 1.1, 0.8), "wood", Vector3(0, 0.55, 0), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(4.1, 0.06, 0.95), "metal_bright", Vector3(0, 1.12, 0), Vector3.ZERO, D)
			_body(n, Vector3(4.0, 1.1, 0.8), Vector3(0, 0.55, 0))
			_loot_on(n, Vector3(1.2, 1.17, 0))
		"scanner_gate":
			for s in [-0.9, 0.9]:
				MeshKit.add_box(n, Vector3(0.2, 2.2, 0.6), "plastic_dark", Vector3(s, 1.1, 0), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(2.0, 0.2, 0.6), "plastic_dark", Vector3(0, 2.3, 0), Vector3.ZERO, D)
			MeshKit.add_box(n, Vector3(1.6, 0.04, 0.04), "emissive_red", Vector3(0, 2.18, 0.3), Vector3.ZERO, D)
			for s in [-0.9, 0.9]:
				_body(n, Vector3(0.2, 2.2, 0.6), Vector3(s, 1.1, 0))
		"debris":
			MeshKit.add_box(n, Vector3(0.6, 0.15, 0.4), "wall_concrete", Vector3(0, 0.07, 0), Vector3(0, 0, 8), 30.0)
			MeshKit.add_box(n, Vector3(0.3, 0.1, 0.3), "metal_dark", Vector3(0.35, 0.05, 0.2), Vector3(5, 30, 0), 30.0)
		_:
			MeshKit.add_box(n, Vector3(0.6, 0.6, 0.6), "metal_painted", Vector3(0, 0.3, 0), Vector3.ZERO, D)


func _loot_on(n: Node3D, local: Vector3) -> void:
	# The room dictionary is resolved from the parent room node name.
	var room_node := n.get_parent()
	var room_id := StringName(String(room_node.name).trim_prefix("Room_"))
	var room: Dictionary = b.layout.room_by_id.get(room_id, {})
	if room.is_empty() or (room.loot_tags as PackedStringArray).is_empty():
		return
	b.runtime.loot_points.append({"pos": n.transform * local, "room": room_id, "tags": room.loot_tags})
