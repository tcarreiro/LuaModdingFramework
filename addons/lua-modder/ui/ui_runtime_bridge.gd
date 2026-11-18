class_name UIRuntimeBridge extends RefCounted

const MAX_COMPONENTS := 256
const MAX_VALUE_DEPTH := 8
const MAX_VALUE_ENTRIES := 512
const MAX_STRING_LENGTH := 4096

var errors: Array[String] = []

var _registry: UIComponentRegistry
var _mount: Control
var _state: RuntimeState

var _instances: Dictionary[int, UIComponentInstance] = {}
var _events: Dictionary[int, Dictionary] = {}
var _hooks: Dictionary[int, Dictionary] = {}
var _next_handle := 1


func setup(registry: UIComponentRegistry, mount: Control, state: RuntimeState) -> void:
	_registry = registry
	_mount = mount
	_state = state


func get_api_functions() -> Dictionary[String, Callable]:
	return {
		"open": Callable(self, "_api_open"),
		"set": Callable(self, "_api_set"),
		"close": Callable(self, "_api_close"),
		"on": Callable(self, "_api_on"),
		"hook": Callable(self, "_api_hook")
	}


func _detach_control(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	
	if control.get_parent() != null:
		control.get_parent().remove_child(control)
	
	control.queue_free()


#region Lua API
func _api_open(component_id: Variant, properties: Variant = null) -> int:
	if not _can_use_ui() or typeof(component_id) != TYPE_STRING:
		return 0
	
	if _instances.size() >= MAX_COMPONENTS:
		errors.append("Mod '%s' exceeded the UI component limit." % _state.mod_id)
		return 0
	
	var values := _read_properties(properties)
	if not errors.is_empty():
		return 0
	
	var instance := _registry.instantiate_component(component_id, values, false)
	if instance == null:
		errors.append_array(_registry.errors)
		return 0
	
	var handle := _next_handle
	_next_handle += 1
	_instances[handle] = instance
	_events[handle] = {}
	_hooks[handle] = {}
	_mount.add_child(instance.root)
	return handle


func _api_set(handle: Variant, properties: Variant) -> bool:
	var instance := _get_instance(handle)
	if instance == null:
		return false
	
	var values := _read_properties(properties)
	if not errors.is_empty():
		return false
	
	if not instance.update(values):
		errors.append_array(_registry.errors)
		return false
	
	return true


func _api_close(handle: Variant) -> bool:
	var instance := _get_instance(handle)
	if instance == null:
		return false
	_release_handlers(handle, instance)
	_instances.erase(handle)
	_events.erase(handle)
	_hooks.erase(handle)
	_detach_control(instance.root)
	return true


func _api_on(handle: Variant, event_name: Variant, callback: Variant) -> bool:
	var instance := _get_instance(handle)
	if instance == null or typeof(event_name) != TYPE_STRING:
		return false
	
	if not callback is LuaFunction:
		errors.append("UI event handler must be a Lua function.")
		return false
	
	var token := _state.retain_ui_callback(callback)
	if token == 0:
		errors.append_array(_state.get_errors())
		return false
	
	var listener := Callable(self, "_dispatch_event").bind(token)
	if not instance.on_event(StringName(event_name), listener):
		_state.release_ui_callback(token)
		errors.append_array(instance.interaction.errors)
		return false
	
	_events[handle][String(event_name)] = _events[handle].get(String(event_name), [])
	_events[handle][String(event_name)].append({
		"token": token,
		"listener": listener
	})
	return true


func _api_hook(handle: Variant, hook_name: Variant, callback: Variant) -> bool:
	var instance := _get_instance(handle)
	if instance == null or typeof(hook_name) != TYPE_STRING:
		return false
	
	if not callback is LuaFunction:
		errors.append("UI hook handler must be a Lua function.")
		return false
	
	var token := _state.retain_ui_callback(callback)
	if token == 0:
		errors.append_array(_state.get_errors())
		return false
	
	var previous: Dictionary = _hooks[handle].get(String(hook_name), {})
	var handler := Callable(self, "_dispatch_hook").bind(token)
	if not instance.set_hook(StringName(hook_name), handler):
		_state.release_ui_callback(token)
		errors.append_array(instance.interaction.errors)
		return false
	
	if not previous.is_empty():
		_state.release_ui_callback(previous["token"])
	
	_hooks[handle][String(hook_name)] = {
		"token": token,
		"handler": handler
	}
	return true
#endregion


#region Dispatch
func _dispatch_event(event: Dictionary, token: int) -> void:
	if _state == null:
		return
	var result := _state.invoke_ui_callback(token, [event])
	if not result["ok"]:
		errors.append(str(result["error"]))


func _dispatch_hook(...arguments: Array) -> Variant:
	if _state == null or arguments.is_empty():
		return null
	var token: int = arguments.pop_back()
	var result := _state.invoke_ui_callback(token, arguments, true)
	if not result["ok"]:
		errors.append(str(result["error"]))
		return null
	return result["value"]
#endregion


#region Validation
func _can_use_ui() -> bool:
	if _registry == null or _mount == null or _state == null:
		errors.append("UI Runtime Bridge is not configured.")
		return false
	
	if not is_instance_valid(_mount):
		errors.append("UI mount has been destroyed.")
		return false
	
	if _state.get_phase() != RuntimeState.Phase.ACTIVE:
		errors.append("UI is unavailable outside active Runtime.")
		return false
	
	return true


func _get_instance(handle: Variant) -> UIComponentInstance:
	if not _can_use_ui():
		return null
	
	if typeof(handle) != TYPE_INT or not _instances.has(handle):
		errors.append("Invalid or foreign UI component handle.")
		return null
	
	var instance: UIComponentInstance = _instances[handle]
	if instance.root == null or not is_instance_valid(instance.root):
		errors.append("UI component has been destroyed.")
		return null
	
	return instance


func _read_properties(value: Variant) -> Dictionary:
	errors.clear()
	if value == null:
		return {}
	
	if not value is LuaTable and not value is Dictionary:
		errors.append("UI properties must be a table.")
		return {}
	
	var budget: Array[int] = [0]
	var converted: Variant = _convert_value(value, 0, budget)
	if not errors.is_empty() or not converted is Dictionary:
		return {}
	
	return converted


func _convert_value(value: Variant, depth: int, budget: Array[int]) -> Variant:
	budget[0] += 1
	if depth > MAX_VALUE_DEPTH or budget[0] > MAX_VALUE_ENTRIES:
		errors.append("UI property data exceeds complexity limits.")
		return null
	
	if value is LuaTable:
		if value.get_lua_state() != _state._lua_state:
			errors.append("UI properties contain a foreign Lua table.")
			return null
		return _convert_value(value.to_dictionary(), depth + 1, budget)
	
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME]:
				errors.append("UI property keys must be strings.")
				return null
			result[key] = _convert_value(value[key], depth + 1, budget)
			if not errors.is_empty():
				return null
		return result
	
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_convert_value(item, depth + 1, budget))
			if not errors.is_empty():
				return null
		return result
	
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return value
		TYPE_FLOAT:
			if is_finite(value):
				return LuaUtils.normalize_integer(value)
		TYPE_STRING:
			if value.length() <= MAX_STRING_LENGTH:
				return value
	errors.append("Unsupported UI property value.")
	return null
#endregion


#region Cleanup

func _release_handlers(handle: int, instance: UIComponentInstance) -> void:
	for event_name in _events.get(handle, {}):
		for entry in _events[handle][event_name]:
			instance.off_event(StringName(event_name), entry["listener"])
			_state.release_ui_callback(entry["token"])

	for hook_name in _hooks.get(handle, {}):
		var entry: Dictionary = _hooks[handle][hook_name]
		instance.remove_hook(StringName(hook_name))
		_state.release_ui_callback(entry["token"])

	instance.clear_callbacks()


func close() -> void:
	for handle in _instances.keys():
		var instance: UIComponentInstance = _instances[handle]
		_release_handlers(handle, instance)
		_detach_control(instance.root)

	_instances.clear()
	_events.clear()
	_hooks.clear()

	_state = null
	_registry = null
	_mount = null

#endregion
