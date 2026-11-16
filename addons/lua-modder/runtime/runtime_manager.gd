class_name RuntimeManager extends RefCounted

enum Phase {
	CREATED,
	PREPARED,
	ACTIVE,
	FAILED,
	CLOSED
}

var errors: Array[String] = []

var _phase: int = Phase.CREATED
var _states: Dictionary[String, RuntimeState] = {}
var _ordered_ids: Array[String] = []


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

	_phase = Phase.PREPARED
	return true


func activate(game_functions: Dictionary = {}, existing_mod_ids: Array[String] = [], configuration_changes: Variant = null) -> bool:
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

	# on_init and on_load area mutually exclusive
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
	return true


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
