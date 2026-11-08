class_name FacilityRuntime
extends Node3D
## The built facility and everything systems need to query about it. Built identically on
## every peer from the layout (no randomness), so static interactable ids match everywhere.

var layout: FacilityLayout
var room_info: Dictionary = {}       # id -> {aabb, tags, level, zone, name_key, kind, outdoor}
var spawn_points: Array[Vector3] = []
var enemy_spawns: Array[Vector3] = []
var doors: Dictionary = {}           # door id -> Door
var devices: Array[ObjectiveDevice] = []
var elevators: Array[ElevatorPanel] = []
var containers: Array[Searchable] = []
var loot_points: Array[Dictionary] = [] # {pos, room, tags}
var lights: Array[Dictionary] = []      # {light, fixture, zone, room, emergency, flicker}
var patrol_routes: Array[Dictionary] = [] # {id, points: PackedVector3Array}
var nav_region: NavigationRegion3D
var occluders: Array[OccluderInstance3D] = []


func room_at_position(pos: Vector3) -> StringName:
	for id: StringName in room_info:
		var aabb: AABB = room_info[id].aabb
		if aabb.grow(0.05).has_point(pos + Vector3.UP * 0.3):
			return id
	return &""


func room_name_key(id: StringName) -> String:
	return str(room_info.get(id, {}).get("name_key", ""))


func rooms_with_tag(tag: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in room_info:
		if String(tag) in room_info[id].tags:
			out.append(id)
	out.sort()
	return out


func devices_with_tag(tag: StringName) -> Array[ObjectiveDevice]:
	var out: Array[ObjectiveDevice] = []
	for d in devices:
		if d.tag == tag:
			out.append(d)
	return out


func zone_of_room(id: StringName) -> StringName:
	return room_info.get(id, {}).get("zone", &"main")


func bake_navigation() -> void:
	if nav_region == null:
		return
	var t := Time.get_ticks_msec()
	nav_region.bake_navigation_mesh(false)
	var polys := nav_region.navigation_mesh.get_polygon_count() if nav_region.navigation_mesh else 0
	Log.i("facility", "navmesh baked: %d polygons in %d ms" % [polys, Time.get_ticks_msec() - t])
