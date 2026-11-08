class_name ObjectiveDevice
extends Interactable
## Generic mission machine (terminal, electrical panel, generator, breaker, consoles).
## The MissionDirector activates the chosen devices and configures requirements; the
## device itself only knows how to accept items, run its hold and report completion.
##
## Delivery is cooperative: any player carrying a still-needed item deposits it, so the
## team can split components across inventories. Once everything is delivered the final
## (longer) hold completes the device.

const KIND_PROMPTS := {
	"terminal": "PROMPT_USE_TERMINAL",
	"electrical_panel": "PROMPT_REPAIR_PANEL",
	"generator": "PROMPT_START_GENERATOR",
	"breaker": "PROMPT_RESTORE_POWER",
	"containment_console": "PROMPT_EXTRACT_SAMPLE",
	"evac_console": "PROMPT_CALL_EVAC",
	"alarm_panel": "PROMPT_DISABLE_ALARM",
}

signal items_delivered(peer_id: int, items: Dictionary)

var kind: String = "terminal"
var done := false
var always_usable := false
var requires_power := false
var power_zone: StringName = &"main"
## item id (String) -> count still required (server sets via configure_delivery)
var required_items: Dictionary = {}
var delivered: Dictionary = {}
var work_time := 3.0
var visual: DeviceVisual
## Extra condition provided by systems (e.g. alarm panel only while the alarm is on).
var condition: Callable


func setup(p_kind: String, p_tag: StringName) -> void:
	kind = p_kind
	tag = p_tag
	prompt_key = KIND_PROMPTS.get(kind, "PROMPT_INTERACT")
	interact_range = 2.4
	focus_height = 1.1
	match kind:
		"generator":
			focus_height = 1.0
			interact_range = 3.2
			noise_radius = 16.0
		"electrical_panel":
			noise_radius = 9.0
		"terminal":
			noise_radius = 3.0
			requires_power = true
		"containment_console":
			noise_radius = 12.0
			requires_power = true
		"evac_console":
			requires_power = true
		"alarm_panel":
			always_usable = false
	visual = DeviceVisual.new()
	visual.name = "Visual"
	add_child(visual)
	visual.build(kind)


func configure_delivery(items: Dictionary, p_work_time: float) -> void:
	required_items = {}
	for k in items:
		required_items[str(k)] = int(items[k])
	delivered = {}
	work_time = p_work_time
	mark_dirty()


func missing_items() -> Dictionary:
	var out := {}
	for k: String in required_items:
		var left := int(required_items[k]) - int(delivered.get(k, 0))
		if left > 0:
			out[k] = left
	return out


func _player_has_needed(player: Node) -> bool:
	var inv: Variant = player.get("inventory") if player else null
	if inv == null:
		return false
	for k: String in missing_items():
		if inv.has_item(StringName(k)):
			return true
	return false


func is_visible_to(_player: Node) -> bool:
	return enabled and not done and (objective_active or _usable_now())


func _usable_now() -> bool:
	return always_usable and (not condition.is_valid() or bool(condition.call()))


func can_interact(player: Node) -> String:
	if not enabled:
		return "REASON_UNAVAILABLE"
	if done:
		return "REASON_ALREADY_DONE"
	if not objective_active and not _usable_now():
		return "REASON_NOT_NOW"
	if requires_power and service and service.mission and not service.mission.is_powered(power_zone):
		return "REASON_NO_POWER"
	var missing := missing_items()
	if not missing.is_empty() and not _player_has_needed(player):
		return "REASON_NEEDS_ITEMS"
	return ""


func get_hold_time(player: Node) -> float:
	if not missing_items().is_empty():
		return 0.9
	return work_time if work_time > 0.0 else hold_time


func get_prompt(player: Node) -> String:
	var reason := can_interact(player)
	var missing := missing_items()
	if reason == "REASON_NEEDS_ITEMS" or (reason.is_empty() and not missing.is_empty()):
		var parts: PackedStringArray = []
		for k: String in missing:
			var d := Content.item(StringName(k))
			parts.append("%s x%d" % [tr(d.name_key) if d else k, int(missing[k])])
		var lead := tr("PROMPT_INSTALL") if reason.is_empty() else tr("REASON_NEEDS_ITEMS")
		return "%s: %s" % [lead, ", ".join(parts)]
	if not reason.is_empty():
		return tr(reason)
	return tr(prompt_key)


func server_interact(player: Node) -> void:
	var missing := missing_items()
	if not missing.is_empty():
		var given := {}
		for k: String in missing:
			var removed: int = player.inventory.server_remove(StringName(k), int(missing[k]))
			if removed > 0:
				delivered[k] = int(delivered.get(k, 0)) + removed
				given[k] = removed
		mark_dirty()
		items_delivered.emit(int(player.peer_id), given)
		return
	if not always_usable:
		done = true
	mark_dirty()
	super.server_interact(player)


func server_hold_tick(_player: Node, progress: float) -> void:
	if visual:
		visual.set_progress(progress)


func get_state() -> Dictionary:
	var s := super.get_state()
	s.d = done
	s.req = required_items
	s.dl = delivered
	s.wt = work_time
	return s


func apply_state(s: Dictionary) -> void:
	var was_done := done
	done = bool(s.get("d", done))
	required_items = s.get("req", required_items)
	delivered = s.get("dl", delivered)
	work_time = float(s.get("wt", work_time))
	super.apply_state(s)
	if done and not was_done:
		Audio.play_3d("interact_done", focus_point(), 0.0, 20.0)


func _on_state_applied() -> void:
	if visual:
		visual.set_status(done, objective_active or _usable_now(), not missing_items().is_empty())


func refresh_power() -> void:
	if visual:
		visual.set_powered(service == null or service.mission == null or service.mission.is_powered(power_zone))
