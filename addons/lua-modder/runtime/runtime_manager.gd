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
var _custom_event_owners: Dictionary = {}
var _event_queue: Array[Dictionary] = []
var _draining_events := false

func prepare(mods: Array[ModManifest]) -> bool:
	if _phase != Phase.CREATED:
		errors.append("RuntimeManager can only prepare once.")
		return false
	
	if mods.is_empty():
		errors.append("Cannot prepare Runtime Stage without resolved mods.")
		_fail()
		return false
	
	var versions: Dictionary = {}
	for manifest in mods:
		if manifest == null or manifest.id.strip_edges().is_empty():
			errors.append("Runtime Stage received an invalid mod manifest.")
			_fail()
			return false
	
		if versions.has(manifest.id):
			errors.append("Runtime Stage received duplicate mod ID '%s'." % manifest.id)
			_fail()
			return false
		versions[manifest.id] = manifest.version
	
	var loader := RuntimeLoader.new()
	for manifest in mods:
		if not loader.has_control(manifest):
			continue
	
		var state := RuntimeState.new(manifest.id)
		_states[manifest.id] = state
		_ordered_ids.append(manifest.id)
	
		if not state.set_custom_event_sink(Callable(self, "_enqueue_custom_event")):
			errors.append_array(state.get_errors())
			_fail()
			return false
	
		if not state.start(versions):
			errors.append_array(state.get_errors())
			_fail()
			return false
	
		var source := loader.read_control(manifest)
		if not loader.errors.is_empty():
			errors.append_array(loader.errors)
			_fail()
			return false
	
		if not state.execute_control(source, loader.get_control_path(manifest)):
			errors.append_array(state.get_errors())
			_fail()
			return false
	
	for mod_id in _ordered_ids:
		var state: RuntimeState = _states[mod_id]
		if not state.finish_setup():
			errors.append_array(state.get_errors())
			errors.append("Failed to finish Runtime setup for mod '%s'." % mod_id)
			_fail()
			return false
	
	for mod_id in _ordered_ids:
		var state: RuntimeState = _states[mod_id]
		for event_name in state.get_custom_events():
			if _custom_event_owners.has(event_name):
				errors.append("Duplicate custom event '%s'." % event_name)
				_fail()
				return false
			_custom_event_owners[event_name] = mod_id
	
	_phase = Phase.PREPARED
	return true


func activate(game_functions: Dictionary = {}, existing_mod_ids: Array[String] = [], configuration_changes: Variant = null, saved_storage: Dictionary = {}) -> bool:
	if _phase != Phase.PREPARED:
		errors.append("Runtime Stage must be prepared before activation.")
		return false
	
	# Validate the entire consumer API before exposing it to any mod.
	for function_name in game_functions:
		if typeof(function_name) != TYPE_STRING or String(function_name).strip_edges().is_empty():
			errors.append("Runtime API function names must be non-empty strings.")
			return false
	
		var callback: Variant = game_functions[function_name]
		if not callback is Callable or not callback.is_valid():
			errors.append("Invalid runtime API function '%s'." % function_name)
			return false

	if configuration_changes != null and typeof(configuration_changes) != TYPE_DICTIONARY:
		errors.append("Configuration changes must be a Dictionary or null.")
		return false
	
	for mod_id in _ordered_ids:
		var state: RuntimeState = _states[mod_id]
		if not state.activate(game_functions):
			errors.append_array(state.get_errors())
			_fail()
			return false
	
	for mod_id in _ordered_ids:
		if mod_id not in existing_mod_ids:
			continue
	
		var snapshot: Variant = saved_storage.get(mod_id, {})
		if not snapshot is Dictionary:
			errors.append("Invalid storage snapshot for mod '%s'." % mod_id)
			_fail()
			return false
	
		var state: RuntimeState = _states[mod_id]
		if not state.restore_storage(snapshot):
			errors.append_array(state.get_errors())
			_fail()
			return false
	
	# on_init and on_load are mutually exclusive
	for mod_id in _ordered_ids:
		var state: RuntimeState = _states[mod_id]
		var callback_name := "on_load" if mod_id in existing_mod_ids else "on_init"
		if not state.run_lifecycle(callback_name):
			errors.append_array(state.get_errors())
			_fail()
			return false
	
	if configuration_changes != null:
		for mod_id in _ordered_ids:
			var state: RuntimeState = _states[mod_id]
			if not state.run_lifecycle("on_configuration_changed", configuration_changes):
				errors.append_array(state.get_errors())
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


func get_phase() -> int:
	return _phase


func get_mod_ids() -> Array[String]:
	return _ordered_ids.duplicate()


func get_state(mod_id: String) -> RuntimeState:
	# Do not allow callers to bypass the manager's activation barrier.
	if _phase != Phase.ACTIVE:
		return null
	return _states.get(mod_id)


func get_errors() -> Array[String]:
	return errors.duplicate()


func close() -> void:
	_release_states()
	_phase = Phase.CLOSED


func _fail() -> void:
	_release_states()
	_phase = Phase.FAILED


func _release_states() -> void:
	for state in _states.values():
		state.close()
	
	_states.clear()
	_ordered_ids.clear()
	_custom_event_owners.clear()
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
	
		var queued: Dictionary = _event_queue.pop_front()
		var event_name: String = queued["name"]
		var event_data: Dictionary = queued["data"]
		var raised_by: String = queued["raised_by"]
		if not raised_by.is_empty():
			event_data["mod_name"] = raised_by
	
		for mod_id in _ordered_ids:
			var state: RuntimeState = _states[mod_id]
			if not state.dispatch_event(event_name, event_data):
				errors.append_array(state.get_errors())
				_draining_events = false
				_fail()
				return false
	
	_draining_events = false
	return true
