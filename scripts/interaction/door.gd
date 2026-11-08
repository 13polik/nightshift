class_name Door
extends Interactable
## Sliding facility door. Types: normal, secure (needs power), heavy (slow, loud).
## Locks: keycard (unlocked once by a keycard holder), lockdown (event; forced with a
## crowbar), jammed. Enemies can open unlocked doors and bash locked ones.

signal opened_changed(open: bool)

const OPEN_SPEED := 2.6
const HEAVY_SPEED := 1.2
const PANEL_W := 0.82
const PANEL_H := 2.6
const OPENING_H := 2.7

var door_id: StringName
var door_type: String = "normal"
var power_zone: StringName = &"main"
var lockdown_capable := false
var is_open := false
var lock_kind: String = ""   # "", keycard, lockdown, jammed
var broken := false
var along_x := true          # panel plane runs along the x axis
var _open_t := 0.0
var _panels: Array[Node3D] = []
var _lamp: MeshInstance3D


func setup(p_door: Dictionary, p_along_x: bool, zone: StringName) -> void:
	door_id = p_door.id
	door_type = str(p_door.type)
	along_x = p_along_x
	power_zone = zone
	lockdown_capable = bool(p_door.get("lockdown", false))
	tag = &"door"
	interact_range = 2.6
	focus_height = 1.3
	noise_radius = 7.0 if door_type == "heavy" else 4.0
	_build_visual()


func _build_visual() -> void:
	var frame_mat := "metal_dark"
	var panel_mat := "metal_yellow" if door_type == "heavy" else ("metal_bright" if door_type == "secure" else "metal_painted")
	var side := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	var depth := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var frame_model := PropFactory.model_for("door_frame", "environment")
	var panel_model := PropFactory.model_for("door_panel", "environment")
	if frame_model and panel_model:
		_build_model_visual(frame_model, panel_model, side, depth, panel_mat)
		return
	# frame posts + header
	for s in [-1.0, 1.0]:
		var post := MeshKit.add_box(self, (side * 0.18 + depth * 0.4 + Vector3(0, OPENING_H, 0)).abs(), frame_mat, side * s * (PANEL_W + 0.09) + Vector3(0, OPENING_H * 0.5, 0))
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var header := MeshKit.add_box(self, (side * (PANEL_W * 2 + 0.36) + depth * 0.4 + Vector3(0, 0.25, 0)).abs(), frame_mat, Vector3(0, OPENING_H + 0.12, 0))
	header.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamp = MeshKit.add_box(self, (side * 0.3 + depth * 0.44 + Vector3(0, 0.07, 0)).abs(), "emissive_amber", Vector3(0, OPENING_H + 0.12, 0))
	for s in [-1.0, 1.0]:
		var body := AnimatableBody3D.new()
		body.sync_to_physics = false
		body.collision_layer = 1 | 32
		body.collision_mask = 0
		body.position = side * s * PANEL_W * 0.5 + Vector3(0, PANEL_H * 0.5, 0)
		add_child(body)
		var size := (side * PANEL_W + depth * 0.12 + Vector3(0, PANEL_H, 0)).abs()
		MeshKit.add_box(body, size, panel_mat, Vector3.ZERO)
		MeshKit.add_box(body, (side * 0.06 + depth * 0.14 + Vector3(0, PANEL_H * 0.8, 0)).abs(), "plastic_dark", side * -s * (PANEL_W * 0.5 - 0.05))
		MeshKit.add_collider(body, size, Vector3.ZERO)
		body.set_meta("side", s)
		_panels.append(body)
	_on_state_applied()


func _build_model_visual(frame_model: PackedScene, panel_model: PackedScene, side: Vector3, depth: Vector3, panel_mat: String) -> void:
	var yaw := 0.0 if along_x else PI * 0.5
	var frame: Node3D = frame_model.instantiate()
	frame.rotation.y = yaw
	add_child(frame)
	MaterialLibrary.apply_named(frame)
	PropFactory.set_draw_distance(frame, 50.0)
	_lamp = MeshKit.add_box(self, (side * 0.26 + depth * 0.46 + Vector3(0, 0.05, 0)).abs(), "emissive_amber", Vector3(0, OPENING_H + 0.12, 0))
	_lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for s in [-1.0, 1.0]:
		var body := AnimatableBody3D.new()
		body.sync_to_physics = false
		body.collision_layer = 1 | 32
		body.collision_mask = 0
		body.position = side * s * PANEL_W * 0.5 + Vector3(0, PANEL_H * 0.5, 0)
		add_child(body)
		var panel: Node3D = panel_model.instantiate()
		panel.rotation.y = yaw
		panel.position = Vector3(0, -PANEL_H * 0.5, 0)
		body.add_child(panel)
		MaterialLibrary.apply_named(panel)
		# door type reads from its paint: heavy = yellow, secure = bright steel
		if panel_mat != "metal_painted":
			for mi in panel.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				for i in m.mesh.get_surface_count():
					var src := m.mesh.surface_get_material(i)
					if src and String(src.resource_name).begins_with("metal_painted"):
						m.set_surface_override_material(i, MaterialLibrary.get_mat(panel_mat))
		PropFactory.set_draw_distance(panel, 50.0)
		MeshKit.add_collider(body, (side * PANEL_W + depth * 0.12 + Vector3(0, PANEL_H, 0)).abs(), Vector3.ZERO)
		body.set_meta("side", s)
		_panels.append(body)
	_on_state_applied()


func _physics_process(delta: float) -> void:
	var target := 1.0 if is_open else 0.0
	if is_equal_approx(_open_t, target):
		return
	var speed := HEAVY_SPEED if door_type == "heavy" else OPEN_SPEED
	_open_t = move_toward(_open_t, target, delta * speed)
	var side := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	for p in _panels:
		var s: float = p.get_meta("side")
		p.position = side * s * (PANEL_W * 0.5 + _open_t * (PANEL_W - 0.05)) + Vector3(0, PANEL_H * 0.5, 0)


func is_powered() -> bool:
	if service == null or service.mission == null:
		return true
	return service.mission.is_powered(power_zone)


func requires_power() -> bool:
	return door_type == "secure" and not broken


func get_hold_time(player: Node) -> float:
	if lock_kind == "lockdown" or lock_kind == "jammed":
		return 4.0
	if lock_kind == "keycard":
		return 0.8
	return 1.0 if door_type == "heavy" else 0.0


func get_prompt(player: Node) -> String:
	var reason := can_interact(player)
	if not reason.is_empty():
		return tr(reason)
	if lock_kind == "keycard":
		return tr("PROMPT_USE_KEYCARD")
	if lock_kind == "lockdown" or lock_kind == "jammed":
		return tr("PROMPT_FORCE_DOOR")
	return tr("PROMPT_CLOSE_DOOR") if is_open else tr("PROMPT_OPEN_DOOR")


func can_interact(player: Node) -> String:
	if not enabled:
		return "REASON_UNAVAILABLE"
	if broken:
		return "" if not is_open else "REASON_DOOR_BROKEN"
	if lock_kind == "keycard":
		return "" if _has_item(player, &"keycard") or _has_item(player, &"access_decoder") else "REASON_NEEDS_KEYCARD"
	if lock_kind == "lockdown" or lock_kind == "jammed":
		return "" if _has_item(player, &"crowbar") else "REASON_LOCKDOWN"
	if requires_power() and not is_powered():
		return "REASON_NO_POWER"
	return ""


func _has_item(player: Node, item: StringName) -> bool:
	var inv: Variant = player.get("inventory") if player else null
	return inv != null and inv.has_item(item)


func server_interact(player: Node) -> void:
	if lock_kind == "keycard":
		# an access decoder bypasses one keycard lock and burns out
		if not _has_item(player, &"keycard") and _has_item(player, &"access_decoder"):
			player.inventory.server_remove(&"access_decoder", 1)
		lock_kind = ""
		set_open(true)
	elif lock_kind == "lockdown" or lock_kind == "jammed":
		lock_kind = ""
		broken = true
		set_open(true)
	else:
		set_open(not is_open)
	super.server_interact(player)


## Server: open/close and replicate.
func set_open(v: bool) -> void:
	if is_open == v:
		return
	is_open = v
	if multiplayer.is_server() and service and service.noise:
		service.noise.emit_noise(global_position + Vector3.UP, noise_radius, &"door", 0)
	mark_dirty()
	opened_changed.emit(v)


func set_lock(kind: String) -> void:
	if broken and kind != "":
		return
	lock_kind = kind
	if kind != "":
		is_open = false
	mark_dirty()


func is_locked() -> bool:
	return lock_kind != "" or (requires_power() and not is_powered())


## Server: enemy opens the door (no requirements apart from not being locked).
func enemy_open() -> bool:
	if is_open:
		return true
	if is_locked():
		return false
	set_open(true)
	return true


## Server: enemy finished bashing a locked door.
func enemy_break() -> void:
	lock_kind = ""
	broken = true
	is_open = false
	set_open(true)


func get_state() -> Dictionary:
	var s := super.get_state()
	s.op = is_open
	s.lk = lock_kind
	s.br = broken
	return s


func apply_state(s: Dictionary) -> void:
	var was_open := is_open
	is_open = bool(s.get("op", is_open))
	lock_kind = str(s.get("lk", lock_kind))
	broken = bool(s.get("br", broken))
	if was_open != is_open:
		Audio.play_3d("door_open" if is_open else "door_close", global_position + Vector3.UP, -2.0, 22.0)
		opened_changed.emit(is_open)
	super.apply_state(s)


func _on_state_applied() -> void:
	if _lamp == null:
		return
	var mat := "emissive_green"
	if lock_kind != "":
		mat = "emissive_red"
	elif requires_power() and not is_powered():
		mat = "emissive_off"
	elif broken:
		mat = "emissive_amber"
	_lamp.material_override = MaterialLibrary.get_mat(mat)


## Called by the power grid when zone power changes so the status lamp updates.
func refresh_power() -> void:
	_on_state_applied()
