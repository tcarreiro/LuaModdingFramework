class_name RuntimeState extends RefCounted

enum Phase {
	CREATED,
	SETUP,
	PREPARED,
	ACTIVE,
	CLOSED
}

const MAX_CUSTOM_EVENTS := 1024
const MAX_REMOTE_INTERFACES := 128
const MAX_REMOTE_FUNCTIONS := 128

var errors: Array[String] = []
var mod_id: String

var _phase: int = Phase.CREATED
var _lua_state: LuaState
var _script_api: LuaTable
var _game_api: LuaTable
var _script_functions: Dictionary = {}
var _lifecycle_handlers: Dictionary = {}
var _execution_guard := LuaExecutionGuard.new()
var _storage: LuaTable
var _storage_codec := RuntimeStorage.new()
var _event_handlers: Dictionary = {}
var _custom_events: Dictionary = {}
var _custom_event_sink: Callable
var _inside_on_load := false
var _handler_coroutines: Dictionary = {}
var _remote_api: LuaTable
var _remote_functions: Dictionary = {}
var _remote_interfaces: Dictionary = {}
var _remote_coroutines: Dictionary = {}


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
	_storage = _lua_state.create_table()
	
	_lua_state.globals["storage"] = _storage
	
	_script_functions = {
		"on_init": _lua_state.create_function(_lua_on_init),
		"on_load": _lua_state.create_function(_lua_on_load),
		"on_configuration_changed": _lua_state.create_function(_lua_on_configuration_changed),
		"on_event": _lua_state.create_function(_lua_on_event),
		"register_event": _lua_state.create_function(_lua_register_event),
		"raise_event": _lua_state.create_function(_lua_raise_event),
	}
	
	for function_name in _script_functions:
		_script_api[function_name] = _script_functions[function_name]
	_lua_state.globals["script"] = _script_api
	
	_remote_api = _lua_state.create_table()
	_remote_functions = {
		"add_interface": _lua_state.create_function(_lua_remote_add_interface)
	}
	for function_name in _remote_functions:
		_remote_api.rawset(function_name, _remote_functions[function_name])
	_lua_state.globals["remote"] = _remote_api
	
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


func run_lifecycle(handler_name: String, data: Dictionary = {}) -> bool:
	if _phase != Phase.ACTIVE or not errors.is_empty():
		return false
	
	if handler_name not in ["on_init", "on_load", "on_configuration_changed"]:
		errors.append("Unknown lifecycle callback '%s' for mod '%s'." % [handler_name, mod_id])
		return false
	
	if not _validate_storage_api():
		return false
	
	if not _lifecycle_handlers.has(handler_name):
		return true
	
	var is_load := handler_name == "on_load"
	_inside_on_load = is_load
	var storage_before: Dictionary = {}
	if is_load:
		storage_before = _storage_codec.capture(_lua_state, _storage)
		if not _storage_codec.errors.is_empty():
			errors.append_array(_storage_codec.errors)
			return false
		_lua_state.globals.rawset("game", null)
	
	var arguments: Array = []
	if handler_name == "on_configuration_changed":
		arguments.append(LuaUtils.to_lua_value(_lua_state, data))
	
	var callback: LuaFunction = _lifecycle_handlers[handler_name]
	var success := _execution_guard.invoke(
		_lua_state,
		callback,
		arguments,
		"%s/%s" % [mod_id, handler_name]
	)
	_inside_on_load = false

	if is_load:
		if _lua_state.globals.rawget("game") != null:
			errors.append("Mod '%s' defined game during on_load." % mod_id)
		_lua_state.globals.rawset("game", _game_api)
	else:
		var current_game: Variant = _lua_state.globals.rawget("game")
		if not _same_lua_object(current_game, _game_api):
			errors.append("Mod '%s' replaced the game API during %s." % [mod_id, handler_name])
			_lua_state.globals.rawset("game", _game_api)
	
	if not success:
		errors.append("Lua error in mod '%s' (%s): %s" % [
			mod_id, handler_name, _execution_guard.last_error
		])
	
	_validate_script_api()
	_validate_storage_api()
	_validate_remote_api()
	
	if is_load:
		var storage_after := _storage_codec.capture(_lua_state, _storage)
		if not _storage_codec.errors.is_empty():
			errors.append_array(_storage_codec.errors)
		elif storage_before != storage_after:
			errors.append("Mod '%s' modified storage during on_load." % mod_id)
	
	return success and errors.is_empty()


func get_phase() -> int:
	return _phase


func has_lifecycle_handler(handler_name: String) -> bool:
	return _lifecycle_handlers.has(handler_name)


func get_errors() -> Array[String]:
	return errors.duplicate()


func close() -> void:
	_lifecycle_handlers.clear()
	_event_handlers.clear()
	_remote_interfaces.clear()
	
	_handler_coroutines.clear()
	_remote_coroutines.clear() # it needs to happen AFTER _remote_interfaces.clear()
	
	_script_functions.clear()
	_remote_functions.clear()
	
	_custom_events.clear()
	_custom_event_sink = Callable()
	
	_script_api = null
	_storage = null
	_game_api = null
	_lua_state = null
	
	_phase = Phase.CLOSED
	_inside_on_load = false


#region Exposed APIs
func _lua_on_init(handler: Variant) -> bool:
	return _register_lifecycle_handler("on_init", handler)


func _lua_on_load(handler: Variant) -> bool:
	return _register_lifecycle_handler("on_load", handler)


func _lua_on_configuration_changed(handler: Variant) -> bool:
	return _register_lifecycle_handler("on_configuration_changed", handler)


func _lua_on_event(event_ids: Variant, handler: Variant) -> bool:
	if _phase != Phase.SETUP and _phase != Phase.ACTIVE:
		errors.append("Mod '%s' cannot register events in the current phase." % mod_id)
		return false

	if handler != null and not handler is LuaFunction:
		errors.append("Mod '%s' registered an invalid event handler." % mod_id)
		return false

	if handler is LuaFunction and handler.get_lua_state() != _lua_state:
		errors.append("Mod '%s' registered a handler from another LuaState." % mod_id)
		return false

	var raw_ids: Array = []
	if typeof(event_ids) == TYPE_STRING:
		raw_ids.append(event_ids)
	elif event_ids is LuaTable:
		raw_ids = event_ids.to_array()
	elif event_ids is Array:
		raw_ids = event_ids
	else:
		errors.append("Mod '%s' provided invalid event identifiers." % mod_id)
		return false

	if raw_ids.is_empty():
		errors.append("Mod '%s' provided an empty event list." % mod_id)
		return false

	var names: Array[String] = []
	for value in raw_ids:
		if typeof(value) != TYPE_STRING or String(value).strip_edges().is_empty():
			errors.append("Mod '%s' provided an invalid event name." % mod_id)
			return false

		if value not in names:
			names.append(value)

	var coroutine: LuaCoroutine
	if handler != null:
		coroutine = _execution_guard.get_active_coroutine()
		if coroutine == null:
			errors.append("Cannot register event handler outside protected Lua execution.")
			return false

	for event_name in names:
		var key := "event:" + event_name

		if handler == null:
			_event_handlers.erase(event_name)
			_handler_coroutines.erase(key)
		else:
			_event_handlers[event_name] = handler
			_handler_coroutines[key] = coroutine

	return true


func _lua_register_event(local_name: Variant) -> String:
	if _phase != Phase.SETUP:
		errors.append("Mod '%s' can only register custom events during setup." % mod_id)
		return ""
	
	if typeof(local_name) != TYPE_STRING:
		errors.append("Mod '%s' provided an invalid custom event name." % mod_id)
		return ""
	
	var name := String(local_name)
	var pattern := RegEx.create_from_string("^[A-Za-z_][A-Za-z0-9_.-]*$")
	if name.length() > 100 or pattern.search(name) == null:
		errors.append("Mod '%s' provided an invalid custom event name '%s'." % [mod_id, name])
		return ""
	
	var event_name := "%s:%s" % [mod_id, name]
	if not _custom_events.has(event_name) and _custom_events.size() >= MAX_CUSTOM_EVENTS:
		errors.append("Mod '%s' exceeded its custom event limit." % mod_id)
		return ""
	
	_custom_events[event_name] = true
	return event_name


func _lua_raise_event(event_name: Variant, payload: Variant) -> bool:
	if _phase != Phase.ACTIVE or _inside_on_load:
		errors.append("Mod '%s' cannot raise custom events in this phase." % mod_id)
		return false
	
	if typeof(event_name) != TYPE_STRING or not _custom_events.has(event_name):
		errors.append("Mod '%s' cannot raise undeclared or foreign event '%s'." % [mod_id, str(event_name)])
		return false
	
	if not payload is LuaTable:
		errors.append("Custom event '%s' requires a Lua table payload." % event_name)
		return false
	
	if not _custom_event_sink.is_valid():
		errors.append("Mod '%s' has no custom event dispatcher." % mod_id)
		return false
	
	var visited: Dictionary = {}
	var counter: Array[int] = [0]
	var data: Variant = _read_custom_event_value(payload, 0, visited, counter)
	if not errors.is_empty():
		return false
	
	if not data is Dictionary:
		errors.append("Custom event payload must be a table.")
		return false
	
	if data.has("name") or data.has("mod_name"):
		errors.append("Custom event payload contains reserved fields.")
		return false
	
	if not _custom_event_sink.call(mod_id, String(event_name), data):
		errors.append("Mod '%s' failed to enqueue custom event '%s'." % [mod_id, event_name])
		return false
	
	return true


func _lua_remote_add_interface(local_name: Variant, functions: Variant) -> String:
	if _phase != Phase.SETUP:
		errors.append("Mod '%s' can only register remote interfaces during setup." % mod_id)
		return ""
	
	if typeof(local_name) != TYPE_STRING:
		errors.append("Mod '%s' provided an invalid remote interface name." % mod_id)
		return ""
	
	if not functions is LuaTable or functions.get_lua_state() != _lua_state:
		errors.append("Mod '%s' provided an invalid remote interface definition." % mod_id)
		return ""
	
	var name := String(local_name)
	var pattern := RegEx.create_from_string("^[A-Za-z_][A-Za-z0-9_.-]*$")
	if name.length() > 100 or pattern.search(name) == null:
		errors.append("Mod '%s' provided an invalid remote interface name '%s'." % [mod_id, name])
		return ""
	
	var interface_name := "%s:%s" % [mod_id, name]
	if _remote_interfaces.has(interface_name):
		errors.append("Mod '%s' already registered remote interface '%s'." % [mod_id, interface_name])
		return ""
	
	if _remote_interfaces.size() >= MAX_REMOTE_INTERFACES:
		errors.append("Mod '%s' exceeded its remote interface limit." % mod_id)
		return ""
	
	var definitions: Dictionary = functions.to_dictionary()
	if definitions.is_empty() or definitions.size() > MAX_REMOTE_FUNCTIONS:
		errors.append("Remote interface '%s' must contain between 1 and %d functions." % [
			interface_name, MAX_REMOTE_FUNCTIONS
		])
		return ""
	
	var methods: Dictionary = {}
	for method_name in definitions:
		if typeof(method_name) != TYPE_STRING:
			errors.append("Remote interface '%s' contains a non-string method name." % interface_name)
			return ""
	
		if pattern.search(String(method_name)) == null:
			errors.append("Remote interface '%s' contains an invalid method name '%s'." % [
				interface_name, str(method_name)
			])
			return ""
	
		var callback: Variant = definitions[method_name]
		if not callback is LuaFunction:
			errors.append("Remote interface '%s' contains an invalid method '%s'." % [
				interface_name, method_name
			])
			return ""
	
		if callback.get_lua_state() != _lua_state:
			errors.append("Remote method '%s' belongs to another LuaState." % method_name)
			return ""
		methods[method_name] = callback
	
	var origin := _execution_guard.get_active_coroutine()
	if origin == null:
		errors.append("Remote interfaces must be registered during protected Lua execution.")
		return ""
	
	_remote_interfaces[interface_name] = methods
	_remote_coroutines[interface_name] = origin
	
	return interface_name
#endregion


#region public methods
func has_event_handler(event_name: String) -> bool:
	return _event_handlers.has(event_name)


func set_custom_event_sink(sink: Callable) -> bool:
	if _phase != Phase.CREATED or not sink.is_valid():
		errors.append("Invalid custom event sink for mod '%s'." % mod_id)
		return false
	_custom_event_sink = sink
	return true


func get_custom_events() -> Array[String]:
	var result: Array[String] = []
	for event_name in _custom_events:
		result.append(event_name)
	return result


func restore_storage(snapshot: Dictionary = {}) -> bool:
	if _phase != Phase.ACTIVE or not errors.is_empty():
		errors.append("Mod '%s' cannot restore storage outside activation." % mod_id)
		return false

	var restored := _storage_codec.restore(_lua_state, snapshot)

	if restored == null:
		for error in _storage_codec.errors:
			errors.append("Mod '%s': %s" % [mod_id, error])
		return false

	_storage = restored
	_lua_state.globals.rawset("storage", _storage)
	return true


func snapshot_storage() -> Dictionary:
	if _phase != Phase.ACTIVE or not errors.is_empty():
		errors.append("Mod '%s' cannot snapshot storage." % mod_id)
		return {}
	
	if not _validate_storage_api():
		return {}
	
	var snapshot := _storage_codec.capture(_lua_state, _storage)
	if not _storage_codec.errors.is_empty():
		for error in _storage_codec.errors:
			errors.append("Mod '%s': %s" % [mod_id, error])
		return {}
	
	return snapshot



func dispatch_event(event_name: String, data: Dictionary = {}) -> bool:
	if _phase != Phase.ACTIVE or not errors.is_empty():
		return false
	
	if not _event_handlers.has(event_name):
		return true
	
	var event_data := data.duplicate(true)
	event_data["name"] = event_name
	var lua_data := LuaUtils.to_lua_value(_lua_state, event_data)
	var callback: LuaFunction = _event_handlers[event_name]
	var owner_coroutine: LuaCoroutine = _handler_coroutines.get("event:" + event_name)
	var success := _execution_guard.invoke(
		_lua_state,
		callback,
		[lua_data],
		"%s/event:%s" % [mod_id, event_name]
	)
	if not success:
		errors.append("Lua error in mod '%s' (event '%s'): %s" % [
			mod_id, event_name, _execution_guard.last_error
		])
	
	var current_game: Variant = _lua_state.globals.rawget("game")
	if not _same_lua_object(current_game, _game_api):
		errors.append("Mod '%s' replaced the game API during event '%s'." % [mod_id, event_name])
		_lua_state.globals.rawset("game", _game_api)
	
	_validate_script_api()
	_validate_storage_api()
	_validate_remote_api()
	
	var valid := success and errors.is_empty()
	callback = null
	owner_coroutine = null
	return valid


func get_remote_interfaces() -> Array[String]:
	var result: Array[String] = []
	for interface_name in _remote_interfaces:
		result.append(interface_name)
	return result


func has_remote_method(interface_name: String, method_name: String) -> bool:
	if not _remote_interfaces.has(interface_name):
		return false
	var methods: Dictionary = _remote_interfaces[interface_name]
	return methods.has(method_name)
#endregion


#region private methods
func _register_lifecycle_handler(handler_name: String, handler: Variant) -> bool:
	if _phase != Phase.SETUP:
		errors.append("Lifecycle callbacks can only be registered during setup.")
		return false
	
	if handler != null and not handler is LuaFunction:
		errors.append("Handler '%s' must be a Lua function or nil." % handler_name)
		return false
	
	var key := "lifecycle:" + handler_name
	if handler == null:
		_lifecycle_handlers.erase(handler_name)
		_handler_coroutines.erase(key)
		return true
	
	var coroutine := _execution_guard.get_active_coroutine()
	if coroutine == null:
		errors.append("Cannot register lifecycle handler outside protected Lua execution.")
		return false
	
	_lifecycle_handlers[handler_name] = handler
	_handler_coroutines[key] = coroutine
	return true


func _same_lua_object(left: Variant, right: Variant) -> bool:
	if not left is LuaObject or not right is LuaObject:
		return false
	return left.get_lua_state() == right.get_lua_state() and left.get_pointer_value() == right.get_pointer_value()


func _validate_script_api() -> bool:
	var current_script: Variant = _lua_state.globals.rawget("script")

	if not current_script is LuaTable:
		errors.append("Mod '%s' removed or replaced the script API." % mod_id)
		return false

	if not _same_lua_object(current_script, _script_api):
		errors.append("Mod '%s' replaced the script API." % mod_id)
		return false

	for function_name in _script_functions:
		var current_function: Variant = _script_api.rawget(function_name)
		var expected_function: LuaFunction = _script_functions[function_name]

		if not current_function is LuaFunction or not _same_lua_object(current_function, expected_function):
			errors.append("Mod '%s' replaced script.%s." % [mod_id, function_name])
			return false

	return true


func _validate_setup_api() -> bool:
	if not _validate_script_api():
		return false
	
	if not _validate_remote_api():
		return false
	
	if _lua_state.globals.rawget("game") != null:
		errors.append("Mod '%s' attempted to define game during setup." % mod_id)
		return false
	
	return _validate_storage_api()


func _validate_storage_api() -> bool:
	var current: Variant = _lua_state.globals.rawget("storage")
	if not current is LuaTable or not _same_lua_object(current, _storage):
		errors.append("Mod '%s' replaced the storage table." % mod_id)
		return false
	return true


func _read_custom_event_value(value: Variant, depth: int, visited: Dictionary, counter: Array[int]) -> Variant:
	counter[0] += 1
	if depth > 32 or counter[0] > 10_000:
		errors.append("Custom event payload exceeds its size or depth limits.")
		return null
	
	if value is LuaTable:
		if value.get_lua_state() != _lua_state:
			errors.append("Custom event payload contains a foreign Lua table.")
			return null
	
		var pointer: int = value.get_pointer_value()
		if visited.has(pointer):
			errors.append("Circular tables are not supported in custom event payloads.")
			return null
	
		visited[pointer] = true
		var result: Dictionary = {}
		var source: Dictionary = value.to_dictionary()
		for key in source:
			if typeof(key) != TYPE_STRING and typeof(key) != TYPE_INT:
				errors.append("Unsupported custom event table key.")
				break
	
			result[key] = _read_custom_event_value(source[key], depth + 1, visited, counter)
			if not errors.is_empty():
				break
	
		visited.erase(pointer)
		return result
	
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			if typeof(key) != TYPE_STRING and typeof(key) != TYPE_INT:
				errors.append("Unsupported custom event dictionary key.")
				return null
	
			result[key] = _read_custom_event_value(value[key], depth + 1, visited, counter)
			if not errors.is_empty():
				return null
	
		return result
	
	if value is Array:
		var result: Array = []
		for element in value:
			result.append(_read_custom_event_value(element, depth + 1, visited, counter))
	
			if not errors.is_empty():
				return null
		return result
	
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_FLOAT:
			if is_finite(value):
				return value
	
	errors.append("Unsupported custom event payload value.")
	return null



func _validate_remote_api() -> bool:
	var current_remote: Variant = _lua_state.globals.rawget("remote")
	if not current_remote is LuaTable:
		errors.append("Mod '%s' removed or replaced the remote API." % mod_id)
		return false
	
	if not _same_lua_object(current_remote, _remote_api):
		errors.append("Mod '%s' replaced the remote API." % mod_id)
		return false
	
	for function_name in _remote_functions:
		var current_function: Variant = _remote_api.rawget(function_name)
		var expected_function: LuaFunction = _remote_functions[function_name]
		if not current_function is LuaFunction or not _same_lua_object(current_function, expected_function):
			errors.append("Mod '%s' replaced remote.%s." % [mod_id, function_name])
			return false
	
	return true
#endregion
