class_name PickupManager
extends Node3D
## Server-authoritative world items. Spawns/removals are broadcast with server-assigned
## ids so every peer agrees on which pickup is which.

var mission: Node # MissionController


func server_spawn(item: StringName, count: int, pos: Vector3) -> int:
	if not multiplayer.is_server() or Content.item(item) == null or count <= 0:
		return -1
	var id: int = mission.interactions._next_dynamic_id
	mission.interactions._next_dynamic_id += 1
	_rpc_spawn.rpc(id, String(item), count, _ground(pos))
	return id


func server_remove(id: int) -> void:
	if multiplayer.is_server():
		_rpc_remove.rpc(id)


func snapshot() -> Array:
	var out: Array = []
	for c in get_children():
		if c is ItemPickup and c.visible and c.net_id >= 0:
			out.append([c.net_id, String(c.item_id), c.count, c.global_position])
	return out


func apply_snapshot(list: Array) -> void:
	for e: Array in list:
		_spawn_local(int(e[0]), StringName(e[1]), int(e[2]), e[3])


func _ground(pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 3.0, 1)
	var hit := space.intersect_ray(q)
	return (hit.position as Vector3) + Vector3.UP * 0.08 if not hit.is_empty() else pos


@rpc("authority", "call_local", "reliable")
func _rpc_spawn(id: int, item: String, count: int, pos: Vector3) -> void:
	_spawn_local(id, StringName(item), count, pos)


func _spawn_local(id: int, item: StringName, count: int, pos: Vector3) -> void:
	if mission.interactions.get_interactable(id):
		return
	var p := ItemPickup.new()
	p.name = "Pickup_%d" % id
	add_child(p)
	p.global_position = pos
	p.setup(item, count)
	mission.interactions.register_dynamic(p, id)


@rpc("authority", "call_local", "reliable")
func _rpc_remove(id: int) -> void:
	var i: Interactable = mission.interactions.get_interactable(id)
	if i:
		mission.interactions.registry.erase(id)
		Audio.play_3d("pickup", i.global_position, -4.0, 8.0)
		i.queue_free()
