class_name RuntimeState extends State

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
const MAX_REMOTE_ARGUMENTS := 32
const REMOTE_CALL_FACTORY := """
return function(native_call)
	assert(type(native_call) == "function", "Invalid native remote function")

	return function(interface_name, method_name, ...)
		return native_call(interface_name, method_name, table.pack(...))
	end
end
"""


var mod_id: String

var _phase: int = Phase.CREATED
var _script_api: LuaTable
var _game_api: LuaTable
var _game_api_entries: Array[Dictionary] = []
var _script_functions: Dictionary = {}
var _lifecycle_handlers: Dictionary = {}
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
var _remote_native_call: LuaFunction
var _remote_call_sink: Callable
var _remote_has_sink: Callable
var _ui_callbacks: Dictionary[int, LuaFunction] = {}
var _ui_coroutines: Dictionary[int, LuaCoroutine] = {}
var _ui_pending_release: Array[int] = []
var _next_ui_callback_id: int = 1

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
	_lua_state.open_libraries(LuaState.LUA_BASE | LuaState.LUA_STRING | LuaState.LUA_TABLE | LuaState.LUA_MATH)
	LuaExecutionGuard.restrict_base_functions(_lua_state)
	_storage = _lua_state.create_table()
	_lua_state.globals["storage"] = _storage
	_create_script_api()
	if not _create_remote_api():
		return false

	_lua_state.globals["mods"] = LuaUtils.to_lua_value(_lua_state, mod_versions)
	_lua_state.globals["game"] = null
	_phase = Phase.SETUP
	return true


func execute(source: String, _mod_id: String = "", chunk_name: String = "") -> bool:
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


func activate(game_functions: Dictionary = {}, api_registry: RuntimeApiRegistry = null) -> bool:
	if _phase != Phase.PREPARED:
		errors.append("Mod '%s' cannot activate before setup is complete." % mod_id)
		return false
	if not _validate_activation_api(game_functions, api_registry):
		return false

	_game_api = _lua_state.create_table()
	_game_api_entries.clear()
	_add_legacy_game_functions(game_functions)
	if api_registry != null:
		_add_namespaced_game_functions(api_registry.get_functions())

	_lua_state.globals.rawset("game", _game_api)
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
	var before: Dictionary = {}
	if is_load:
		before = _storage_codec.capture(_lua_state, _storage)
		if not _storage_codec.errors.is_empty():
			errors.append_array(_storage_codec.errors)
			return false
		_lua_state.globals.rawset("game", null)
	_inside_on_load = is_load

	var arguments: Array = []
	if handler_name == "on_configuration_changed":
		arguments.append(LuaUtils.to_lua_value(_lua_state, data))
	var callback: LuaFunction = _lifecycle_handlers[handler_name]
	var success := _execution_guard.invoke(_lua_state, callback, arguments, "%s/%s" % [mod_id, handler_name])
	_inside_on_load = false

	_restore_game_after_lifecycle(is_load, handler_name)
	if not success:
		errors.append("Lua error in mod '%s' (%s): %s" % [mod_id, handler_name, _execution_guard.last_error])
	_validate_runtime_apis()
	if is_load:
		_validate_unmodified_storage(before)
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
	
	_ui_callbacks.clear() # it needs to happen BEFORE _handler_coroutines.clear()
	_ui_coroutines.clear()
	_ui_pending_release.clear()
	_next_ui_callback_id = 1
	
	_handler_coroutines.clear()
	_remote_coroutines.clear() # it needs to happen AFTER _remote_interfaces.clear()
	
	_script_functions.clear()
	_remote_functions.clear()
	_remote_native_call = null
	
	_custom_events.clear()
	_custom_event_sink = Callable()
	_remote_call_sink = Callable()
	_remote_has_sink = Callable()
	
	_script_api = null
	_remote_api = null
	_storage = null
	_game_api_entries.clear() # it needs to be BEFORE _game_api = null
	_game_api = null
	
	_storage_codec.release() # it needs to be BEFORE _lua_state = null
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


func _lua_remote_has_interface(interface_name: Variant, method_name: Variant = null) -> bool:
	if _phase != Phase.ACTIVE or _inside_on_load:
		errors.append("Mod '%s' cannot query remote interfaces in this phase." % mod_id)
		return false
	
	if typeof(interface_name) != TYPE_STRING:
		errors.append("Remote interface name must be a string.")
		return false
	
	if method_name != null and typeof(method_name) != TYPE_STRING:
		errors.append("Remote method name must be a string.")
		return false
	
	if not _remote_has_sink.is_valid():
		errors.append("Remote registry is unavailable for mod '%s'." % mod_id)
		return false
	
	return _remote_has_sink.call(
		String(interface_name),
		String(method_name) if method_name != null else ""
	)


func _lua_remote_call(interface_name: Variant, method_name: Variant, argument_table: Variant) -> Variant:
	if _phase != Phase.ACTIVE or _inside_on_load:
		errors.append("Mod '%s' cannot call remote interfaces in this phase." % mod_id)
		return null
	
	if typeof(interface_name) != TYPE_STRING or typeof(method_name) != TYPE_STRING:
		errors.append("Remote call requires string interface and method names.")
		return null
	
	if not argument_table is LuaTable or argument_table.get_lua_state() != _lua_state:
		errors.append("Invalid remote argument container for mod '%s'." % mod_id)
		return null
	
	var count: Variant = LuaUtils.normalize_integer(argument_table.rawget("n"))
	if typeof(count) != TYPE_INT or count < 0 or count > MAX_REMOTE_ARGUMENTS:
		errors.append("Invalid remote argument count or limit exceeded.")
		return null
	
	var arguments: Array = []
	var visited: Dictionary = {}
	var counter: Array[int] = [0]
	
	for i in range(1, int(count) + 1):
		var value: Variant = argument_table.rawget(i)
		var converted: Variant = _read_custom_event_value(value, 0, visited, counter)
	
		if not errors.is_empty():
			return null
	
		arguments.append(converted)
	if not _remote_call_sink.is_valid():
		errors.append("Remote dispatcher is unavailable for mod '%s'." % mod_id)
		return null
	
	var response: Variant = _remote_call_sink.call(
		mod_id,
		String(interface_name),
		String(method_name),
		arguments
	)
	
	if not response is Dictionary:
		errors.append("Remote dispatcher returned an invalid response.")
		return null
	
	if not response.get("ok", false):
		errors.append("Remote call failed: %s" % response.get("error", "Unknown error."))
		return null
	
	return LuaUtils.to_lua_value(_lua_state, response.get("value"))
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
	if not LuaUtils.same_lua_object(_lua_state, current_game, _game_api):
		errors.append("Mod '%s' replaced the game API during event '%s'." % [mod_id, event_name])
		_lua_state.globals.rawset("game", _game_api)
	
	_validate_runtime_apis()
	
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


func set_remote_sinks(call_sink: Callable, has_sink: Callable) -> bool:
	if _phase != Phase.CREATED or not call_sink.is_valid() or not has_sink.is_valid():
		errors.append("Invalid remote API sinks for mod '%s'." % mod_id)
		return false
	_remote_call_sink = call_sink
	_remote_has_sink = has_sink
	return true


func invoke_remote(interface_name: String, method_name: String, arguments: Array) -> Dictionary:
	if _phase != Phase.ACTIVE or not errors.is_empty():
		return {
			"ok": false,
			"error": "Target mod '%s' is not ready." % mod_id
		}
	
	if not has_remote_method(interface_name, method_name):
		return {
			"ok": false,
			"error": "Unknown remote function '%s.%s'." % [interface_name, method_name]
		}
	
	var methods: Dictionary = _remote_interfaces[interface_name]
	var callback: LuaFunction = methods[method_name]
	
	# preserve original coroutine
	var origin: LuaCoroutine = _remote_coroutines[interface_name]
	var lua_arguments: Array = []
	for argument in arguments:
		lua_arguments.append(LuaUtils.to_lua_value(_lua_state, argument))
	
	var success := _execution_guard.invoke(
		_lua_state,
		callback,
		lua_arguments,
		"%s/remote:%s.%s" % [mod_id, interface_name, method_name],
		Callable(self, "_serialize_remote_result")
	)
	
	if not success:
		errors.append("Lua remote error in mod '%s': %s" % [
			mod_id, _execution_guard.last_error
		])
	
	var current_game: Variant = _lua_state.globals.rawget("game")
	if not LuaUtils.same_lua_object(_lua_state, current_game, _game_api):
		errors.append("Mod '%s' replaced the game API during remote call." % mod_id)
		_lua_state.globals.rawset("game", _game_api)
	
	_validate_runtime_apis()
	
	var result: Variant = _execution_guard.last_result
	var valid := success and errors.is_empty()
	callback = null
	origin = null
	if not valid:
		return {"ok": false, "error": str(errors)}
	return {"ok": true, "value": result}
#endregion


#region private methods
func _create_script_api() -> void:
	_script_api = _lua_state.create_table()
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


func _create_remote_api() -> bool:
	_remote_api = _lua_state.create_table()
	_remote_functions = {
		"add_interface": _lua_state.create_function(_lua_remote_add_interface),
		"has_interface": _lua_state.create_function(_lua_remote_has_interface)
	}
	var wrapper := _create_remote_call_wrapper()
	if wrapper == null:
		return false
	_remote_functions["call"] = wrapper
	for function_name in _remote_functions:
		_remote_api.rawset(function_name, _remote_functions[function_name])
	_lua_state.globals.rawset("remote", _remote_api)
	return true


func _create_remote_call_wrapper() -> LuaFunction:
	_remote_native_call = _lua_state.create_function(_lua_remote_call)
	if _remote_native_call == null:
		errors.append("Failed to create native remote function for mod '%s'." % mod_id)
		return null
	var factory_result: Variant = _lua_state.do_string(REMOTE_CALL_FACTORY)
	if factory_result is LuaError:
		errors.append("Failed to load remote call factory for mod '%s': %s" % [mod_id, factory_result])
		return null
	if not factory_result is LuaFunction:
		errors.append("Remote call factory did not return a LuaFunction for mod '%s'." % mod_id)
		return null
	var factory: LuaFunction = factory_result
	var result: Variant = factory.invokev([_remote_native_call])
	if result is LuaError:
		errors.append("Failed to create remote call wrapper for mod '%s': %s" % [mod_id, result])
		return null
	if not result is LuaFunction:
		errors.append("Remote call wrapper is not a LuaFunction for mod '%s'." % mod_id)
		return null
	return result


func _validate_activation_api(game_functions: Dictionary, registry: RuntimeApiRegistry) -> bool:
	for function_name in game_functions:
		if typeof(function_name) != TYPE_STRING or String(function_name).is_empty():
			errors.append("Runtime API function names must be non-empty strings.")
			return false
		var callback: Variant = game_functions[function_name]
		if not callback is Callable or not callback.is_valid():
			errors.append("Invalid runtime API function '%s'." % function_name)
			return false
	
	if registry == null:
		return true
	if not registry.errors.is_empty():
		errors.append("Runtime API registry contains registration errors: %s" % str(registry.errors))
		return false
	for full_path in registry.get_functions():
		for function_name in game_functions:
			if full_path == function_name or full_path.begins_with(String(function_name) + "."):
				errors.append("Runtime API path '%s' conflicts with legacy function '%s'." % [full_path, function_name])
				return false
	return true


func _add_legacy_game_functions(functions: Dictionary) -> void:
	for function_name in functions:
		var callback := _lua_state.create_function(functions[function_name])
		_game_api.rawset(function_name, callback)
		_game_api_entries.append({
			"parent": _game_api, "key": function_name,
			"expected": callback, "path": function_name
		})


func _add_namespaced_game_functions(functions: Dictionary[String, Callable]) -> void:
	var tables: Dictionary[String, LuaTable] = {}
	for full_path in functions:
		var segments := full_path.split(".")
		var parent: LuaTable = _game_api
		var _namespace := ""
		for i in range(segments.size() - 1):
			var segment := segments[i]
			_namespace = segment if _namespace.is_empty() else _namespace + "." + segment
			if not tables.has(_namespace):
				var nested := _lua_state.create_table()
				parent.rawset(segment, nested)
				tables[_namespace] = nested
				_game_api_entries.append({
					"parent": parent, "key": segment,
					"expected": nested, "path": _namespace
				})
			parent = tables[_namespace]
		var method_name := segments[segments.size() - 1]
		var callback := _lua_state.create_function(functions[full_path])
		parent.rawset(method_name, callback)
		_game_api_entries.append({
			"parent": parent, "key": method_name,
			"expected": callback, "path": full_path
		})


func _restore_game_after_lifecycle(is_load: bool, handler: String) -> void:
	if is_load:
		if _lua_state.globals.rawget("game") != null:
			errors.append("Mod '%s' defined game during on_load." % mod_id)
		_lua_state.globals.rawset("game", _game_api)
		return
	var current_game: Variant = _lua_state.globals.rawget("game")
	if not LuaUtils.same_lua_object(_lua_state, current_game, _game_api):
		errors.append("Mod '%s' replaced the game API during %s." % [mod_id, handler])
		_lua_state.globals.rawset("game", _game_api)


func _validate_runtime_apis() -> void:
	_validate_script_api()
	_validate_remote_api()
	_validate_game_api_members()
	_validate_storage_api()


func _validate_unmodified_storage(before: Dictionary) -> void:
	var after := _storage_codec.capture(_lua_state, _storage)
	if not _storage_codec.errors.is_empty():
		errors.append_array(_storage_codec.errors)
	elif before != after:
		errors.append("Mod '%s' modified storage during on_load." % mod_id)


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


func _validate_script_api() -> bool:
	var current_script: Variant = _lua_state.globals.rawget("script")
	if not current_script is LuaTable:
		errors.append("Mod '%s' removed or replaced the script API." % mod_id)
		return false
	
	if not LuaUtils.same_lua_object(_lua_state, current_script, _script_api):
		errors.append("Mod '%s' replaced the script API." % mod_id)
		return false
	
	for function_name in _script_functions:
		var current_function: Variant = _script_api.rawget(function_name)
		var expected_function: LuaFunction = _script_functions[function_name]
		if not current_function is LuaFunction or not LuaUtils.same_lua_object(_lua_state, current_function, expected_function):
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
	if not current is LuaTable or not LuaUtils.same_lua_object(_lua_state, current, _storage):
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
	
	if not LuaUtils.same_lua_object(_lua_state, current_remote, _remote_api):
		errors.append("Mod '%s' replaced the remote API." % mod_id)
		return false
	
	for function_name in _remote_functions:
		var current_function: Variant = _remote_api.rawget(function_name)
		var expected_function: LuaFunction = _remote_functions[function_name]
		if not current_function is LuaFunction or not LuaUtils.same_lua_object(_lua_state, current_function, expected_function):
			errors.append("Mod '%s' replaced remote.%s." % [mod_id, function_name])
			return false
	
	return true


func _serialize_remote_result(value: Variant) -> Variant:
	var visited: Dictionary = {}
	var counter: Array[int] = [0]
	return _read_custom_event_value(value, 0, visited, counter)


func _validate_game_api_members() -> bool:
	for entry in _game_api_entries:
		var parent: LuaTable = entry["parent"]
		var key: String = entry["key"]
		var expected: LuaObject = entry["expected"]
		var full_path: String = entry["path"]
		var current: Variant = parent.rawget(key)
		if not LuaUtils.same_lua_object(_lua_state, current, expected):
			errors.append("Mod '%s' replaced game.%s." % [mod_id, full_path])
			return false
	
	return true
#endregion


#region UI callbacks
func retain_ui_callback(callback: Variant) -> int:
	if _phase != Phase.ACTIVE or _inside_on_load:
		errors.append("UI callbacks cannot be registered in the current phase.")
		return 0
	
	if not callback is LuaFunction or callback.get_lua_state() != _lua_state:
		errors.append("Invalid or foreign UI callback in mod '%s'." % mod_id)
		return 0
	
	var coroutine := _execution_guard.get_active_coroutine()
	if coroutine == null:
		errors.append("UI callbacks must be registered during protected Lua execution.")
		return 0
	
	var callback_id := _next_ui_callback_id
	_next_ui_callback_id += 1
	_ui_callbacks[callback_id] = callback
	_ui_coroutines[callback_id] = coroutine
	return callback_id


func invoke_ui_callback(callback_id: int, arguments: Array = [], expect_result: bool = false) -> Dictionary:
	if _phase != Phase.ACTIVE or _inside_on_load or not _ui_callbacks.has(callback_id):
		return {"ok": false, "error": "UI callback is unavailable."}
	
	if not errors.is_empty():
		return {"ok": false, "error": "RuntimeState contains errors."}
	
	var callback: LuaFunction = _ui_callbacks[callback_id]
	var origin: LuaCoroutine = _ui_coroutines[callback_id]
	var lua_arguments: Array = []
	for argument in arguments:
		lua_arguments.append(LuaUtils.to_lua_value(_lua_state, argument))
	var success := _execution_guard.invoke(
		_lua_state,
		callback,
		lua_arguments,
		"%s/ui:%d" % [mod_id, callback_id],
		Callable(self, "_serialize_remote_result")
	)
	if not success:
		errors.append("Lua UI callback error in mod '%s': %s" % [
			mod_id, _execution_guard.last_error
		])
	_validate_runtime_apis()
	var result: Variant = _execution_guard.last_result
	var valid := success and errors.is_empty()
	callback = null
	origin = null
	_flush_ui_callback_releases()
	if not valid:
		return {"ok": false, "error": str(errors)}
	return {"ok": true, "value": result if expect_result else null}


func release_ui_callback(callback_id: int) -> void:
	if not _ui_callbacks.has(callback_id):
		return
	
	if _execution_guard.get_active_coroutine() != null:
		if not _ui_pending_release.has(callback_id):
			_ui_pending_release.append(callback_id)
		return
	
	_ui_callbacks.erase(callback_id)
	_ui_coroutines.erase(callback_id)


func _flush_ui_callback_releases() -> void:
	if _execution_guard.get_active_coroutine() != null:
		return
	
	for callback_id in _ui_pending_release:
		_ui_callbacks.erase(callback_id)
		_ui_coroutines.erase(callback_id)
	
	_ui_pending_release.clear()
#endregion
