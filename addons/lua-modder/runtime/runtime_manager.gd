class_name RuntimeManager extends RefCounted

enum Phase {
	CREATED,
	PREPARED,
	ACTIVE,
	FAILED,
	CLOSED
}

const MAX_QUEUED_EVENTS := 2048
const MAX_EVENTS_PER_FLUSH := 4096

var errors: Array[String] = []

var _phase: int = Phase.CREATED
var _states: Dictionary[String, RuntimeState] = {}
var _ordered_ids: Array[String] = []
var _draining_events := false
var _event_queue: Array[Dictionary] = []
var _custom_event_owners: Dictionary = {}
var _remote_interface_owners: Dictionary[String, String] = {}
var _remote_call_stack: Array[String] = []
var _lifecycle_ready: Dictionary[String, bool] = {}
var _ui_bridge_factory: Callable
var _ui_bridges: Dictionary[String, UIRuntimeBridge] = {}


func prepare(mods: Array[ModManifest]) -> bool:
	if _phase != Phase.CREATED:
		errors.append("RuntimeManager can only prepare once.")
		return false
	if mods.is_empty():
		errors.append("Cannot prepare Runtime Stage without resolved mods.")
		_fail()
		return false
	var versions := _read_mod_versions(mods)
	if versions.is_empty() or not _prepare_mod_states(mods, versions) \
			or not _finish_mod_setup() or not _collect_custom_event_owners() \
			or not _collect_remote_interface_owners():
		_fail()
		return false
	_phase = Phase.PREPARED
	return true


func activate(game_functions: Dictionary = {}, existing_mod_ids: Array[String] = [],
		configuration_changes: Variant = null, saved_storage: Dictionary = {},
		api_registry: RuntimeApiRegistry = null) -> bool:
	if _phase != Phase.PREPARED:
		errors.append("Runtime Stage must be prepared before activation.")
		return false
	if not _validate_activation_arguments(game_functions, configuration_changes, api_registry):
		return false
	if not _activate_mod_states(game_functions, api_registry) \
			or not _restore_existing_storage(existing_mod_ids, saved_storage) \
			or not _run_initial_lifecycle(existing_mod_ids) \
			or not _run_configuration_lifecycle(configuration_changes):
		_fail()
		return false
	_phase = Phase.ACTIVE
	return _flush_event_queue()


func snapshot_storage() -> Dictionary:
	if _phase != Phase.ACTIVE:
		errors.append("Runtime Stage must be active to snapshot storage.")
		return {}
	var result: Dictionary = {}
	for mod_id in _ordered_ids:
		var state: RuntimeState = _states[mod_id]
		var snapshot := state.snapshot_storage()
		if snapshot.is_empty():
			errors.append_array(state.get_errors())
			return {}
		result[mod_id] = snapshot
	return result


func emit_event(event_name: String, data: Dictionary = {}) -> bool:
	if _phase != Phase.ACTIVE:
		errors.append("Runtime Stage must be active to emit events.")
		return false
	if not _queue_event(event_name, data, ""):
		return false
	return _flush_event_queue()


func configure_ui_bridge(factory: Callable) -> bool:
	if _phase != Phase.CREATED:
		errors.append("UI Bridge must be configured before Runtime preparation.")
		return false
	if not factory.is_valid():
		errors.append("Invalid UI Bridge factory.")
		return false
	_ui_bridge_factory = factory
	return true


func get_phase() -> int:
	return _phase


func get_mod_ids() -> Array[String]:
	return _ordered_ids.duplicate()


func get_state(mod_id: String) -> RuntimeState:
	if _phase != Phase.ACTIVE:
		return null
	return _states.get(mod_id)


func get_remote_interfaces() -> Array[String]:
	var result: Array[String] = []
	if _phase != Phase.PREPARED and _phase != Phase.ACTIVE:
		return result
	for interface_name in _remote_interface_owners:
		result.append(interface_name)
	return result


func get_remote_interface_owner(interface_name: String) -> String:
	if _phase != Phase.PREPARED and _phase != Phase.ACTIVE:
		return ""
	return _remote_interface_owners.get(interface_name, "")


func has_remote_interface(interface_name: String) -> bool:
	return not get_remote_interface_owner(interface_name).is_empty()


func has_remote_method(interface_name: String, method_name: String) -> bool:
	var owner_id := get_remote_interface_owner(interface_name)
	if owner_id.is_empty():
		return false
	var state: RuntimeState = _states.get(owner_id)
	if state == null:
		return false
	return state.has_remote_method(interface_name, method_name)


func get_errors() -> Array[String]:
	return errors.duplicate()


func close() -> void:
	_release_states()
	_phase = Phase.CLOSED


#region private methods
func _read_mod_versions(mods: Array[ModManifest]) -> Dictionary:
	var versions: Dictionary = {}
	for manifest in mods:
		if manifest == null or manifest.id.strip_edges().is_empty():
			errors.append("Runtime Stage received an invalid mod manifest.")
			return {}
		if versions.has(manifest.id):
			errors.append("Runtime Stage received duplicate mod ID '%s'." % manifest.id)
			return {}
		versions[manifest.id] = manifest.version
	return versions


func _prepare_mod_states(mods: Array[ModManifest], versions: Dictionary) -> bool:
	var loader := RuntimeLoader.new()
	for manifest in mods:
		if not loader.has_control(manifest):
			continue
		if not _prepare_one_mod(manifest, versions, loader):
			return false
	return true


func _prepare_one_mod(manifest: ModManifest, versions: Dictionary, loader: RuntimeLoader) -> bool:
	var state := RuntimeState.new(manifest.id)
	_states[manifest.id] = state
	_ordered_ids.append(manifest.id)
	if not state.set_custom_event_sink(Callable(self, "_enqueue_custom_event")) \
			or not state.set_remote_sinks(Callable(self, "_invoke_remote"), Callable(self, "_has_remote")) \
			or not state.start(versions):
		errors.append_array(state.get_errors())
		return false
	var source := loader.read_control(manifest)
	if not loader.errors.is_empty():
		errors.append_array(loader.errors)
		return false
	if not state.execute(source, "", loader.get_control_path(manifest)):
		errors.append_array(state.get_errors())
		return false
	return true


func _finish_mod_setup() -> bool:
	for mod_id in _ordered_ids:
		var state: RuntimeState = _states[mod_id]
		if not state.finish_setup():
			errors.append_array(state.get_errors())
			errors.append("Failed to finish Runtime setup for mod '%s'." % mod_id)
			return false
	return true


func _collect_custom_event_owners() -> bool:
	for mod_id in _ordered_ids:
		var state: RuntimeState = _states[mod_id]
		for event_name in state.get_custom_events():
			if _custom_event_owners.has(event_name):
				errors.append("Duplicate custom event '%s'." % event_name)
				return false
			_custom_event_owners[event_name] = mod_id
	return true


func _collect_remote_interface_owners() -> bool:
	for mod_id in _ordered_ids:
		var state: RuntimeState = _states[mod_id]
		for interface_name in state.get_remote_interfaces():
			if not interface_name.begins_with(mod_id + ":"):
				errors.append("Mod '%s' registered a remote interface outside its namespace: '%s'." % [mod_id, interface_name])
				return false
			if _remote_interface_owners.has(interface_name):
				errors.append("Duplicate remote interface '%s'." % interface_name)
				return false
			_remote_interface_owners[interface_name] = mod_id
	return true


func _validate_activation_arguments(game_functions: Dictionary, changes: Variant, api: RuntimeApiRegistry) -> bool:
	for function_name in game_functions:
		if typeof(function_name) != TYPE_STRING or String(function_name).strip_edges().is_empty():
			errors.append("Runtime API function names must be non-empty strings.")
			return false
		var callback: Variant = game_functions[function_name]
		if not callback is Callable or not callback.is_valid():
			errors.append("Invalid runtime API function '%s'." % function_name)
			return false
	if api != null and not _validate_registered_api(game_functions, api):
		return false
	if changes != null and typeof(changes) != TYPE_DICTIONARY:
		errors.append("Configuration changes must be a Dictionary or null.")
		return false
	return true


func _validate_registered_api(game_functions: Dictionary, api: RuntimeApiRegistry) -> bool:
	if not api.errors.is_empty():
		errors.append("Runtime API registry contains registration errors: %s" % str(api.errors))
		return false
	var registered_functions := api.get_functions()
	for full_path in registered_functions:
		var callback: Callable = registered_functions[full_path]
		if not callback.is_valid():
			errors.append("Invalid registered runtime API function '%s'." % full_path)
			return false
		for function_name in game_functions:
			if full_path == function_name or full_path.begins_with(String(function_name) + "."):
				errors.append("Runtime API path '%s' conflicts with legacy function '%s'." % [full_path, function_name])
				return false
	return true



func _activate_mod_states(game_functions: Dictionary, api: RuntimeApiRegistry) -> bool:
	for mod_id in _ordered_ids:
		var state: RuntimeState = _states[mod_id]
		var mod_api := api
		if _ui_bridge_factory.is_valid():
			var bridge: Variant = _ui_bridge_factory.call(mod_id, state)
			if not bridge is UIRuntimeBridge:
				errors.append("Invalid UI Bridge for mod '%s'." % mod_id)
				return false
			_ui_bridges[mod_id] = bridge
			mod_api = _build_mod_api(api, bridge)
			if mod_api == null:
				return false
		if not state.activate(game_functions, mod_api):
			errors.append_array(state.get_errors())
			return false
	return true


func _build_mod_api(base: RuntimeApiRegistry, bridge: UIRuntimeBridge) -> RuntimeApiRegistry:
	var result := RuntimeApiRegistry.new()
	if base != null:
		var functions := base.get_functions()
		for full_path in functions:
			var separator := full_path.rfind(".")
			var _namespace := ""
			var function_name := full_path
			if separator >= 0:
				_namespace = full_path.substr(0, separator)
				function_name = full_path.substr(separator + 1)
			if not result.register_function(_namespace, function_name, functions[full_path]):
				errors.append_array(result.errors)
				return null
	for function_name in bridge.get_api_functions():
		if not result.register_function(
			"ui", function_name, bridge.get_api_functions()[function_name]
		):
			errors.append_array(result.errors)
			return null
	return result


func _restore_existing_storage(existing_ids: Array[String], saved: Dictionary) -> bool:
	for mod_id in _ordered_ids:
		if mod_id not in existing_ids:
			continue
		var snapshot: Variant = saved.get(mod_id, {})
		if not snapshot is Dictionary:
			errors.append("Invalid storage snapshot for mod '%s'." % mod_id)
			return false
		var state: RuntimeState = _states[mod_id]
		if not state.restore_storage(snapshot):
			errors.append_array(state.get_errors())
			return false
	return true


func _run_initial_lifecycle(existing_ids: Array[String]) -> bool:
	for mod_id in _ordered_ids:
		var state: RuntimeState = _states[mod_id]
		var handler := "on_load" if mod_id in existing_ids else "on_init"
		if not state.run_lifecycle(handler):
			errors.append_array(state.get_errors())
			return false
		_lifecycle_ready[mod_id] = true
	return true


func _run_configuration_lifecycle(changes: Variant) -> bool:
	if changes == null:
		return true
	for mod_id in _ordered_ids:
		var state: RuntimeState = _states[mod_id]
		if not state.run_lifecycle("on_configuration_changed", changes):
			errors.append_array(state.get_errors())
			return false
	return true



func _fail() -> void:
	_release_states()
	_phase = Phase.FAILED


func _release_states() -> void:
	for bridge in _ui_bridges.values():
		bridge.close()
	_ui_bridges.clear()
	
	for state in _states.values():
		state.close()
	_states.clear()
	
	_ordered_ids.clear()
	_custom_event_owners.clear()
	_remote_interface_owners.clear()
	_remote_call_stack.clear()
	_lifecycle_ready.clear()
	_event_queue.clear()
	_draining_events = false


func _is_valid_event_value(value: Variant, depth: int, visited: Array[int]) -> bool:
	if depth > 32:
		return false
	visited[0] += 1
	if visited[0] > 10_000:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for element in value:
				if not _is_valid_event_value(element, depth + 1, visited):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if typeof(key) != TYPE_STRING and typeof(key) != TYPE_INT:
					return false
				if not _is_valid_event_value(value[key], depth + 1, visited):
					return false
			return true
	return false


func _enqueue_custom_event(mod_id: String, event_name: String, data: Dictionary) -> bool:
	if _phase != Phase.PREPARED and _phase != Phase.ACTIVE:
		errors.append("Custom events cannot be raised in this runtime phase.")
		return false
	
	if _custom_event_owners.get(event_name, "") != mod_id:
		errors.append("Mod '%s' does not own custom event '%s'." % [mod_id, event_name])
		return false
	
	return _queue_event(event_name, data, mod_id)


func _queue_event(event_name: String, data: Dictionary, raised_by: String) -> bool:
	if event_name.strip_edges().is_empty():
		errors.append("Event name cannot be empty.")
		return false
	
	if data.has("name") or data.has("mod_name"):
		errors.append("Event payload contains reserved fields.")
		return false
	
	var visited: Array[int] = [0]
	if not _is_valid_event_value(data, 0, visited):
		errors.append("Event '%s' contains unsupported data." % event_name)
		return false
	
	if _event_queue.size() >= MAX_QUEUED_EVENTS:
		errors.append("Runtime event queue limit exceeded.")
		return false
	
	_event_queue.append({
		"name": event_name,
		"data": data.duplicate(true),
		"raised_by": raised_by
	})
	
	return true


func _flush_event_queue() -> bool:
	if _draining_events:
		return true
	_draining_events = true
	var processed := 0
	while not _event_queue.is_empty():
		processed += 1
		if processed > MAX_EVENTS_PER_FLUSH:
			errors.append("Runtime event dispatch limit exceeded.")
			_draining_events = false
			_fail()
			return false
		if not _dispatch_queued_event(_event_queue.pop_front()):
			_draining_events = false
			_fail()
			return false
	_draining_events = false
	return true


func _dispatch_queued_event(queued: Dictionary) -> bool:
	var event_name: String = queued["name"]
	var event_data: Dictionary = queued["data"]
	var raised_by: String = queued["raised_by"]
	if not raised_by.is_empty():
		event_data["mod_name"] = raised_by
	for mod_id in _ordered_ids:
		var state: RuntimeState = _states[mod_id]
		if not state.dispatch_event(event_name, event_data):
			errors.append_array(state.get_errors())
			return false
	return true


func _has_remote(interface_name: String, method_name: String) -> bool:
	if method_name.is_empty():
		return has_remote_interface(interface_name)
	return has_remote_method(interface_name, method_name)


func _invoke_remote(caller_id: String, interface_name: String, method_name: String, arguments: Array) -> Dictionary:
	if _phase != Phase.PREPARED and _phase != Phase.ACTIVE:
		return {
			"ok": false,
			"error": "Runtime Stage is not ready for remote calls."
		}
	
	if not _states.has(caller_id):
		return {
			"ok": false,
			"error": "Unknown remote caller '%s'." % caller_id
		}
	
	if not has_remote_method(interface_name, method_name):
		return {
			"ok": false,
			"error": "Unknown remote function '%s.%s'." % [interface_name, method_name]
		}
	
	var owner_id := get_remote_interface_owner(interface_name)
	var root_call := _remote_call_stack.is_empty()
	if root_call:
		_remote_call_stack.append(caller_id)
	elif _remote_call_stack.back() != caller_id:
		return {
			"ok": false,
			"error": "Invalid remote call chain."
		}
	
	if owner_id in _remote_call_stack:
		if root_call:
			_remote_call_stack.pop_back()
		return {
			"ok": false,
			"error": "Recursive remote call involving mod '%s'." % owner_id
		}
	
	if not _lifecycle_ready.get(owner_id, false):
		if root_call:
			_remote_call_stack.pop_back()
		return {
			"ok": false,
			"error": "Remote interface '%s' belongs to a mod that has not completed initialization." % interface_name
		}
	
	_remote_call_stack.append(owner_id)
	var target: RuntimeState = _states[owner_id]
	var response := target.invoke_remote(interface_name, method_name, arguments)
	_remote_call_stack.pop_back()
	if root_call:
		_remote_call_stack.pop_back()
	return response
#endregion
