class_name ItemVisuals
extends RefCounted
## Procedural development models for items (used until real meshes are assigned through
## ItemData.world_model). Each has an emissive accent so loot reads in the dark.


static func build(data: ItemData) -> Node3D:
	var root := Node3D.new()
	var id := String(data.id) if data else "unknown"
	var model := PropFactory.model_for(id, "items")
	if model:
		var inst: Node3D = model.instantiate()
		root.add_child(inst)
		MaterialLibrary.apply_named(inst)
		PropFactory.set_draw_distance(inst, 25.0, false)
		_add_halo(root, data)
		return root
	match id:
		"battery":
			MeshKit.add_cyl(root, 0.05, 0.16, "metal_dark", Vector3(0, 0.08, 0))
			MeshKit.add_cyl(root, 0.052, 0.05, "emissive_green", Vector3(0, 0.14, 0))
		"medkit":
			MeshKit.add_box(root, Vector3(0.34, 0.12, 0.24), "plastic_white", Vector3(0, 0.06, 0))
			MeshKit.add_box(root, Vector3(0.2, 0.125, 0.05), "emissive_red", Vector3(0, 0.065, 0))
			MeshKit.add_box(root, Vector3(0.05, 0.125, 0.16), "emissive_red", Vector3(0, 0.065, 0))
		"bandage":
			MeshKit.add_cyl(root, 0.06, 0.08, "plastic_white", Vector3(0, 0.04, 0), Vector3(90, 0, 0))
		"keycard":
			MeshKit.add_box(root, Vector3(0.09, 0.01, 0.14), "plastic_white", Vector3(0, 0.01, 0))
			MeshKit.add_box(root, Vector3(0.091, 0.012, 0.03), "emissive_cyan", Vector3(0, 0.012, -0.04))
		"fuse":
			MeshKit.add_cyl(root, 0.035, 0.18, "glass", Vector3(0, 0.035, 0), Vector3(0, 0, 90))
			MeshKit.add_cyl(root, 0.038, 0.04, "metal_bright", Vector3(0.08, 0.035, 0), Vector3(0, 0, 90))
			MeshKit.add_cyl(root, 0.038, 0.04, "metal_bright", Vector3(-0.08, 0.035, 0), Vector3(0, 0, 90))
			MeshKit.add_cyl(root, 0.01, 0.12, "emissive_amber", Vector3(0, 0.035, 0), Vector3(0, 0, 90))
		"circuit_board":
			MeshKit.add_box(root, Vector3(0.22, 0.02, 0.16), "emissive_green", Vector3(0, 0.01, 0))
			MeshKit.add_box(root, Vector3(0.06, 0.04, 0.06), "plastic_dark", Vector3(0.04, 0.03, 0.02))
			MeshKit.add_box(root, Vector3(0.04, 0.03, 0.08), "metal_bright", Vector3(-0.06, 0.025, -0.02))
		"access_decoder":
			MeshKit.add_box(root, Vector3(0.14, 0.05, 0.22), "plastic_dark", Vector3(0, 0.025, 0))
			MeshKit.add_box(root, Vector3(0.1, 0.052, 0.08), "screen_on", Vector3(0, 0.03, -0.04))
		"sample_case":
			MeshKit.add_box(root, Vector3(0.4, 0.26, 0.24), "metal_bright", Vector3(0, 0.13, 0))
			MeshKit.add_cyl(root, 0.06, 0.2, "biohazard_liquid", Vector3(0, 0.27, 0), Vector3(0, 0, 90))
			MeshKit.add_box(root, Vector3(0.41, 0.03, 0.03), "emissive_amber", Vector3(0, 0.2, 0.12))
		"crowbar":
			MeshKit.add_cyl(root, 0.018, 0.75, "metal_dark", Vector3(0, 0.02, 0), Vector3(0, 0, 90))
			MeshKit.add_box(root, Vector3(0.08, 0.04, 0.04), "hazard", Vector3(0.36, 0.02, 0))
		"arc_emitter":
			MeshKit.add_box(root, Vector3(0.1, 0.12, 0.3), "metal_painted", Vector3(0, 0.06, 0))
			MeshKit.add_cyl(root, 0.03, 0.12, "emissive_cyan", Vector3(0, 0.08, -0.2), Vector3(90, 0, 0))
		"arc_cell":
			MeshKit.add_cyl(root, 0.035, 0.1, "emissive_cyan", Vector3(0, 0.05, 0))
		"data_drive":
			MeshKit.add_box(root, Vector3(0.08, 0.025, 0.12), "metal_bright", Vector3(0, 0.0125, 0))
			MeshKit.add_box(root, Vector3(0.02, 0.026, 0.02), "emissive_cyan", Vector3(0.025, 0.013, -0.045))
		_:
			MeshKit.add_box(root, Vector3(0.2, 0.2, 0.2), "metal_painted", Vector3(0, 0.1, 0))
	_add_halo(root, data)
	for c in root.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## Soft floor halo so items are discoverable in darkness without a real light.
static func _add_halo(root: Node3D, data: ItemData) -> void:
	var halo := MeshKit.add_cyl(root, 0.28, 0.005, "emissive_amber" if data and data.category == ItemData.Category.OBJECTIVE else "emissive_cyan", Vector3(0, -0.07, 0))
	halo.transparency = 0.75
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
