extends Node
## Player settings (autoload "Settings"): graphics, audio, controls, gameplay, language.
## Persisted through SaveManager as the "settings" document.

enum Quality { LOW, MEDIUM, HIGH }
enum TouchUi { AUTO, ALWAYS, NEVER }

const DOC := "settings"
const VERSION := 1

const DEFAULTS := {
	"graphics": {
		"quality": -1, # -1 = auto-detect on first launch
		"render_scale": 1.0,
		"fps_cap": 60,
		"show_fps": false,
		"vsync": true,
	},
	"audio": {
		"master": 0.9,
		"music": 0.7,
		"sfx": 1.0,
		"ambience": 0.85,
		"ui": 0.8,
	},
	"controls": {
		"look_sensitivity": 1.0,
		"invert_y": false,
		"joystick_scale": 1.0,
		"button_scale": 1.0,
		"hud_opacity": 0.85,
		"left_handed": false,
		"dynamic_joystick": true,
		"sprint_toggle": false,
		"crouch_toggle": true,
		"haptics": true,
		"touch_ui": TouchUi.AUTO,
		"mouse_sensitivity": 1.0,
	},
	"gameplay": {
		"camera_shake": 1.0,
		"subtitles": true,
		"show_hints": true,
	},
	"network": {
		"relay_url": "",
	},
	"language": "",
}

## Per-quality render presets. Values chosen for mid-range mobile GPUs at MEDIUM.
const QUALITY_PRESETS := {
	Quality.LOW: {
		"scale_3d": 0.65, "msaa": Viewport.MSAA_DISABLED, "shadows": false,
		"flashlight_shadows": false, "glow": false, "fog": true, "particles": false,
		"max_room_lights": 4, "light_range": 22.0, "draw_distance": 40.0, "lod_bias": 0.5,
		"shadow_atlas": 512, "ambient_detail": false, "volumetric": false,
	},
	Quality.MEDIUM: {
		"scale_3d": 0.85, "msaa": Viewport.MSAA_DISABLED, "shadows": false,
		"flashlight_shadows": true, "glow": true, "fog": true, "particles": true,
		"max_room_lights": 6, "light_range": 28.0, "draw_distance": 60.0, "lod_bias": 1.0,
		"shadow_atlas": 1024, "ambient_detail": true, "volumetric": false,
	},
	Quality.HIGH: {
		"scale_3d": 1.0, "msaa": Viewport.MSAA_2X, "shadows": true,
		"flashlight_shadows": true, "glow": true, "fog": true, "particles": true,
		"max_room_lights": 10, "light_range": 40.0, "draw_distance": 90.0, "lod_bias": 1.5,
		"shadow_atlas": 2048, "ambient_detail": true, "volumetric": true,
	},
}

var data: Dictionary = {}


func _ready() -> void:
	InputSetup.register_default_actions()
	data = SaveManager.load_document(DOC, VERSION, DEFAULTS)
	if int(data.graphics.quality) < 0:
		data.graphics.quality = detect_quality()
		Log.i("settings", "auto-detected graphics quality %s" % Quality.keys()[data.graphics.quality])
		save()
	var forced := CmdArgs.value("quality").to_upper()
	if forced in Quality.keys():
		data.graphics.quality = Quality[forced]
	apply_all.call_deferred()


func get_value(section: String, key: String) -> Variant:
	var s: Variant = data.get(section)
	if s is Dictionary:
		return s.get(key, DEFAULTS[section].get(key))
	return null


func set_value(section: String, key: String, value: Variant, persist: bool = true) -> void:
	if not data.has(section) or not data[section] is Dictionary:
		data[section] = DEFAULTS[section].duplicate(true)
	data[section][key] = value
	_apply_section(section)
	Events.settings_changed.emit(section)
	if persist:
		save()


func save() -> void:
	SaveManager.save_document(DOC, VERSION, data)


func apply_all() -> void:
	for section in ["graphics", "audio", "controls"]:
		_apply_section(section)


func quality() -> int:
	return clampi(int(data.graphics.quality), Quality.LOW, Quality.HIGH)


func preset() -> Dictionary:
	return QUALITY_PRESETS[quality()]


func touch_ui_enabled() -> bool:
	if CmdArgs.has("touch"):
		return true
	match int(get_value("controls", "touch_ui")):
		TouchUi.ALWAYS:
			return true
		TouchUi.NEVER:
			return false
	return is_mobile() or DisplayServer.is_touchscreen_available()


static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]


## Conservative heuristic; players can change it in settings.
func detect_quality() -> int:
	if DisplayServer.get_name() == "headless":
		return Quality.LOW
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	if not is_mobile():
		return Quality.HIGH
	var low_markers := ["mali-g5", "mali-t", "adreno (tm) 5", "adreno (tm) 4", "powervr", "adreno (tm) 61"]
	for m in low_markers:
		if adapter.contains(m):
			return Quality.LOW
	if OS.get_processor_count() >= 8:
		return Quality.MEDIUM
	return Quality.LOW


func _apply_section(section: String) -> void:
	match section:
		"graphics":
			_apply_graphics()
		"audio":
			if is_instance_valid(Audio):
				Audio.apply_volumes(data.audio)
		"controls":
			Input.emulate_touch_from_mouse = touch_ui_enabled() and not is_mobile()


func _apply_graphics() -> void:
	var p := preset()
	var vp := get_viewport()
	if vp == null:
		return
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = clampf(float(p.scale_3d) * float(data.graphics.render_scale), 0.5, 1.0)
	vp.msaa_3d = p.msaa
	vp.positional_shadow_atlas_size = int(p.shadow_atlas)
	vp.mesh_lod_threshold = 1.0 / maxf(0.25, float(p.lod_bias))
	Engine.max_fps = int(data.graphics.fps_cap)
	MaterialLibrary.apply_quality(quality())
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if data.graphics.vsync else DisplayServer.VSYNC_DISABLED)
	Events.graphics_quality_changed.emit(quality())
