class_name CharacterPreview
extends SubViewportContainer
## Rotating 3D preview of the operative with the given cosmetics (customize / lobby).

var _vp: SubViewport
var _pivot: Node3D
var _visual: CharacterVisual


func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(320, 420)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_2X
	add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.6)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_vp.add_child(env)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.1, 3.2)
	cam.fov = 40
	_vp.add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))
	var key := OmniLight3D.new()
	key.position = Vector3(1.5, 2.5, 2.0)
	key.light_energy = 2.0
	key.omni_range = 8.0
	_vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.5, 2.0, -1.5)
	rim.light_color = Color(1.0, 0.6, 0.3)
	rim.light_energy = 1.5
	rim.omni_range = 6.0
	_vp.add_child(rim)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_visual = ProceduralSurvivorVisual.new()
	_pivot.add_child(_visual)


func show_cosmetics(cos: Dictionary) -> void:
	if _visual:
		_visual.apply_cosmetics(cos)


func _process(delta: float) -> void:
	if _pivot:
		_pivot.rotation.y += delta * 0.5
