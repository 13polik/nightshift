extends Node
## Central logger (autoload "Log"). Categories make multi-process network logs readable,
## and a ring buffer keeps recent lines for the debug overlay / bug reports.

enum Level { DEBUG, INFO, WARN, ERROR }
const LEVEL_NAMES: Array[String] = ["DBG", "INF", "WRN", "ERR"]
const BUFFER_SIZE := 400

signal message_logged(level: int, category: String, text: String)

var min_level: Level = Level.DEBUG
## Prefix set by the network layer (e.g. "H1" for host, "C2" for client) for multi-instance logs.
var prefix: String = ""
var _buffer: PackedStringArray = PackedStringArray()


func _ready() -> void:
	if not OS.is_debug_build():
		min_level = Level.INFO


func d(category: String, text: String) -> void:
	_write(Level.DEBUG, category, text)


func i(category: String, text: String) -> void:
	_write(Level.INFO, category, text)


func w(category: String, text: String) -> void:
	_write(Level.WARN, category, text)


func e(category: String, text: String) -> void:
	_write(Level.ERROR, category, text)


func recent_lines() -> PackedStringArray:
	return _buffer


func _write(level: Level, category: String, text: String) -> void:
	if level < min_level:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var p := ("[%s]" % prefix) if not prefix.is_empty() else ""
	var line := "%s[%8.2f][%s][%s] %s" % [p, t, LEVEL_NAMES[level], category, text]
	if level == Level.ERROR:
		# push_error prints to stderr (with backtrace) and reaches the debugger
		push_error(line)
	else:
		print(line)
	_buffer.append(line)
	if _buffer.size() > BUFFER_SIZE:
		_buffer = _buffer.slice(_buffer.size() - BUFFER_SIZE)
	message_logged.emit(level, category, text)
