class_name Searchable
extends Interactable
## Searchable container (locker, desk, cabinet, crate). Contents are assigned by the
## server-side LootSpawner and never sent to clients until the container is searched.

var container_kind: String = "locker"
var loot_tags: PackedStringArray = PackedStringArray()
var searched := false
## server only: Array of [item_id, count]
var contents: Array = []
var _lid: Node3D
var drop_offset := Vector3(0, 1.0, 0.5)


func _ready() -> void:
	prompt_key = "PROMPT_SEARCH"
	hold_time = 1.3
	noise_radius = 3.0
	focus_height = 0.9


func can_interact(_player: Node) -> String:
	if searched:
		return "REASON_EMPTY"
	return super.can_interact(_player)


func is_visible_to(_player: Node) -> bool:
	return enabled and not searched


func server_interact(player: Node) -> void:
	searched = true
	var mission: Node = service.mission
	var i := 0
	for entry: Array in contents:
		var pos := global_transform * (drop_offset + Vector3((i % 3 - 1) * 0.25, 0, 0))
		mission.pickups.server_spawn(StringName(entry[0]), int(entry[1]), pos)
		i += 1
	contents.clear()
	mark_dirty()
	super.server_interact(player)


func server_hold_tick(_player: Node, _progress: float) -> void:
	pass


func set_lid(n: Node3D) -> void:
	_lid = n


func get_state() -> Dictionary:
	var s := super.get_state()
	s.sr = searched
	return s


func apply_state(s: Dictionary) -> void:
	var was := searched
	searched = bool(s.get("sr", searched))
	if searched and not was:
		Audio.play_3d("search", global_position + Vector3.UP * 0.8, -4.0, 10.0)
	super.apply_state(s)


func _on_state_applied() -> void:
	if _lid and searched:
		_lid.rotation_degrees.y = -100.0 if container_kind == "locker" else _lid.rotation_degrees.y
		if container_kind != "locker":
			_lid.position.z = 0.25
