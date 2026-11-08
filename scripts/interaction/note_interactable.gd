class_name NoteInteractable
extends Interactable
## Inspectable document (environmental storytelling). Purely local: reading a note never
## touches the network.

var text_key: String = ""


func _ready() -> void:
	prompt_key = "PROMPT_READ"
	local_only = true
	interact_range = 1.8
	focus_height = 0.1
	tag = &"note"
	var model := PropFactory.model_for("note", "environment")
	if model:
		var inst: Node3D = model.instantiate()
		add_child(inst)
		MaterialLibrary.apply_named(inst)
		PropFactory.set_draw_distance(inst, 20.0, false)
		var g := MeshKit.add_box(self, Vector3(0.12, 0.004, 0.012), "emissive_amber", Vector3(0, 0.011, -0.14))
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	var paper := MeshKit.add_box(self, Vector3(0.22, 0.006, 0.3), "plastic_white", Vector3(0, 0.005, 0))
	paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glint := MeshKit.add_box(self, Vector3(0.18, 0.007, 0.02), "emissive_amber", Vector3(0, 0.006, -0.1))
	glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
