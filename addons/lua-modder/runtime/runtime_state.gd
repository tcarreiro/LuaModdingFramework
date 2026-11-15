class_name RuntimeState extends RefCounted

enum Phase {
	CREATED,
	SETUP,
	PREPARED,
	ACTIVE,
	CLOSED
}

var errors: Array[String] = []
var mod_id: String

var _phase: int = Phase.CREATED
var _lua_state: LuaState
var _script_api: LuaTable
var _game_api: LuaTable
var _lua_rawequal: LuaFunction
var _script_functions: Dictionary = {}
var _lifecycle_handlers: Dictionary = {}
var _execution_guard := LuaExecutionGuard.new()


func _init(id: String) -> void:
	mod_id = id


func start(mod_versions: Dictionary = {}) -> bool:
	if _phase != Phase.CREATED:
		errors.append("RuntimeState '%s' cannot be started again." % mod_id)
		return false

	if mod_id.strip_edges().is_empty():
		errors.append("RuntimeState requires a mod ID.")
		return false

	_lua_state = LuaState.new()
	_lua_state.open_libraries(
		LuaState.LUA_BASE |
		LuaState.LUA_STRING |
		LuaState.LUA_TABLE |
		LuaState.LUA_MATH
	)

	LuaExecutionGuard.restrict_base_functions(_lua_state)

	_script_api = _lua_state.create_table()
	_script_functions = {
		"on_init": _lua_state.create_function(_lua_on_init),
		"on_load": _lua_state.create_function(_lua_on_load),
		"on_configuration_changed": _lua_state.create_function(_lua_on_configuration_changed)
	}

	for function_name in _script_functions:
		_script_api[function_name] = _script_functions[function_name]

	_lua_rawequal = _lua_state.globals["rawequal"]
	_lua_state.globals["script"] = _script_api
	_lua_state.globals["mods"] = LuaUtils.to_lua_value(_lua_state, mod_versions)
	_lua_state.globals["game"] = null

	_phase = Phase.SETUP
	return true


func execute_control(source: String, chunk_name: String = "") -> bool:
	if _phase != Phase.SETUP:
		errors.append("Mod '%s' cannot execute control.lua outside setup." % mod_id)
		return false

	if not errors.is_empty():
		return false

	var success := _execution_guard.execute(_lua_state, source, chunk_name)

	if not success:
		errors.append("Lua error in mod '%s' (%s): %s" % [
			mod_id, chunk_name, _execution_guard.last_error
		])
		return false

	if not errors.is_empty():
		return false
	
	return _validate_setup_api()


func finish_setup() -> bool:
	if _phase != Phase.SETUP or not errors.is_empty():
		return false

	_phase = Phase.PREPARED
	return true


func activate(game_functions: Dictionary = {}) -> bool:
	if _phase != Phase.PREPARED:
		errors.append("Mod '%s' cannot activate before setup is complete." % mod_id)
		return false

	for function_name in game_functions:
		if typeof(function_name) != TYPE_STRING:
			errors.append("Runtime API function names must be strings.")
			return false

		var callback: Variant = game_functions[function_name]

		if not callback is Callable or not callback.is_valid():
			errors.append("Invalid runtime API function '%s'." % function_name)
			return false

	_game_api = _lua_state.create_table()

	for function_name in game_functions:
		_game_api[function_name] = _lua_state.create_function(game_functions[function_name])

	_lua_state.globals["game"] = _game_api
	_phase = Phase.ACTIVE
	return true


func get_phase() -> int:
	return _phase


func has_lifecycle_handler(handler_name: String) -> bool:
	return _lifecycle_handlers.has(handler_name)


func get_errors() -> Array[String]:
	return errors.duplicate()


func close() -> void:
	_lifecycle_handlers.clear()
	_script_functions.clear()
	_script_api = null
	_game_api = null
	_lua_rawequal = null
	_lua_state = null
	_phase = Phase.CLOSED


func _lua_on_init(handler: Variant) -> bool:
	return _register_lifecycle_handler("on_init", handler)


func _lua_on_load(handler: Variant) -> bool:
	return _register_lifecycle_handler("on_load", handler)


func _lua_on_configuration_changed(handler: Variant) -> bool:
	return _register_lifecycle_handler("on_configuration_changed", handler)


func _register_lifecycle_handler(handler_name: String, handler: Variant) -> bool:
	if _phase != Phase.SETUP:
		errors.append("Lifecycle callbacks can only be registered during setup.")
		return false

	if handler != null and not handler is LuaFunction:
		errors.append("Handler '%s' must be a Lua function or nil." % handler_name)
		return false

	if handler == null:
		_lifecycle_handlers.erase(handler_name)
	else:
		_lifecycle_handlers[handler_name] = handler

	return true


func _validate_setup_api() -> bool:
	var current_script: Variant = _lua_state.globals.rawget("script")

	if not current_script is LuaTable:
		errors.append("Mod '%s' removed or replaced the script API." % mod_id)
		return false

	if current_script.get_lua_state() != _lua_state or current_script.get_pointer_value() != _script_api.get_pointer_value():
		errors.append("Mod '%s' replaced the script API." % mod_id)
		return false

	for function_name in _script_functions:
		var current_function: Variant = _script_api.rawget(function_name)
		var expected_function: LuaFunction = _script_functions[function_name]

		if not current_function is LuaFunction:
			errors.append("Mod '%s' replaced script.%s." % [mod_id, function_name])
			return false

		if current_function.get_lua_state() != _lua_state or current_function.get_pointer_value() != expected_function.get_pointer_value():
			errors.append("Mod '%s' replaced script.%s." % [mod_id, function_name])
			return false

	if _lua_state.globals.rawget("game") != null:
		errors.append("Mod '%s' attempted to define game during setup." % mod_id)
		return false

	return true
