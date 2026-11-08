class_name FacilityLayout
extends RefCounted
## Parsed, validated facility layout (authored as JSON in data/facilities/).
## Rooms are tile rectangles per level; walls are derived automatically from room
## boundaries, doors/openings are explicit tile-edge pairs.

var id: String = ""
var name_key: String = ""
var tile_size: float = 2.0
var levels: Dictionary = {}       # int -> {y, height}
var rooms: Array[Dictionary] = []
var room_by_id: Dictionary = {}
var grid: Dictionary = {}         # int level -> {Vector2i: room_id}
var doors: Array[Dictionary] = []
var door_lookup: Dictionary = {}  # "L|ax,az|bx,bz" -> door index
var patrol_routes: Array[Dictionary] = []
var route_locks: Dictionary = {}
## Localisation keys of the readable notes placed in this facility (empty = default set).
var notes: PackedStringArray = PackedStringArray()
var errors: PackedStringArray = PackedStringArray()


static func load_json(path: String) -> FacilityLayout:
	var l := FacilityLayout.new()
	if not FileAccess.file_exists(path):
		l.errors.append("layout not found: %s" % path)
		return l
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		l.errors.append("layout is not valid JSON: %s" % path)
		return l
	l._parse(parsed)
	return l


func _parse(d: Dictionary) -> void:
	id = str(d.get("id", ""))
	name_key = str(d.get("name_key", ""))
	tile_size = float(d.get("tile_size", 2.0))
	var lv: Dictionary = d.get("levels", {})
	for k in lv:
		levels[int(k)] = {"y": float(lv[k].get("y", 0.0)), "height": float(lv[k].get("height", 4.0))}
	for raw: Dictionary in d.get("rooms", []):
		var r := raw.duplicate(true)
		r.id = StringName(str(r.get("id", "")))
		r.level = int(r.get("level", 0))
		var rect: Array = r.get("rect", [0, 0, 1, 1])
		r.rect = Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))
		r.tags = PackedStringArray(r.get("tags", []))
		r.loot_tags = PackedStringArray(r.get("loot_tags", []))
		r.features = r.get("features", [])
		r.kind = str(r.get("kind", "room"))
		r.outdoor = bool(r.get("outdoor", false))
		r.power_zone = StringName(str(r.get("power_zone", "main")))
		if not levels.has(r.level):
			errors.append("room %s uses unknown level %d" % [r.id, r.level])
			levels[r.level] = {"y": r.level * 6.0, "height": 4.0}
		if room_by_id.has(r.id):
			errors.append("duplicate room id %s" % r.id)
		rooms.append(r)
		room_by_id[r.id] = r
		if not grid.has(r.level):
			grid[r.level] = {}
		var g: Dictionary = grid[r.level]
		for x in range(r.rect.position.x, r.rect.end.x):
			for z in range(r.rect.position.y, r.rect.end.y):
				var t := Vector2i(x, z)
				if g.has(t):
					errors.append("rooms %s and %s overlap at %s (level %d)" % [g[t], r.id, t, r.level])
				g[t] = r.id
	var auto_id := 0
	for raw: Dictionary in d.get("doors", []):
		var door := raw.duplicate(true)
		var a: Array = door.get("a", [0, 0])
		var b: Array = door.get("b", [0, 0])
		door.a = Vector2i(int(a[0]), int(a[1]))
		door.b = Vector2i(int(b[0]), int(b[1]))
		door.type = str(door.get("type", "normal"))
		if str(door.get("id", "")).is_empty():
			door.id = "opening_%d" % auto_id
			auto_id += 1
		door.id = StringName(str(door.id))
		if (door.a - door.b).abs().x + (door.a - door.b).abs().y != 1:
			errors.append("door %s tiles %s/%s are not adjacent" % [door.id, door.a, door.b])
			continue
		var la: Variant = _level_of_tile(door.a, door.get("level", null))
		var lb: Variant = _level_of_tile(door.b, la)
		if la == null or lb == null:
			errors.append("door %s is not between two floor tiles" % door.id)
			continue
		door.level_a = int(la)
		door.level_b = int(lb)
		door.room_a = grid[int(la)][door.a]
		door.room_b = grid[int(lb)][door.b]
		var idx := doors.size()
		doors.append(door)
		door_lookup[_edge_key(int(la), door.a, door.b)] = idx
		door_lookup[_edge_key(int(lb), door.b, door.a)] = idx
	for raw: Dictionary in d.get("patrol_routes", []):
		patrol_routes.append(raw)
	route_locks = d.get("route_locks", {})
	notes = PackedStringArray(d.get("notes", []))


## Finds the level containing `tile`, preferring `preferred` (for doors on one level).
func _level_of_tile(tile: Vector2i, preferred: Variant) -> Variant:
	if preferred != null and grid.has(int(preferred)) and grid[int(preferred)].has(tile):
		return int(preferred)
	var keys := grid.keys()
	keys.sort()
	keys.reverse()
	for l in keys:
		if grid[l].has(tile):
			return l
	return null


static func _edge_key(level: int, a: Vector2i, b: Vector2i) -> String:
	return "%d|%d,%d|%d,%d" % [level, a.x, a.y, b.x, b.y]


func door_on_edge(level: int, a: Vector2i, b: Vector2i) -> Dictionary:
	var idx: int = door_lookup.get(_edge_key(level, a, b), -1)
	return doors[idx] if idx >= 0 else {}


func room_at(level: int, tile: Vector2i) -> StringName:
	return grid.get(level, {}).get(tile, &"")


func level_y(level: int) -> float:
	return float(levels.get(level, {"y": 0.0}).y)


func level_height(level: int) -> float:
	return float(levels.get(level, {"height": 4.0}).height)


## Floor height at continuous tile coordinates inside `room` (handles ramps).
func floor_y(room: Dictionary, tx: float, tz: float) -> float:
	var base := level_y(room.level)
	if not room.has("ramp"):
		return base
	var ramp: Dictionary = room.ramp
	var along := tz if str(ramp.get("axis", "z")) == "z" else tx
	var from := float(ramp.from)
	var to := float(ramp.to) + 1.0
	if along <= from:
		return float(ramp.y_from)
	if along >= to:
		return float(ramp.y_to)
	return lerpf(float(ramp.y_from), float(ramp.y_to), (along - from) / (to - from))


func tile_to_world(tx: float, tz: float, y: float) -> Vector3:
	return Vector3(tx * tile_size, y, tz * tile_size)


func tile_center(tile: Vector2i, room: Dictionary) -> Vector3:
	var cx := tile.x + 0.5
	var cz := tile.y + 0.5
	return tile_to_world(cx, cz, floor_y(room, cx, cz))


func room_aabb(room: Dictionary) -> AABB:
	var r: Rect2i = room.rect
	var y0 := level_y(room.level)
	var h := level_height(room.level)
	if room.has("ramp"):
		var y_min := minf(float(room.ramp.y_from), float(room.ramp.y_to))
		var y_max := maxf(float(room.ramp.y_from), float(room.ramp.y_to)) + h
		return AABB(Vector3(r.position.x * tile_size, y_min, r.position.y * tile_size),
			Vector3(r.size.x * tile_size, y_max - y_min, r.size.y * tile_size))
	return AABB(Vector3(r.position.x * tile_size, y0, r.position.y * tile_size),
		Vector3(r.size.x * tile_size, h, r.size.y * tile_size))


func rooms_with_tag(tag: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in rooms:
		if tag in r.tags:
			out.append(r)
	return out


## Room adjacency graph through doors/openings (plus elevator links).
func adjacency() -> Dictionary:
	var adj: Dictionary = {}
	for r in rooms:
		adj[r.id] = []
	for d in doors:
		if not d.room_b in adj[d.room_a]:
			adj[d.room_a].append(d.room_b)
		if not d.room_a in adj[d.room_b]:
			adj[d.room_b].append(d.room_a)
	for r in rooms:
		if r.has("elevator"):
			var link := StringName(str(r.elevator.get("link", "")))
			if room_by_id.has(link):
				adj[r.id].append(link)
				adj[link].append(r.id)
	return adj


func reachable_from(start: StringName) -> Dictionary:
	var adj := adjacency()
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var cur: StringName = queue.pop_front()
		for n in adj.get(cur, []):
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


func validate() -> PackedStringArray:
	var out := errors.duplicate()
	if rooms.is_empty():
		out.append("layout has no rooms")
		return out
	var start: StringName = rooms_with_tag("insertion")[0].id if not rooms_with_tag("insertion").is_empty() else rooms[0].id
	var seen := reachable_from(start)
	for r in rooms:
		if not seen.has(r.id):
			out.append("room %s is unreachable from %s" % [r.id, start])
	if rooms_with_tag("extraction").is_empty():
		out.append("layout has no extraction room")
	var spawns := 0
	for r in rooms:
		for f: Dictionary in r.features:
			if f.get("type") == "spawn_player":
				spawns += 1
			var p: Array = f.get("pos", [0, 0])
			var t := Vector2i(floori(float(p[0])), floori(float(p[1])))
			if not r.rect.has_point(t):
				out.append("feature %s in room %s lies outside the room (%s)" % [f.get("kind", f.get("type")), r.id, t])
	if spawns < 4:
		out.append("layout needs at least 4 player spawns (has %d)" % spawns)
	for route in patrol_routes:
		for p: Array in route.get("points", []):
			var lvl := int(p[2]) if p.size() > 2 else int(route.get("level", 0))
			var t := Vector2i(floori(float(p[0])), floori(float(p[1])))
			if room_at(lvl, t) == &"":
				out.append("patrol route %s point %s is not on a floor tile (level %d)" % [route.get("id"), t, lvl])
	return out
