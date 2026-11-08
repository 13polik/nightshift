class_name ItemPickup
extends Interactable
## A world item that can be picked up. Spawned/removed only by the server (PickupManager);
## the visual comes from ItemData.world_model or a procedural development model.

var item_id: StringName
var count: int = 1
var _visual: Node3D
var _t := 0.0


func setup(p_item: StringName, p_count: int) -> void:
	item_id = p_item
	count = p_count
	tag = &"pickup"
	interact_range = 2.2
	focus_height = 0.25
	var data := Content.item(item_id)
	if data and data.world_model:
		_visual = data.world_model.instantiate()
		add_child(_visual)
	else:
		_visual = ItemVisuals.build(data)
		add_child(_visual)
	_t = float(hash(item_id) % 100) * 0.1


func get_prompt(_player: Node) -> String:
	var data := Content.item(item_id)
	var item_name := tr(data.name_key) if data else String(item_id)
	var reason := can_interact(_player)
	if not reason.is_empty():
		return "%s - %s" % [item_name, tr(reason)]
	return tr("PROMPT_PICK_UP").format({"item": item_name + (" x%d" % count if count > 1 else "")})


func can_interact(player: Node) -> String:
	var inv: Variant = player.get("inventory") if player else null
	if inv == null:
		return "REASON_UNAVAILABLE"
	if not inv.can_add(item_id, 1):
		return "REASON_INVENTORY_FULL"
	return ""


func server_interact(player: Node) -> void:
	var added: int = player.inventory.server_add(item_id, count)
	count -= added
	super.server_interact(player)
	if count <= 0:
		service.mission.pickups.server_remove(net_id)
	else:
		mark_dirty()


func get_state() -> Dictionary:
	var s := super.get_state()
	s.c = count
	return s


func apply_state(s: Dictionary) -> void:
	count = int(s.get("c", count))
	super.apply_state(s)


func _process(delta: float) -> void:
	_t += delta
	if _visual:
		_visual.position.y = 0.08 + sin(_t * 2.2) * 0.04
		_visual.rotation.y += delta * 0.8
