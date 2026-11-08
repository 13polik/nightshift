class_name ObjectiveHandlers
extends RefCounted
## Built-in objective handler implementations.


class ReachZone extends ObjectiveHandler:
	var _check := 0.0

	func update(delta: float) -> void:
		_check -= delta
		if _check > 0.0:
			return
		_check = 0.25
		var fac: FacilityRuntime = mission().facility
		var inside := 0
		var active := 0
		for p: PlayerCharacter in mission().get_players():
			if not p.is_active():
				continue
			active += 1
			var room := fac.room_at_position(p.global_position)
			if room in rt.rooms:
				inside += 1
		detail = {"inside": inside, "total": active}
		if (def.require_all_players and inside >= active and active > 0) or (not def.require_all_players and inside > 0):
			complete()


class UseDevices extends ObjectiveHandler:
	var _done: Dictionary = {}

	func _devices() -> Array[ObjectiveDevice]:
		var out: Array[ObjectiveDevice] = []
		for id in rt.targets:
			var d := mission().interactions.get_interactable(int(id)) as ObjectiveDevice
			if d:
				out.append(d)
		return out

	func start() -> void:
		for d in _devices():
			d.work_time = def.duration if def.duration > 0.0 else 1.0
			d.noise_radius = maxf(d.noise_radius, def.work_noise)
			if def.type == ObjectiveData.Type.DELIVER:
				d.configure_delivery(rt.items, def.duration)
			d.set_objective_active(true)
		if _devices().is_empty():
			Log.e("mission", "objective %s has no target devices (tag %s)" % [def.id, def.target_tag])
			complete()

	func stop() -> void:
		for d in _devices():
			if not d.done:
				d.set_objective_active(false)

	func on_interaction(_peer: int, i: Interactable) -> void:
		if not i is ObjectiveDevice or not int(i.net_id) in rt.targets:
			return
		var d := i as ObjectiveDevice
		if d.done:
			_done[d.net_id] = true
			if def.grants_item != &"":
				mission().pickups.server_spawn(def.grants_item, 1, d.global_transform * Vector3(0, 0.3, 0.9))
		detail = {"done": _done.size(), "total": rt.targets.size()}
		if _done.size() >= rt.targets.size():
			complete()

	func progress() -> float:
		if completed:
			return 1.0
		var total := float(maxi(1, rt.targets.size()))
		var p := float(_done.size()) / total
		# delivery progress inside a single device
		for d in _devices():
			if not d.done and not d.required_items.is_empty():
				var need := 0
				var have := 0
				for k: String in d.required_items:
					need += int(d.required_items[k])
					have += int(d.delivered.get(k, 0))
				p += float(have) / float(maxi(1, need)) * 0.5 / total
		return clampf(p, 0.0, 1.0)


class Collect extends ObjectiveHandler:
	var _check := 0.0
	var _have: Dictionary = {}

	func start() -> void:
		var hint_rooms: Array = []
		if def.reveal_item_location:
			for c: Searchable in mission().facility.containers:
				for e: Array in c.contents:
					if rt.items.has(str(e[0])) and not c.room_id in hint_rooms:
						hint_rooms.append(c.room_id)
		detail = {"have": {}, "need": rt.items, "hint_rooms": hint_rooms}

	func update(delta: float) -> void:
		_check -= delta
		if _check > 0.0:
			return
		_check = 0.3
		var have := {}
		for item: String in rt.items:
			var n := 0
			for p: PlayerCharacter in mission().get_players():
				if p.is_active() or p.is_extracted():
					n += p.inventory.count(StringName(item))
			have[item] = n
		_have = have
		detail.have = have
		var ok := true
		for item: String in rt.items:
			if int(have.get(item, 0)) < int(rt.items[item]):
				ok = false
		if ok:
			complete()

	func progress() -> float:
		if completed:
			return 1.0
		var need := 0
		var got := 0
		for item: String in rt.items:
			need += int(rt.items[item])
			got += mini(int(_have.get(item, 0)), int(rt.items[item]))
		return float(got) / float(maxi(1, need))


class Survive extends ObjectiveHandler:
	func update(delta: float) -> void:
		elapsed += delta
		detail = {"left": maxf(0.0, def.duration - elapsed)}
		if elapsed >= def.duration:
			complete()

	func progress() -> float:
		return clampf(elapsed / maxf(def.duration, 0.1), 0.0, 1.0)


class Extract extends ObjectiveHandler:
	var _check := 0.0
	var room: StringName

	func start() -> void:
		room = mission().setup.extraction_room
		mission().state.set_flag(&"extraction_open", true)
		mission().state.set_flag(&"extraction_room", String(room))
		mission().state.set_flag(&"departure_left", def.duration)

	func update(delta: float) -> void:
		elapsed += delta
		var left := maxf(0.0, def.duration - elapsed)
		_check -= delta
		if _check > 0.0:
			return
		_check = 0.25
		mission().state.set_flag(&"departure_left", snappedf(left, 1.0))
		var fac: FacilityRuntime = mission().facility
		var remaining := 0
		var extracted := 0
		for p: PlayerCharacter in mission().get_players():
			if p.is_extracted():
				extracted += 1
				continue
			if p.can_act() and fac.room_at_position(p.global_position) == room:
				p.health.server_extract()
				extracted += 1
				mission().on_player_extracted(p)
				continue
			if p.is_active():
				remaining += 1
		detail = {"extracted": extracted, "left": left}
		if (remaining == 0 and extracted > 0) or left <= 0.0:
			complete()

	func progress() -> float:
		return clampf(elapsed / maxf(def.duration, 0.1), 0.0, 1.0)
