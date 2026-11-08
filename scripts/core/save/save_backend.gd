class_name SaveBackend
extends RefCounted
## Storage abstraction. LocalSaveBackend writes files; a future CloudSaveBackend can sync
## the same documents with an online account without changing SaveManager callers.


func read_text(_key: String) -> String:
	return ""


func write_text(_key: String, _text: String) -> bool:
	return false


func read_backup(_key: String) -> String:
	return ""


func exists(_key: String) -> bool:
	return false


func remove(_key: String) -> void:
	pass


func describe() -> String:
	return "abstract"
