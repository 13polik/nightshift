class_name FacilityBuilder
extends RefCounted
## Turns a FacilityLayout into geometry, collision, navigation source, doors, devices,
## lights and dressing. Fully deterministic: same layout => same scene on every peer.
##
## Geometry strategy (mobile): one merged ArrayMesh per room (floor / walls / ceiling
## surfaces) so each room is a single cullable draw group; collision uses merged boxes.

const WALL_T := 0.25
const DOOR_TOP := 2.85
const OPEN_TOP := 3.2
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const LAYER_WORLD := 1
const LAYER_CEILING := 64

const KIND_MATERIALS := {
	"outdoor": ["floor_asphalt", "wall_concrete"], "lobby": ["floor_tile", "wall_panel"],
	"security": ["floor_tile", "wall_panel"], "corridor": ["floor_concrete", "wall_panel"],
	"office": ["floor_tile", "wall_panel"], "storage": ["floor_concrete", "wall_industrial"],
	"medical": ["floor_tile", "wall_medical"], "lab": ["floor_tile", "wall_lab"],
	"maintenance": ["floor_grate", "wall_industrial"], "stairs": ["floor_grate", "wall_concrete"],
	"server": ["floor_grate", "wall_panel"], "elevator": ["floor_tile", "wall_panel"],
	"generator": ["floor_concrete", "wall_industrial"], "tunnel": ["floor_concrete", "wall_concrete"],
	"pump": ["floor_grate", "wall_industrial"], "hall": ["floor_concrete", "wall_concrete"],
	"containment": ["floor_tile", "wall_lab"], "control": ["floor_tile", "wall_panel"],
	"archive": ["floor_concrete", "wall_panel"],
	"freezer": ["floor_freezer", "wall_freezer"], "dock": ["floor_concrete", "wall_concrete"],
}

const LIGHT_COLORS := {
	"lab": Color(0.82, 0.92, 1.0), "medical": Color(0.85, 0.95, 1.0), "containment": Color(0.75, 0.95, 0.9),
	"maintenance": Color(1.0, 0.78, 0.5), "generator": Color(1.0, 0.75, 0.45), "pump": Color(1.0, 0.8, 0.55),
	"tunnel": Color(1.0, 0.82, 0.6), "server": Color(0.6, 0.85, 1.0), "outdoor": Color(1.0, 0.7, 0.4),
	"freezer": Color(0.55, 0.78, 1.0), "dock": Color(1.0, 0.72, 0.42),
}

var layout: FacilityLayout
var runtime: FacilityRuntime
var interactions: InteractionService
var ts: float = 2.0
var props: PropFactory
var _wall_edges: Dictionary = {}   # collision edges
var _blocked: Dictionary = {}      # room id -> {Vector2i: true}
var _wall_slots: Dictionary = {}   # room id -> Array[{tile, dir}]
var _world_body: StaticBody3D
var _ceiling_body: StaticBody3D
var _room_st: Dictionary = {}      # room id -> {floor, wall, ceiling: SurfaceTool}
var _elevator_panels: Dictionary = {} # room id -> ElevatorPanel


static func build(p_layout: FacilityLayout, parent: Node3D, p_interactions: InteractionService) -> FacilityRuntime:
	var b := FacilityBuilder.new()
	b.layout = p_layout
	b.interactions = p_interactions
	b.ts = p_layout.tile_size
	return b._build(parent)


func _build(parent: Node3D) -> FacilityRuntime:
	var t0 := Time.get_ticks_msec()
	runtime = FacilityRuntime.new()
	runtime.name = "Facility"
	runtime.layout = layout
	parent.add_child(runtime)

	var nav := NavigationRegion3D.new()
	nav.name = "Navigation"
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 2.2
	nm.agent_max_climb = 0.4
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.25
	nm.cell_height = 0.2
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = LAYER_WORLD
	nm.region_min_size = 4.0
	nav.navigation_mesh = nm
	runtime.add_child(nav)
	runtime.nav_region = nav

	_world_body = StaticBody3D.new()
	_world_body.name = "WorldCollision"
	_world_body.collision_layer = LAYER_WORLD
	_world_body.collision_mask = 0
	nav.add_child(_world_body)
	_ceiling_body = StaticBody3D.new()
	_ceiling_body.name = "CeilingCollision"
	_ceiling_body.collision_layer = LAYER_CEILING
	_ceiling_body.collision_mask = 0
	runtime.add_child(_ceiling_body)

	props = PropFactory.new(self)

	for room in layout.rooms:
		var node := Node3D.new()
		node.name = "Room_%s" % room.id
		nav.add_child(node)
		runtime.room_info[room.id] = {
			"aabb": layout.room_aabb(room), "tags": room.tags, "level": room.level,
			"zone": room.power_zone, "name_key": str(room.get("name_key", "")), "kind": room.kind,
			"outdoor": room.outdoor, "node": node,
		}
		_blocked[room.id] = {}
		_wall_slots[room.id] = []
		var mats: Array = KIND_MATERIALS.get(room.kind, ["floor_concrete", "wall_panel"])
		_room_st[room.id] = {
			"floor": _new_st(), "wall": _new_st(), "ceiling": _new_st(),
			"floor_mat": mats[0], "wall_mat": mats[1],
		}
		_block_special_tiles(room)
	for room in layout.rooms:
		_build_floor_ceiling(room)
		_collect_walls(room)
	_build_doors()
	_build_wall_collision()
	for room in layout.rooms:
		_build_features(room)
	_link_elevators()
	for room in layout.rooms:
		props.dress_room(room)
		_detail_room(room)
		_build_lights(room)
		_flush_room(room)
	for room in layout.rooms:
		_commit_room_mesh(room)
	_build_patrol_routes()
	Log.i("facility", "built '%s': %d rooms, %d doors, %d devices, %d containers, %d loot points, %d lights in %d ms" % [
		layout.id, layout.rooms.size(), runtime.doors.size(), runtime.devices.size(), runtime.containers.size(),
		runtime.loot_points.size(), runtime.lights.size(), Time.get_ticks_msec() - t0])
	return runtime


func room_node(room: Dictionary) -> Node3D:
	return runtime.room_info[room.id].node


func _new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _block_special_tiles(room: Dictionary) -> void:
	var blk: Dictionary = _blocked[room.id]
	for f: Dictionary in room.features:
		var p: Array = f.pos
		var t := Vector2i(floori(float(p[0])), floori(float(p[1])))
		blk[t] = true
		if f.get("kind", "") in ["generator", "containment_console", "vehicle"]:
			for dx in range(-2, 3):
				for dz in range(-2, 3):
					blk[t + Vector2i(dx, dz)] = true
	if room.has("elevator"):
		var car: Array = room.elevator.car
		for x in range(int(car[0]), int(car[0]) + int(car[2])):
			for z in range(int(car[1]), int(car[1]) + int(car[3]) + 1):
				blk[Vector2i(x, z)] = true
	if room.has("ramp"):
		for x in range(room.rect.position.x, room.rect.end.x):
			for z in range(int(room.ramp.from), int(room.ramp.to) + 1):
				blk[Vector2i(x, z)] = true
	for d in layout.doors:
		if d.room_a == room.id:
			blk[d.a] = true
		if d.room_b == room.id:
			blk[d.b] = true


func is_blocked(room: Dictionary, tile: Vector2i) -> bool:
	return _blocked[room.id].has(tile)


func block(room: Dictionary, tile: Vector2i) -> void:
	_blocked[room.id][tile] = true


func wall_slots(room: Dictionary) -> Array:
	return _wall_slots[room.id]


func floor_at(room: Dictionary, tx: float, tz: float) -> float:
	return layout.floor_y(room, tx, tz)


func world(room: Dictionary, tx: float, tz: float) -> Vector3:
	return layout.tile_to_world(tx, tz, floor_at(room, tx, tz))


# --- floors & ceilings ----------------------------------------------------------------

func _build_floor_ceiling(room: Dictionary) -> void:
	var r: Rect2i = room.rect
	var st: Dictionary = _room_st[room.id]
	var h := layout.level_height(room.level)
	var x0 := r.position.x * ts
	var x1 := r.end.x * ts
	var segments: Array = [] # [z_start_tile, z_end_tile]
	if room.has("ramp"):
		var from := int(room.ramp.from)
		var to := int(room.ramp.to) + 1
		if from > r.position.y:
			segments.append([r.position.y, from])
		segments.append([from, to])
		if to < r.end.y:
			segments.append([to, r.end.y])
	else:
		segments.append([r.position.y, r.end.y])
	for seg in segments:
		var za: float = float(seg[0])
		var zb: float = float(seg[1])
		var ya := floor_at(room, r.position.x + 0.5, za)
		var yb := floor_at(room, r.position.x + 0.5, zb)
		var z0 := za * ts
		var z1 := zb * ts
		var n := Vector3(0, z1 - z0, -(yb - ya)).normalized() if absf(yb - ya) > 0.001 else Vector3.UP
		# Floor quad (normal up): (x0,z1) (x1,z1) (x1,z0) (x0,z0)
		MeshKit.st_quad(st.floor, Vector3(x0, yb, z1), Vector3(x1, yb, z1), Vector3(x1, ya, z0), Vector3(x0, ya, z0), n)
		if not room.outdoor:
			MeshKit.st_quad(st.ceiling, Vector3(x0, ya + h, z0), Vector3(x1, ya + h, z0), Vector3(x1, yb + h, z1), Vector3(x0, yb + h, z1), -n)
		# collision slab
		var length := Vector2(z1 - z0, yb - ya).length()
		var angle := rad_to_deg(atan2(-(yb - ya), z1 - z0))
		var center := Vector3((x0 + x1) * 0.5, (ya + yb) * 0.5, (z0 + z1) * 0.5) - n * 0.15
		MeshKit.add_collider(_world_body, Vector3(x1 - x0, 0.3, length), center, Vector3(angle, 0, 0))
		if not room.outdoor:
			MeshKit.add_collider(_ceiling_body, Vector3(x1 - x0, 0.3, length), center + n * (h + 0.3), Vector3(angle, 0, 0))


# --- walls ----------------------------------------------------------------------------

func _collect_walls(room: Dictionary) -> void:
	var r: Rect2i = room.rect
	var level: int = room.level
	var h := layout.level_height(level)
	var runs: Dictionary = {}  # flat rooms: "dir|line|y0|y1" -> Array[int along]
	var ramp := room.has("ramp")
	for x in range(r.position.x, r.end.x):
		for z in range(r.position.y, r.end.y):
			var t := Vector2i(x, z)
			for di in 4:
				var d: Vector2i = DIRS[di]
				var nt := t + d
				if layout.room_at(level, nt) == room.id:
					continue
				var door := layout.door_on_edge(level, t, nt)
				if not door.is_empty():
					continue
				var along := z if d.x != 0 else x
				var line := (x + 1 if d.x > 0 else x) if d.x != 0 else (z + 1 if d.y > 0 else z)
				var e0 := _edge_endpoints(t, d)
				var y0 := minf(floor_at(room, e0[0].x, e0[0].y), floor_at(room, e0[1].x, e0[1].y))
				var y1 := maxf(floor_at(room, e0[0].x, e0[0].y), floor_at(room, e0[1].x, e0[1].y)) + h
				_add_collision_edge(level, d.x != 0, line, along, y0 - 0.1, y1 + 0.1)
				(_wall_slots[room.id] as Array).append({"tile": t, "dir": d})
				if ramp:
					_wall_face(room, t, d, 1)
				else:
					var key := "%d|%d" % [di, line]
					if not runs.has(key):
						runs[key] = []
					runs[key].append(along)
	for key: String in runs:
		var parts := key.split("|")
		var di := int(parts[0])
		var line := int(parts[1])
		var list: Array = runs[key]
		list.sort()
		var start: int = list[0]
		var prev: int = list[0]
		for i in range(1, list.size() + 1):
			if i < list.size() and list[i] == prev + 1:
				prev = list[i]
				continue
			var d: Vector2i = DIRS[di]
			var tile := Vector2i(line - 1 if d.x > 0 else line, start) if d.x != 0 else Vector2i(start, line - 1 if d.y > 0 else line)
			_wall_face(room, tile, d, prev - start + 1)
			if i < list.size():
				start = list[i]
				prev = list[i]


## Endpoints (tile coords) of the edge on side `d` of tile `t`.
func _edge_endpoints(t: Vector2i, d: Vector2i) -> Array[Vector2]:
	if d.x != 0:
		var lx := float(t.x + 1 if d.x > 0 else t.x)
		return [Vector2(lx, t.y), Vector2(lx, t.y + 1)]
	var lz := float(t.y + 1 if d.y > 0 else t.y)
	return [Vector2(t.x, lz), Vector2(t.x + 1, lz)]


## Adds an inward-facing wall quad covering `count` tiles starting at tile `t` along the edge.
func _wall_face(room: Dictionary, t: Vector2i, d: Vector2i, count: int) -> void:
	var h := layout.level_height(room.level)
	var n := Vector3(-d.x, 0, -d.y)       # faces into the room
	var inset := WALL_T * 0.5
	var p0: Vector2
	var p1: Vector2
	if d.x != 0:
		var lx := float(t.x + 1 if d.x > 0 else t.x)
		p0 = Vector2(lx, t.y)
		p1 = Vector2(lx, t.y + count)
	else:
		var lz := float(t.y + 1 if d.y > 0 else t.y)
		p0 = Vector2(t.x, lz)
		p1 = Vector2(t.x + count, lz)
	var y0a := floor_at(room, p0.x, p0.y)
	var y0b := floor_at(room, p1.x, p1.y)
	var ext := inset / ts
	var a2 := p0 - (p1 - p0).normalized() * ext
	var b2 := p1 + (p1 - p0).normalized() * ext
	var wa := Vector3(a2.x * ts, 0, a2.y * ts) + n * inset
	var wb := Vector3(b2.x * ts, 0, b2.y * ts) + n * inset
	# order endpoints so (b - a) points to the viewer's right when facing the wall
	var right := (-n).cross(Vector3.UP)
	if (wb - wa).dot(right) < 0.0:
		var tmp := wa
		wa = wb
		wb = tmp
		var ty := y0a
		y0a = y0b
		y0b = ty
	var st: SurfaceTool = _room_st[room.id].wall
	MeshKit.st_quad(st, wa + Vector3.UP * (y0a - 0.02), wb + Vector3.UP * (y0b - 0.02), wb + Vector3.UP * (y0b + h + 0.02), wa + Vector3.UP * (y0a + h + 0.02), n)


func _add_collision_edge(level: int, x_axis: bool, line: int, along: int, y0: float, y1: float) -> void:
	var key := "%d|%s|%d|%d" % [level, "x" if x_axis else "z", line, along]
	if _wall_edges.has(key):
		var e: Dictionary = _wall_edges[key]
		e.y0 = minf(e.y0, y0)
		e.y1 = maxf(e.y1, y1)
	else:
		_wall_edges[key] = {"level": level, "x_axis": x_axis, "line": line, "along": along, "y0": y0, "y1": y1}


func _build_wall_collision() -> void:
	var groups: Dictionary = {}
	for e: Dictionary in _wall_edges.values():
		var gk := "%d|%s|%d|%.2f|%.2f" % [e.level, e.x_axis, e.line, e.y0, e.y1]
		if not groups.has(gk):
			groups[gk] = {"e": e, "list": []}
		groups[gk].list.append(int(e.along))
	var keys := groups.keys()
	keys.sort()
	for gk in keys:
		var g: Dictionary = groups[gk]
		var e: Dictionary = g.e
		var list: Array = g.list
		list.sort()
		var start: int = list[0]
		var prev: int = list[0]
		for i in range(1, list.size() + 1):
			if i < list.size() and list[i] == prev + 1:
				prev = list[i]
				continue
			var len_t := prev - start + 1
			var h := float(e.y1) - float(e.y0)
			var cy := (float(e.y0) + float(e.y1)) * 0.5
			var along_c := (start + len_t * 0.5) * ts
			var size: Vector3
			var center: Vector3
			if e.x_axis:
				size = Vector3(WALL_T, h, len_t * ts + WALL_T)
				center = Vector3(int(e.line) * ts, cy, along_c)
			else:
				size = Vector3(len_t * ts + WALL_T, h, WALL_T)
				center = Vector3(along_c, cy, int(e.line) * ts)
			MeshKit.add_collider(_world_body, size, center)
			if len_t >= 3:
				_add_occluder(size, center)
			if i < list.size():
				start = list[i]
				prev = list[i]


func _add_occluder(size: Vector3, center: Vector3) -> void:
	var occ := OccluderInstance3D.new()
	var box := BoxOccluder3D.new()
	box.size = size * Vector3(0.9, 0.95, 0.9)
	occ.occluder = box
	occ.position = center
	runtime.add_child(occ)
	runtime.occluders.append(occ)


# --- doors & openings -----------------------------------------------------------------

func _build_doors() -> void:
	for d: Dictionary in layout.doors:
		var room_a: Dictionary = layout.room_by_id[d.room_a]
		var room_b: Dictionary = layout.room_by_id[d.room_b]
		var dir: Vector2i = d.b - d.a
		var along_x := dir.y != 0
		var ep := _edge_endpoints(d.a, dir)
		var mid := (ep[0] + ep[1]) * 0.5
		var fy := maxf(floor_at(room_a, mid.x, mid.y), floor_at(room_b, mid.x, mid.y))
		var center := Vector3(mid.x * ts, fy, mid.y * ts)
		var h := minf(layout.level_height(room_a.level), layout.level_height(room_b.level))
		var top := OPEN_TOP if d.type == "open" else DOOR_TOP
		var span := Vector3(ts + WALL_T, 0, WALL_T) if along_x else Vector3(WALL_T, 0, ts + WALL_T)
		# lintel (visual on both sides + collision)
		var lintel_h := h - top
		if lintel_h > 0.05:
			var lsize := span + Vector3(0, lintel_h, 0)
			var lc := center + Vector3(0, top + lintel_h * 0.5, 0)
			MeshKit.st_box(_room_st[room_a.id].wall, lc, lsize)
			MeshKit.add_collider(_world_body, lsize, lc)
		if d.type == "open":
			continue
		# side stubs (door opening is narrower than a tile)
		var stub := (ts - Door.PANEL_W * 2.0) * 0.5
		for s in [-1.0, 1.0]:
			var off := Vector3(s * (ts * 0.5 - stub * 0.5), 0, 0) if along_x else Vector3(0, 0, s * (ts * 0.5 - stub * 0.5))
			var ssize := (Vector3(stub, top, WALL_T) if along_x else Vector3(WALL_T, top, stub))
			var sc := center + off + Vector3(0, top * 0.5, 0)
			MeshKit.st_box(_room_st[room_a.id].wall, sc, ssize)
			MeshKit.add_collider(_world_body, ssize, sc)
		var door := Door.new()
		door.name = "Door_%s" % d.id
		door.position = center
		runtime.add_child(door)
		door.setup(d, along_x, room_a.power_zone if room_a.power_zone != &"exterior" else room_b.power_zone)
		door.room_id = d.room_a
		interactions.register_static(door)
		runtime.doors[d.id] = door


# --- features -------------------------------------------------------------------------

static func face_yaw(face: String) -> float:
	match face:
		"n": return PI
		"e": return PI * 0.5
		"w": return -PI * 0.5
	return 0.0


func _build_features(room: Dictionary) -> void:
	var node := room_node(room)
	for f: Dictionary in room.features:
		var p: Array = f.pos
		var pos := world(room, float(p[0]), float(p[1]))
		var yaw := face_yaw(str(f.get("face", "s")))
		match str(f.type):
			"spawn_player":
				runtime.spawn_points.append(pos + Vector3.UP * 0.1)
			"enemy_spawn":
				runtime.enemy_spawns.append(pos + Vector3.UP * 0.1)
			"prop":
				props.place(room, str(f.kind), pos, yaw)
			"interactable":
				var kind := str(f.kind)
				if kind == "elevator_panel":
					var ep := ElevatorPanel.new()
					ep.name = "Elevator_%s" % room.id
					ep.position = pos
					ep.rotation.y = yaw
					node.add_child(ep)
					ep.setup(StringName(str(f.get("tag", "elevator"))), AABB(), room.power_zone)
					ep.room_id = room.id
					interactions.register_static(ep)
					runtime.elevators.append(ep)
					_elevator_panels[room.id] = ep
				else:
					var dev := ObjectiveDevice.new()
					dev.name = "Device_%s_%d" % [kind, runtime.devices.size()]
					dev.position = pos
					dev.rotation.y = yaw
					node.add_child(dev)
					dev.setup(kind, StringName(str(f.get("tag", kind))))
					dev.room_id = room.id
					dev.power_zone = room.power_zone
					interactions.register_static(dev)
					runtime.devices.append(dev)


func _link_elevators() -> void:
	for room in layout.rooms:
		if not room.has("elevator"):
			continue
		var link_id := StringName(str(room.elevator.get("link", "")))
		var top: ElevatorPanel = _elevator_panels.get(room.id)
		var bottom: ElevatorPanel = _elevator_panels.get(link_id)
		if top == null or bottom == null:
			Log.e("facility", "elevator in %s missing panels" % room.id)
			continue
		var car: Array = room.elevator.car
		var bottom_room: Dictionary = layout.room_by_id[link_id]
		var p0 := Vector3(float(car[0]) * ts, layout.level_y(room.level), float(car[1]) * ts)
		var size := Vector3(float(car[2]) * ts, 3.0, float(car[3]) * ts)
		top.car_aabb = AABB(p0, size)
		bottom.car_aabb = AABB(Vector3(p0.x, layout.level_y(bottom_room.level), p0.z), size)
		top.link = bottom
		bottom.link = top
		props.elevator_car(room, top.car_aabb)
		props.elevator_car(bottom_room, bottom.car_aabb)


# --- lights ---------------------------------------------------------------------------

func _build_lights(room: Dictionary) -> void:
	var r: Rect2i = room.rect
	var node := room_node(room)
	var w := r.size.x * ts
	var dd := r.size.y * ts
	var color: Color = LIGHT_COLORS.get(room.kind, Color(0.95, 0.93, 0.88))
	var h := layout.level_height(room.level)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(room.id) + "_lights")
	if room.outdoor:
		var lamp_pos := world(room, r.position.x + 0.7, r.position.y + 0.7)
		props.place(room, "lamp_post", lamp_pos, 0.0)
		var l := OmniLight3D.new()
		l.light_color = color
		l.light_energy = 1.4
		l.omni_range = 16.0
		l.position = lamp_pos + Vector3(0.6, 4.6, 0.6)
		node.add_child(l)
		runtime.lights.append({"light": l, "fixture": null, "zone": &"exterior", "room": room.id, "emergency": false, "flicker": rng.randf() < 0.5, "base_energy": l.light_energy})
		return
	var nx := maxi(1, roundi(w / 7.0))
	var nz := maxi(1, roundi(dd / 7.0))
	var fixtures: Array[Vector3] = []
	for ix in nx:
		for iz in nz:
			var tx := r.position.x + (ix + 0.5) * r.size.x / float(nx)
			var tz := r.position.y + (iz + 0.5) * r.size.y / float(nz)
			fixtures.append(world(room, tx, tz) + Vector3.UP * (h - 0.06))
	var max_lights := clampi(int(w * dd / 45.0), 1, 3)
	var step := maxi(1, fixtures.size() / max_lights)
	for i in fixtures.size():
		var fpos := fixtures[i]
		var fixture: Variant = _fixture(room, node, "light_fixture", fpos + Vector3.UP * 0.06, Vector3(1.4, 0.07, 0.35), "emissive_white")
		var light: OmniLight3D = null
		if i % step == 0 and i / step < max_lights:
			light = OmniLight3D.new()
			light.light_color = color
			light.light_energy = 1.25
			light.omni_range = clampf(maxf(w, dd) * 0.75, 7.0, 13.0)
			light.omni_attenuation = 1.1
			light.light_specular = 0.4
			light.position = fpos - Vector3.UP * 0.3
			light.distance_fade_enabled = true
			light.distance_fade_begin = 28.0
			light.distance_fade_length = 6.0
			node.add_child(light)
		runtime.lights.append({"light": light, "fixture": fixture, "zone": room.power_zone, "room": room.id,
			"emergency": false, "flicker": rng.randf() < 0.18, "base_energy": 1.25})
	# emergency light: red, dim, active when the zone is unpowered
	var slots: Array = _wall_slots[room.id]
	var epos := world(room, r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5) + Vector3.UP * (h - 0.5)
	if not slots.is_empty():
		var s: Dictionary = slots[rng.randi_range(0, slots.size() - 1)]
		var t: Vector2i = s.tile
		var d: Vector2i = s.dir
		epos = world(room, t.x + 0.5 + d.x * 0.42, t.y + 0.5 + d.y * 0.42) + Vector3.UP * (h - 0.45)
	var ebox: Variant = _fixture(room, node, "emergency_light", epos, Vector3(0.3, 0.15, 0.3), "emissive_red")
	var el := OmniLight3D.new()
	el.light_color = Color(1.0, 0.12, 0.06)
	el.light_energy = 0.9
	el.omni_range = clampf(maxf(w, dd) * 0.6, 6.0, 11.0)
	el.omni_attenuation = 1.4
	el.light_specular = 0.2
	el.position = epos - Vector3.UP * 0.2
	node.add_child(el)
	runtime.lights.append({"light": el, "fixture": ebox, "zone": room.power_zone, "room": room.id,
		"emergency": true, "flicker": false, "base_energy": 0.9})


## Light fixture: batched model when available. Returns the fallback MeshInstance3D or a
## "kind/Tube" key that _flush_room() resolves to the room's batched emissive tube mesh.
func _fixture(room: Dictionary, parent: Node3D, kind: String, pos: Vector3, fallback_size: Vector3, mat: String) -> Variant:
	var batch := props.batch_for(room)
	if not batch.has_model(kind, "environment"):
		var box := MeshKit.add_box(parent, fallback_size, mat, pos)
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return box
	batch.add(kind, "environment", Transform3D(Basis(), pos))
	return "%s/Tube" % kind


## Emits the room's batched geometry and resolves fixture references for the power grid.
func _flush_room(room: Dictionary) -> void:
	var dist := float(Settings.preset().draw_distance) * 0.75
	var made := props.batch_for(room).flush(room_node(room), maxf(dist, 30.0), true, "Room_%s" % room.id)
	for mmi in made.values():
		var key := String((mmi as Node).name)
		if key.contains("light_fixture") or key.contains("emergency_light") or key.contains("pipe_run") or key.contains("cable_tray") or key.contains("wall_vent"):
			(mmi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for l: Dictionary in runtime.lights:
		if l.room == room.id and l.fixture is String:
			l.fixture = made.get(l.fixture)


const DETAIL_KINDS := {
	"corridor": ["pipe_run", "cable_tray"], "tunnel": ["pipe_run", "pipe_run"], "maintenance": ["pipe_run", "cable_tray"],
	"generator": ["pipe_run"], "pump": ["pipe_run", "pipe_run"], "server": ["cable_tray"], "hall": ["pipe_run"],
	"storage": ["cable_tray"], "lab": ["cable_tray"], "containment": ["pipe_run"], "control": ["cable_tray"],
	"freezer": ["pipe_run", "pipe_run"],
}


## Architectural dressing that makes rooms read as a real facility: ceiling pipe runs and
## cable trays along the long axis, wall vents high on walls. Visual only (no collision),
## deterministic per room.
func _detail_room(room: Dictionary) -> void:
	if room.outdoor or room.has("ramp"):
		return
	var r: Rect2i = room.rect
	var node := room_node(room)
	var h := layout.level_height(room.level)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(room.id) + "_detail")
	var kinds: Array = DETAIL_KINDS.get(room.kind, [])
	var along_x := r.size.x >= r.size.y
	var batch := props.batch_for(room)
	for k in kinds.size():
		if not batch.has_model(kinds[k], "environment"):
			continue
		# offset each run toward a different side of the room
		var lane := (0.25 if k == 0 else 0.75)
		var length := (r.size.x if along_x else r.size.y)
		for i in length:
			var tx := (r.position.x + i + 0.5) if along_x else (r.position.x + r.size.x * lane)
			var tz := (r.position.y + r.size.y * lane) if along_x else (r.position.y + i + 0.5)
			var p := world(room, tx, tz) + Vector3.UP * (h - (0.55 if kinds[k] == "pipe_run" else 0.35))
			batch.add(kinds[k], "environment", Transform3D(Basis(Vector3.UP, 0.0 if along_x else PI * 0.5), p))
	if batch.has_model("wall_vent", "environment"):
		var slots: Array = _wall_slots[room.id]
		for n in mini(2, slots.size() / 6 + 1):
			if slots.is_empty():
				break
			var s: Dictionary = slots[rng.randi_range(0, slots.size() - 1)]
			var t: Vector2i = s.tile
			var d: Vector2i = s.dir
			var vp := world(room, t.x + 0.5 + d.x * 0.47, t.y + 0.5 + d.y * 0.47) + Vector3.UP * (h - 0.8)
			batch.add("wall_vent", "environment", Transform3D(Basis(Vector3.UP, atan2(float(-d.x), float(-d.y))), vp))


# --- finalise -------------------------------------------------------------------------

func _commit_room_mesh(room: Dictionary) -> void:
	var st: Dictionary = _room_st[room.id]
	var mesh := ArrayMesh.new()
	var mats := [st.floor_mat, st.wall_mat, "ceiling"]
	var tools: Array = [st.floor, st.wall, st.ceiling]
	for i in 3:
		var tool: SurfaceTool = tools[i]
		var arrays := tool.commit_to_arrays()
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		tool.generate_tangents()
		var before := mesh.get_surface_count()
		tool.commit(mesh)
		if mesh.get_surface_count() > before:
			mesh.surface_set_material(mesh.get_surface_count() - 1, MaterialLibrary.get_mat(mats[i]))
	var mi := MeshInstance3D.new()
	mi.name = "Shell"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	room_node(room).add_child(mi)


func _build_patrol_routes() -> void:
	for route: Dictionary in layout.patrol_routes:
		var pts := PackedVector3Array()
		for p: Array in route.points:
			var lvl := int(p[2]) if p.size() > 2 else int(route.get("level", 0))
			var tile := Vector2i(floori(float(p[0])), floori(float(p[1])))
			var rid := layout.room_at(lvl, tile)
			if rid == &"":
				continue
			pts.append(world(layout.room_by_id[rid], float(p[0]), float(p[1])))
		runtime.patrol_routes.append({"id": StringName(str(route.id)), "points": pts})
