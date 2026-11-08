class_name PlayerInventory
extends Node
## Server-authoritative slot inventory. Deliberately simple for touch: a few slots with
## stacking, one selected slot, tap to use, long-press to drop. Every change is pushed to
## all peers (teammates see who carries the keycard / sample).

signal changed
signal item_used(item_id: StringName)
signal use_progress_changed(progress: float)

const EMPTY := {"id": "", "n": 0}

var player: Node3D # PlayerCharacter
var slots: Array = []
var selected: int = 0
## channelled use in progress (server-driven, mirrored to clients)
var using_slot: int = -1
var use_progress: float = 0.0
var _use_elapsed := 0.0
var _use_duration := 0.0


func setup(p_player: Node3D, slot_count: int) -> void:
	player = p_player
	slots.clear()
	for i in slot_count:
		slots.append(EMPTY.duplicate())


# --- queries (valid on every peer) ----------------------------------------------------

func count(item: StringName) -> int:
	var n := 0
	for s: Dictionary in slots:
		if StringName(s.id) == item:
			n += int(s.n)
	return n


func has_item(item: StringName) -> bool:
	return count(item) > 0


func can_add(item: StringName, n: int = 1) -> bool:
	var data := Content.item(item)
	if data == null:
		return false
	var room := 0
	for s: Dictionary in slots:
		if str(s.id).is_empty():
			room += data.max_stack
		elif StringName(s.id) == item:
			room += data.max_stack - int(s.n)
	return room >= mini(n, 1)


func slot_item(i: int) -> ItemData:
	if i < 0 or i >= slots.size():
		return null
	var id := str(slots[i].id)
	return Content.item(StringName(id)) if not id.is_empty() else null


func item_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for s: Dictionary in slots:
		if not str(s.id).is_empty():
			out.append(StringName(s.id))
	return out


# --- client requests ------------------------------------------------------------------

func request_use(slot: int) -> void:
	Net.send_to_server(self, &"_srv_use", [slot])


func request_drop(slot: int) -> void:
	Net.send_to_server(self, &"_srv_drop", [slot])


func request_select(slot: int) -> void:
	selected = clampi(slot, 0, slots.size() - 1)
	changed.emit()
	Net.send_to_server(self, &"_srv_select", [slot])


func request_cancel_use() -> void:
	Net.send_to_server(self, &"_srv_cancel_use", [])


# --- server ---------------------------------------------------------------------------

## Adds up to n items. Returns how many were added.
func server_add(item: StringName, n: int) -> int:
	var data := Content.item(item)
	if data == null or n <= 0:
		return 0
	var left := n
	for s: Dictionary in slots:
		if left <= 0:
			break
		if StringName(s.id) == item and int(s.n) < data.max_stack:
			var add := mini(left, data.max_stack - int(s.n))
			s.n = int(s.n) + add
			left -= add
	for s: Dictionary in slots:
		if left <= 0:
			break
		if str(s.id).is_empty():
			var add := mini(left, data.max_stack)
			s.id = String(item)
			s.n = add
			left -= add
	if left < n:
		_broadcast()
	return n - left


func server_remove(item: StringName, n: int) -> int:
	var left := n
	for i in range(slots.size() - 1, -1, -1):
		var s: Dictionary = slots[i]
		if left <= 0:
			break
		if StringName(s.id) == item:
			var take := mini(left, int(s.n))
			s.n = int(s.n) - take
			left -= take
			if int(s.n) <= 0:
				slots[i] = EMPTY.duplicate()
	if left < n:
		_broadcast()
	return n - left


## Drops every item at the player's position (used when a player disconnects or dies).
func server_drop_all() -> void:
	var mission: Node = player.mission
	if mission == null:
		return
	var i := 0
	for s: Dictionary in slots:
		if not str(s.id).is_empty():
			var data := Content.item(StringName(s.id))
			if data and data.droppable:
				var off := Vector3(cos(i * 1.7), 0, sin(i * 1.7)) * 0.5
				mission.pickups.server_spawn(StringName(s.id), int(s.n), player.global_position + off + Vector3.UP * 0.2)
		i += 1
	for k in slots.size():
		slots[k] = EMPTY.duplicate()
	_broadcast()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or using_slot < 0:
		return
	if not player.call("can_act"):
		_cancel_use()
		return
	_use_elapsed += delta
	use_progress = clampf(_use_elapsed / maxf(_use_duration, 0.01), 0.0, 1.0)
	if _use_elapsed >= _use_duration:
		var slot := using_slot
		using_slot = -1
		use_progress = 0.0
		_apply_use(slot)
		_broadcast()
	elif int(_use_elapsed * 10.0) != int((_use_elapsed - delta) * 10.0):
		_broadcast()


func _cancel_use() -> void:
	using_slot = -1
	use_progress = 0.0
	_broadcast()


@rpc("any_peer", "call_remote", "reliable")
func _srv_select(slot: int) -> void:
	if Net.sender_id() != player.peer_id:
		return
	selected = clampi(slot, 0, slots.size() - 1)
	_broadcast()


@rpc("any_peer", "call_remote", "reliable")
func _srv_cancel_use() -> void:
	if Net.sender_id() == player.peer_id and using_slot >= 0:
		_cancel_use()


@rpc("any_peer", "call_remote", "reliable")
func _srv_use(slot: int) -> void:
	if Net.sender_id() != player.peer_id or not player.call("can_act") or using_slot >= 0:
		return
	var data := slot_item(slot)
	if data == null or not data.is_usable():
		return
	var reason := _use_block_reason(data)
	if not reason.is_empty():
		player.call("server_notify", reason)
		return
	if data.use_time > 0.0:
		using_slot = slot
		_use_elapsed = 0.0
		_use_duration = data.use_time
		_broadcast()
	else:
		_apply_use(slot)


func _use_block_reason(data: ItemData) -> String:
	match data.use_effect:
		ItemData.UseEffect.HEAL:
			if player.health.health >= player.health.max_health - 0.5:
				return "REASON_FULL_HEALTH"
		ItemData.UseEffect.RECHARGE_BATTERY:
			if player.flashlight.battery >= player.flashlight.battery_max - 0.5:
				return "REASON_BATTERY_FULL"
		ItemData.UseEffect.STUN_PULSE:
			if data.requires_ammo != &"" and not has_item(data.requires_ammo):
				return "REASON_NO_AMMO"
	return ""


func _apply_use(slot: int) -> void:
	var data := slot_item(slot)
	if data == null:
		return
	match data.use_effect:
		ItemData.UseEffect.HEAL:
			player.health.server_heal(data.effect_amount)
		ItemData.UseEffect.RECHARGE_BATTERY:
			player.flashlight.server_recharge()
		ItemData.UseEffect.STUN_PULSE:
			if data.requires_ammo != &"":
				server_remove(data.requires_ammo, 1)
			player.mission.server_stun_pulse(player, data.effect_amount)
	if data.consumed_on_use:
		var s: Dictionary = slots[slot]
		s.n = int(s.n) - 1
		if int(s.n) <= 0:
			slots[slot] = EMPTY.duplicate()
	_rpc_used.rpc(String(data.id))
	_broadcast()


@rpc("any_peer", "call_remote", "reliable")
func _srv_drop(slot: int) -> void:
	if Net.sender_id() != player.peer_id or not player.call("can_act"):
		return
	var data := slot_item(slot)
	if data == null or not data.droppable:
		return
	var s: Dictionary = slots[slot]
	var fwd: Vector3 = -player.global_basis.z
	player.mission.pickups.server_spawn(data.id, int(s.n), player.global_position + fwd * 0.8 + Vector3.UP * 0.2)
	slots[slot] = EMPTY.duplicate()
	_broadcast()


func _broadcast() -> void:
	if multiplayer.is_server():
		_rpc_sync.rpc(slots, selected, using_slot, use_progress)


@rpc("authority", "call_local", "reliable")
func _rpc_sync(p_slots: Array, p_selected: int, p_using: int, p_progress: float) -> void:
	slots = p_slots
	if not player.is_local or multiplayer.is_server():
		selected = p_selected
	using_slot = p_using
	use_progress = p_progress
	use_progress_changed.emit(p_progress)
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_used(item: String) -> void:
	var data := Content.item(StringName(item))
	if data == null:
		return
	match data.use_effect:
		ItemData.UseEffect.HEAL:
			Audio.play_3d("heal", player.global_position + Vector3.UP, -2.0, 10.0)
		ItemData.UseEffect.STUN_PULSE:
			Audio.play_3d("stun", player.global_position + Vector3.UP, 2.0, 30.0)
		_:
			Audio.play_3d("pickup", player.global_position + Vector3.UP, -6.0, 8.0)
	item_used.emit(StringName(item))
