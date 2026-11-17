@tool
class_name State extends RefCounted

var errors: Array[String] = []
var warnings: Array[String] = []

var _lua_state: LuaState
var _raw: LuaTable
var _current_mod_id: String = ""
var _execution_guard := LuaExecutionGuard.new()

func get_errors() -> Array[String]:
	return []


func get_warnings() -> Array[String]:
	return []


func close() -> void:
	push_error("State not implemented.")


func execute(source: String, mod_id: String, chunk_name: String = "") -> bool:
	push_error("State not implemented")
	return false


func is_active() -> bool:
	push_error("State not implemented")
	return false


func define_from_json(data: Dictionary, mod_id: String) -> bool:
	if not is_active():
		errors.append("State is not active.")
		return false
	
	if not get_errors().is_empty():
		return false
	
	if mod_id.strip_edges().is_empty():
		errors.append("Cannot register state without a mod ID.")
		return false
	
	return true
