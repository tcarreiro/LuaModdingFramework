@tool
extends EditorPlugin

func _enter_tree() -> void:
	if not _check_dependencies():
		return

func _check_dependencies() -> bool:
	if not ClassDB.class_exists("LuaState"):
		push_error(
			"[Lua UI Builder] Missing dependency: 'lua-gdextension' "
			+ "need to be downloaded and installed. "
			+ "See: https://github.com/gilzoide/lua-gdextension"
		)
		return false
	return true
