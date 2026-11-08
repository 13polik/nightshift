extends Node
## Audio architecture (autoload "Audio").
##  * Buses: Master > Music, SFX (with facility reverb), Ambience, UI
##  * Cue library: id -> AudioStream (real files in res://audio/cues override synthesis)
##  * Pooled 3D one-shots with simple wall occlusion, pooled 2D/UI one-shots
##  * Persistent emitters (ambience beds, alarms, machines) owned by world nodes

const BUSES := ["Music", "SFX", "Ambience", "UI"]
const POOL_3D := 24
const POOL_2D := 8
const CUE_EXTENSIONS := ["ogg", "wav", "mp3"]
const ASSET_ROOT := "res://assets/audio"
## Cues that loop (beds, machines, music layers, emitters).
const LOOPING := ["amb_vent", "amb_hum", "amb_drone", "music_tension", "music_pulse", "music_chase", "generator_loop",
	"elevator", "alarm", "interact_loop", "hunter_breath", "hunter_presence", "heartbeat"]
const OCCLUSION_MASK := 1

var _cache: Dictionary = {}
## cue id -> Array[String] of authored files (several takes => random variation)
var _index: Dictionary = {}
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _next3d := 0
var _next2d := 0
var muted_for_tests := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_index_assets(ASSET_ROOT)
	_setup_buses()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.max_polyphony = 1
		p.panning_strength = 1.0
		add_child(p)
		_pool3d.append(p)
	for i in POOL_2D:
		var p2 := AudioStreamPlayer.new()
		p2.bus = &"UI"
		add_child(p2)
		_pool2d.append(p2)
	apply_volumes(Settings.data.get("audio", {}))
	if DisplayServer.get_name() == "headless":
		muted_for_tests = true


func _setup_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, &"Master")
	var sfx := AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.65
		reverb.damping = 0.6
		reverb.wet = 0.18
		reverb.dry = 1.0
		AudioServer.add_bus_effect(sfx, reverb)
	var amb := AudioServer.get_bus_index("Ambience")
	if AudioServer.get_bus_effect_count(amb) == 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 9000.0
		AudioServer.add_bus_effect(amb, lp)


func apply_volumes(audio: Dictionary) -> void:
	_set_bus_volume("Master", float(audio.get("master", 1.0)))
	_set_bus_volume("Music", float(audio.get("music", 1.0)))
	_set_bus_volume("SFX", float(audio.get("sfx", 1.0)))
	_set_bus_volume("Ambience", float(audio.get("ambience", 1.0)))
	_set_bus_volume("UI", float(audio.get("ui", 1.0)))


func _set_bus_volume(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


func _index_assets(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for d in dir.get_directories():
		_index_assets(path.path_join(d))
	for f in dir.get_files():
		var fname := f.trim_suffix(".import").trim_suffix(".remap")
		var ext := fname.get_extension()
		if not ext in CUE_EXTENSIONS:
			continue
		var base := fname.get_basename()
		# "<cue>_<n>" are takes of the same cue
		var cue_id := base
		var us := base.rfind("_")
		if us > 0 and base.substr(us + 1).is_valid_int():
			cue_id = base.substr(0, us)
		if not _index.has(cue_id):
			_index[cue_id] = []
		var full := path.path_join(fname)
		if not full in _index[cue_id]:
			(_index[cue_id] as Array).append(full)


func has_authored(id: String) -> bool:
	return _index.has(id)


## Returns the stream for a cue id: an authored asset (random take) when present,
## otherwise the procedural fallback.
func cue(id: String) -> AudioStream:
	if _index.has(id):
		var takes: Array = _index[id]
		var path: String = takes[randi() % takes.size()]
		if _cache.has(path):
			return _cache[path]
		# looping is configured in the import settings (tools/audio/patch_imports.py)
		var st: AudioStream = load(path)
		_cache[path] = st
		return st
	if _cache.has(id):
		return _cache[id]
	var stream: AudioStream = null
	for ext in CUE_EXTENSIONS:
		var path := "res://audio/cues/%s.%s" % [id, ext]
		if ResourceLoader.exists(path):
			stream = load(path)
			break
	if stream == null:
		stream = ProceduralAudio.generate(id)
	_cache[id] = stream
	return stream


## Pre-generates cues during loading screens so gameplay never hitches.
func warm(ids: Array) -> void:
	for id in ids:
		if _index.has(str(id)):
			for path in _index[str(id)]:
				if not _cache.has(path):
					_cache[path] = load(path)
		else:
			cue(str(id))


func play_ui(id: String, volume_db: float = 0.0) -> void:
	if muted_for_tests:
		return
	var p := _pool2d[_next2d]
	_next2d = (_next2d + 1) % _pool2d.size()
	p.stream = cue(id)
	p.volume_db = volume_db
	p.bus = &"UI"
	p.play()


func play_2d(id: String, volume_db: float = 0.0, bus: StringName = &"SFX") -> void:
	if muted_for_tests:
		return
	var p := _pool2d[_next2d]
	_next2d = (_next2d + 1) % _pool2d.size()
	p.stream = cue(id)
	p.volume_db = volume_db
	p.bus = bus
	p.play()


## Positional one-shot. `range_m` = distance where the sound becomes inaudible.
func play_3d(id: String, pos: Vector3, volume_db: float = 0.0, range_m: float = 25.0, pitch: float = 1.0) -> void:
	if muted_for_tests:
		return
	var p := _pool3d[_next3d]
	_next3d = (_next3d + 1) % _pool3d.size()
	p.stop()
	p.stream = cue(id)
	p.global_position = pos
	p.max_distance = range_m
	p.unit_size = range_m * 0.18
	p.pitch_scale = pitch
	var occluded := _is_occluded(pos)
	p.volume_db = volume_db - (7.0 if occluded else 0.0)
	p.attenuation_filter_cutoff_hz = 1800.0 if occluded else 9000.0
	p.play()


## Creates a looping positional emitter owned by `parent` (machines, alarms, vents).
func create_emitter(parent: Node3D, id: String, volume_db: float = -6.0, range_m: float = 18.0, bus: StringName = &"Ambience") -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = cue(id)
	p.bus = bus
	p.volume_db = volume_db
	p.max_distance = range_m
	p.unit_size = range_m * 0.2
	p.attenuation_filter_cutoff_hz = 6000.0
	parent.add_child(p)
	if not muted_for_tests:
		p.autoplay = true
		if p.is_inside_tree():
			p.play()
	return p


func _is_occluded(pos: Vector3) -> bool:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	if cam == null or not cam.is_inside_tree():
		return false
	var space := cam.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, pos, OCCLUSION_MASK)
	return not space.intersect_ray(q).is_empty()
