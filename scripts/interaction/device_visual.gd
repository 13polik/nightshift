class_name DeviceVisual
extends Node3D
## Development visuals for mission devices with a status lamp and screen. Replace by
## setting a scene in res://scenes/environments/devices/<kind>.tscn whose root extends
## DeviceVisual - the device logic does not change.

var kind := ""
var _lamp: MeshInstance3D
var _screen: MeshInstance3D
var _running: Array[Node3D] = []
var _emitter: AudioStreamPlayer3D
var _sparks: GPUParticles3D
var _done := false
var _powered := true
var _t := 0.0


func build(p_kind: String) -> void:
	kind = p_kind
	var model := PropFactory.model_for("terminal" if kind == "server_terminal" else kind, "props/devices")
	if model:
		var inst: Node3D = model.instantiate()
		add_child(inst)
		MaterialLibrary.apply_named(inst)
		PropFactory.set_draw_distance(inst, 60.0)
		_lamp = inst.find_child("StatusLamp*", true, false) as MeshInstance3D
		_screen = inst.find_child("Screen*", true, false) as MeshInstance3D
		for f in inst.find_children("Fan*", "MeshInstance3D", true, false):
			_running.append(f)
		if kind == "electrical_panel":
			_sparks = _make_sparks(Vector3(0.0, 1.0, 0.15))
		_add_collision()
		return
	match kind:
		"terminal", "server_terminal":
			MeshKit.add_box(self, Vector3(0.9, 1.0, 0.5), "metal_painted", Vector3(0, 0.5, -0.05))
			MeshKit.add_box(self, Vector3(0.95, 0.06, 0.6), "metal_dark", Vector3(0, 1.02, 0))
			_screen = MeshKit.add_box(self, Vector3(0.7, 0.45, 0.04), "screen_off", Vector3(0, 1.35, -0.18), Vector3(-12, 0, 0))
			MeshKit.add_box(self, Vector3(0.6, 0.03, 0.22), "plastic_dark", Vector3(0, 1.06, 0.12), Vector3(8, 0, 0))
			_lamp = MeshKit.add_box(self, Vector3(0.06, 0.06, 0.02), "emissive_red", Vector3(0.38, 0.9, 0.21))
		"electrical_panel":
			MeshKit.add_box(self, Vector3(1.1, 1.6, 0.3), "metal_painted", Vector3(0, 1.2, -0.1))
			var door := MeshKit.add_box(self, Vector3(1.0, 1.5, 0.04), "metal_dark", Vector3(-0.45, 1.2, 0.07), Vector3(0, -70, 0))
			door.position.x = -0.62
			door.position.z = 0.35
			MeshKit.add_box(self, Vector3(0.9, 0.08, 0.05), "hazard", Vector3(0, 1.9, 0.06))
			for i in 4:
				MeshKit.add_box(self, Vector3(0.12, 0.2, 0.06), "plastic_dark", Vector3(-0.3 + i * 0.2, 1.3, 0.06))
			_lamp = MeshKit.add_box(self, Vector3(0.08, 0.08, 0.03), "emissive_red", Vector3(0.4, 1.75, 0.07))
			_sparks = _make_sparks(Vector3(0.0, 1.0, 0.15))
		"generator":
			MeshKit.add_box(self, Vector3(3.4, 1.6, 1.8), "metal_yellow", Vector3(0, 0.8, 0))
			MeshKit.add_box(self, Vector3(3.6, 0.2, 2.0), "metal_dark", Vector3(0, 0.1, 0))
			for i in 3:
				var fan := MeshKit.add_cyl(self, 0.4, 0.12, "metal_dark", Vector3(-1.0 + i * 1.0, 1.66, 0))
				_running.append(fan)
			MeshKit.add_cyl(self, 0.18, 1.6, "metal_dark", Vector3(1.4, 2.4, -0.5))
			_screen = MeshKit.add_box(self, Vector3(0.6, 0.35, 0.04), "screen_off", Vector3(0.9, 1.1, 0.92))
			_lamp = MeshKit.add_box(self, Vector3(0.1, 0.1, 0.03), "emissive_red", Vector3(1.4, 1.2, 0.92))
		"breaker":
			MeshKit.add_box(self, Vector3(0.8, 1.2, 0.25), "metal_dark", Vector3(0, 1.3, -0.08))
			MeshKit.add_box(self, Vector3(0.12, 0.4, 0.12), "hazard", Vector3(0, 1.3, 0.1))
			_lamp = MeshKit.add_box(self, Vector3(0.08, 0.08, 0.03), "emissive_red", Vector3(0.28, 1.75, 0.06))
		"containment_console":
			MeshKit.add_cyl(self, 1.1, 0.25, "metal_dark", Vector3(0, 0.12, -1.6))
			var tube := MeshKit.add_cyl(self, 0.9, 2.6, "glass", Vector3(0, 1.55, -1.6))
			tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			MeshKit.add_cyl(self, 0.75, 1.6, "biohazard_liquid", Vector3(0, 1.1, -1.6))
			MeshKit.add_cyl(self, 1.1, 0.3, "metal_dark", Vector3(0, 2.95, -1.6))
			MeshKit.add_box(self, Vector3(1.2, 1.0, 0.6), "metal_painted", Vector3(0, 0.5, 0))
			_screen = MeshKit.add_box(self, Vector3(0.9, 0.4, 0.04), "screen_off", Vector3(0, 1.2, 0.1), Vector3(-25, 0, 0))
			_lamp = MeshKit.add_box(self, Vector3(0.08, 0.08, 0.03), "emissive_red", Vector3(0.5, 0.85, 0.31))
		"evac_console":
			MeshKit.add_box(self, Vector3(1.2, 1.1, 0.6), "metal_painted", Vector3(0, 0.55, 0))
			MeshKit.add_box(self, Vector3(0.5, 0.06, 0.3), "hazard", Vector3(0.0, 1.12, 0.05))
			MeshKit.add_cyl(self, 0.09, 0.06, "emissive_red", Vector3(0.0, 1.17, 0.05))
			_screen = MeshKit.add_box(self, Vector3(0.9, 0.5, 0.04), "screen_off", Vector3(0, 1.55, -0.25), Vector3(-10, 0, 0))
			_lamp = MeshKit.add_box(self, Vector3(0.08, 0.08, 0.03), "emissive_red", Vector3(0.5, 0.9, 0.31))
		"alarm_panel":
			MeshKit.add_box(self, Vector3(0.6, 0.8, 0.15), "metal_painted", Vector3(0, 1.4, -0.05))
			_lamp = MeshKit.add_cyl(self, 0.1, 0.08, "emissive_off", Vector3(0, 1.6, 0.05), Vector3(90, 0, 0))
			MeshKit.add_box(self, Vector3(0.2, 0.2, 0.06), "emissive_red", Vector3(0, 1.3, 0.04))
		"elevator_panel":
			MeshKit.add_box(self, Vector3(0.35, 0.6, 0.08), "metal_bright", Vector3(0, 1.3, -0.02))
			_lamp = MeshKit.add_box(self, Vector3(0.12, 0.12, 0.03), "emissive_red", Vector3(0, 1.45, 0.03))
			MeshKit.add_box(self, Vector3(0.12, 0.12, 0.03), "plastic_dark", Vector3(0, 1.2, 0.03))
		_:
			MeshKit.add_box(self, Vector3(0.8, 1.2, 0.5), "metal_painted", Vector3(0, 0.6, 0))
	_add_collision()


func _add_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	match kind:
		"generator":
			MeshKit.add_collider(body, Vector3(3.6, 1.8, 2.0), Vector3(0, 0.9, 0))
		"containment_console":
			MeshKit.add_collider(body, Vector3(2.0, 3.0, 2.0), Vector3(0, 1.5, -1.6))
			MeshKit.add_collider(body, Vector3(1.2, 1.0, 0.6), Vector3(0, 0.5, 0))
		"terminal", "server_terminal", "evac_console":
			MeshKit.add_collider(body, Vector3(1.0, 1.1, 0.6), Vector3(0, 0.55, 0))
		"electrical_panel":
			MeshKit.add_collider(body, Vector3(1.1, 1.6, 0.3), Vector3(0, 1.2, -0.1))


func _make_sparks(pos: Vector3) -> GPUParticles3D:
	if not Settings.preset().particles:
		return null
	var p := GPUParticles3D.new()
	p.amount = 12
	p.lifetime = 0.6
	p.explosiveness = 0.8
	p.one_shot = false
	p.position = pos
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 0.3, 1)
	m.spread = 50.0
	m.initial_velocity_min = 1.5
	m.initial_velocity_max = 3.0
	m.gravity = Vector3(0, -9.8, 0)
	m.scale_min = 0.02
	m.scale_max = 0.04
	p.process_material = m
	p.draw_pass_1 = MeshKit.box_mesh(Vector3(0.03, 0.03, 0.03))
	p.material_override = MaterialLibrary.get_mat("emissive_amber")
	p.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	add_child(p)
	return p


func set_status(done: bool, active: bool, needs_items: bool) -> void:
	if done and not _done and is_inside_tree():
		_completion_fx()
	_done = done
	if _lamp:
		var m := "emissive_green" if done else ("emissive_amber" if active and not needs_items else ("emissive_red" if active or kind != "alarm_panel" else "emissive_off"))
		_lamp.material_override = MaterialLibrary.get_mat(m)
	if _screen:
		_screen.material_override = MaterialLibrary.get_mat("screen_on" if (_powered or kind == "generator") and (active or done) else "screen_off")
	if _sparks:
		_sparks.emitting = kind == "electrical_panel" and not done
	if kind == "generator" and done and _emitter == null:
		_emitter = Audio.create_emitter(self, "generator_loop", -2.0, 30.0, &"SFX")


func _completion_fx() -> void:
	match kind:
		"electrical_panel":
			Effects.sparks(self, global_transform * Vector3(0, 1.2, 0.2), global_basis.z, 40)
			Effects.smoke(self, global_transform * Vector3(0, 1.4, 0.2), 10, 2.0)
		"generator":
			Effects.smoke(self, global_transform * Vector3(-1.3, 3.3, 0.5), 24, 3.0, Color(0.12, 0.12, 0.12, 0.6))
			if Effects.ambient_enabled():
				Effects.smoke(self, global_transform * Vector3(-1.3, 3.3, 0.5), 8, 3.5, Color(0.2, 0.2, 0.2, 0.3), false)
		"containment_console":
			Effects.smoke(self, global_transform * Vector3(0, 2.9, -1.6), 18, 2.5, Color(0.7, 0.85, 0.8, 0.35))
		"breaker":
			Effects.sparks(self, global_transform * Vector3(0, 1.3, 0.15), global_basis.z, 16)


func set_powered(p: bool) -> void:
	_powered = p
	set_status(_done, false, false)


func set_progress(_p: float) -> void:
	pass


func _process(delta: float) -> void:
	if kind == "generator" and _done:
		_t += delta
		for f in _running:
			f.rotation.y += delta * 14.0
