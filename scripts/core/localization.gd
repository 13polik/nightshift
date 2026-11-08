extends Node
## Localization (autoload "Loc"). String tables live in res://localization/<locale>.json
## (flat key -> text). They are turned into Translation objects at startup so all Controls
## and tr() calls are translated by Godot's TranslationServer.

const SUPPORTED: Array[String] = ["en", "pl"]
const LANGUAGE_NAMES := {"en": "English", "pl": "Polski"}

var _tables: Dictionary = {}


func _ready() -> void:
	for locale in SUPPORTED:
		var table := load_table(locale)
		_tables[locale] = table
		var t := Translation.new()
		t.locale = locale
		for key: String in table:
			t.add_message(key, str(table[key]))
		TranslationServer.add_translation(t)
	var lang := str(Settings.data.get("language", ""))
	if lang.is_empty():
		lang = OS.get_locale_language()
	set_language(lang, false)


static func load_table(locale: String) -> Dictionary:
	var path := "res://localization/%s.json" % locale
	if not FileAccess.file_exists(path):
		Log.e("loc", "missing string table %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		Log.e("loc", "invalid string table %s" % path)
		return {}
	return parsed


func set_language(locale: String, persist: bool = true) -> void:
	if not locale in SUPPORTED:
		locale = "en"
	TranslationServer.set_locale(locale)
	if persist:
		Settings.data["language"] = locale
		Settings.save()
	Events.language_changed.emit(locale)


func current() -> String:
	return TranslationServer.get_locale().substr(0, 2)


## Translate with optional {name} placeholders.
func t(key: String, args: Dictionary = {}) -> String:
	var s := TranslationServer.translate(key)
	if not args.is_empty():
		s = s.format(args)
	return s


func has_key(key: String, locale: String = "en") -> bool:
	return _tables.get(locale, {}).has(key)


func table(locale: String) -> Dictionary:
	return _tables.get(locale, {})
