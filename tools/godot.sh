#!/usr/bin/env bash
# Dev helper: runs the Godot console binary against this project.
# Usage: tools/godot.sh [godot args...]
GODOT="${GODOT:-/c/Users/HP ProBook 640 G2/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec "$GODOT" --path "$DIR" "$@"
