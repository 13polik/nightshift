extends Node
## Global, application-level signals (autoload "Events"). Gameplay signals stay scoped to
## mission systems so nothing leaks between missions.

signal settings_changed(section: String)
signal language_changed(locale: String)
signal graphics_quality_changed(quality: int)
signal profile_changed
## Lightweight UI notifications. `text` may be a translation key.
signal toast_requested(text: String, kind: int)
## Modal error/info dialog request.
signal dialog_requested(title_key: String, body: String, kind: int)

enum ToastKind { INFO, SUCCESS, WARNING, DANGER }


func toast(text: String, kind: int = ToastKind.INFO) -> void:
	toast_requested.emit(text, kind)


func error_dialog(title_key: String, body: String) -> void:
	dialog_requested.emit(title_key, body, ToastKind.DANGER)
