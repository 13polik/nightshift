extends Node
## Versioned, checksummed document storage (autoload "SaveManager").
##
## Documents ("profile", "settings", ...) are wrapped in an envelope:
##   { "format": 1, "doc": "profile", "version": N, "saved_at": unix, "checksum": md5, "data": {...} }
## Loading validates JSON, checksum and version; a corrupt file falls back to the .bak copy
## and finally to defaults, so invalid save data can never crash the game.

const FORMAT := 1

## Emitted when a document had to be recovered from backup or reset to defaults.
signal document_recovered(doc: String, from_backup: bool)

var backend: SaveBackend
## doc name -> Callable(version: int, data: Dictionary) -> Dictionary
var _migrations: Dictionary = {}
var last_recovery: Dictionary = {}


func _ready() -> void:
	if backend == null:
		var profile := CmdArgs.value("profile")
		backend = LocalSaveBackend.new("user://save" if profile.is_empty() else "user://save_" + profile.validate_filename())
	Log.i("save", "backend %s" % backend.describe())


func use_backend(b: SaveBackend) -> void:
	backend = b


func register_migration(doc: String, migrator: Callable) -> void:
	_migrations[doc] = migrator


## Loads a document. `defaults` provides every key; loaded data is merged over it so
## new fields added in updates always exist.
func load_document(doc: String, version: int, defaults: Dictionary) -> Dictionary:
	var result := _try_parse(doc, backend.read_text(doc))
	var from_backup := false
	if not result.ok:
		if backend.exists(doc):
			Log.w("save", "document '%s' invalid (%s) - trying backup" % [doc, result.error])
		var bak := _try_parse(doc, backend.read_backup(doc))
		if bak.ok:
			result = bak
			from_backup = true
			Log.w("save", "document '%s' restored from backup" % doc)
			document_recovered.emit(doc, true)
		else:
			if backend.exists(doc):
				Log.e("save", "document '%s' unrecoverable - using defaults" % doc)
				document_recovered.emit(doc, false)
				last_recovery[doc] = "defaults"
			return defaults.duplicate(true)
	var data: Dictionary = result.data
	var file_version: int = result.version
	if file_version < version and _migrations.has(doc):
		data = (_migrations[doc] as Callable).call(file_version, data)
	if from_backup:
		last_recovery[doc] = "backup"
		save_document(doc, version, data)
	return merge_defaults(defaults, data)


func save_document(doc: String, version: int, data: Dictionary) -> bool:
	var envelope := {
		"format": FORMAT,
		"doc": doc,
		"version": version,
		"saved_at": int(Time.get_unix_time_from_system()),
		"checksum": checksum(data),
		"data": data,
	}
	var ok := backend.write_text(doc, JSON.stringify(envelope, "\t", true))
	if not ok:
		Log.e("save", "failed writing '%s'" % doc)
	return ok


func delete_document(doc: String) -> void:
	backend.remove(doc)


## JSON turns every number into a float on load, so numbers are canonicalised to floats
## before hashing; otherwise a valid file would fail validation after a round trip.
static func checksum(data: Dictionary) -> String:
	return JSON.stringify(_canonical(data), "", true).md5_text()


static func _canonical(v: Variant) -> Variant:
	match typeof(v):
		TYPE_INT:
			return float(v)
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[str(k)] = _canonical(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for e in v:
				a.append(_canonical(e))
			return a
	return v


## Recursively fills missing keys from defaults and drops values whose type does not match
## the default (protects against hand-edited / corrupted values).
static func merge_defaults(defaults: Dictionary, data: Dictionary) -> Dictionary:
	var out := defaults.duplicate(true)
	for key in data:
		if not out.has(key):
			out[key] = data[key]
			continue
		var dv: Variant = out[key]
		var v: Variant = data[key]
		if dv is Dictionary and v is Dictionary:
			out[key] = merge_defaults(dv, v)
		elif _compatible(dv, v):
			out[key] = _coerce(dv, v)
	return out


static func _compatible(a: Variant, b: Variant) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	if ta == tb:
		return true
	var numeric := [TYPE_INT, TYPE_FLOAT]
	return ta in numeric and tb in numeric


static func _coerce(default_value: Variant, v: Variant) -> Variant:
	if typeof(default_value) == TYPE_INT and typeof(v) == TYPE_FLOAT:
		return int(v)
	if typeof(default_value) == TYPE_FLOAT and typeof(v) == TYPE_INT:
		return float(v)
	return v


func _try_parse(doc: String, text: String) -> Dictionary:
	var res := {"ok": false, "error": "", "data": {}, "version": 0}
	if text.is_empty():
		res.error = "empty"
		return res
	var json := JSON.new()
	if json.parse(text) != OK:
		res.error = "json: %s" % json.get_error_message()
		return res
	var env: Variant = json.data
	if not env is Dictionary:
		res.error = "not an object"
		return res
	if not (env.has("data") and env.data is Dictionary):
		res.error = "missing data"
		return res
	if env.get("doc", doc) != doc:
		res.error = "wrong doc"
		return res
	if str(env.get("checksum", "")) != checksum(env.data):
		res.error = "checksum mismatch"
		return res
	res.ok = true
	res.data = env.data
	res.version = int(env.get("version", 0))
	return res
