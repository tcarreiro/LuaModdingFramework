class_name UIComponentInteraction extends RefCounted

var errors: Array[String] = []

var _definition: UIComponentDefinition
var _control_ref: WeakRef

var _listeners: Dictionary = {}
var _hooks: Dictionary = {}
var _connections: Dictionary = {}

func setup(definition: UIComponentDefinition, content_root: Control) -> void:
	_definition = definition
	_control_ref = weakref(content_root)


#region Events
func on_event(event_name: StringName, handler: Callable) -> bool:
	errors.clear()
	if not _definition.events.has(event_name):
		return _error("Unknown component event '%s'." % event_name)
	
	if not handler.is_valid():
		return _error("Invalid event handler for '%s'." % event_name)
	
	if not _listeners.has(event_name):
		_listeners[event_name] = []
	
	var listeners: Array = _listeners[event_name]
	if listeners.has(handler):
		return true
	
	if listeners.is_empty() and not _connect_native(event_name):
		return false
	
	listeners.append(handler)
	return true


func off_event(event_name: StringName, handler: Callable) -> bool:
	errors.clear()
	if not _listeners.has(event_name):
		return false
	
	var listeners: Array = _listeners[event_name]
	if not listeners.has(handler):
		return false
	
	listeners.erase(handler)
	if listeners.is_empty():
		_listeners.erase(event_name)
		_disconnect_native(event_name)
	
	return true


func emit_event(event_name: StringName, arguments: Array = []) -> bool:
	errors.clear()
	if not _definition.events.has(event_name):
		return _error("Unknown component event '%s'." % event_name)
	
	for argument in arguments:
		if not _safe_event_argument(argument):
			return _error("Unsupported event argument in '%s'." % event_name)
	
	var payload := {
		"name": String(event_name),
		"arguments": arguments.duplicate(true)
	}
	
	var listeners: Array = _listeners.get(event_name, []).duplicate()
	for handler: Callable in listeners:
		if handler.is_valid():
			handler.call(payload.duplicate(true))
	
	return true


func _connect_native(event_name: StringName) -> bool:
	if not _definition.event_sources.has(event_name):
		return true
	
	var binding: Dictionary = _definition.event_sources[event_name]
	var root := _control_ref.get_ref() as Control
	if root == null:
		return _error("Component Control has been destroyed.")
	
	var path: NodePath = binding.get("path", NodePath("."))
	var source := root.get_node_or_null(path)
	var signal_name := StringName(binding.get("signal", ""))
	if source == null or not source.has_signal(signal_name):
		return _error("Invalid native signal for event '%s'." % event_name)
	
	if not _validate_native_signal(source, signal_name):
		return false
	
	var callback := Callable(self, "_on_native_signal").bind(event_name)
	var result := source.connect(signal_name, callback)
	if result != OK:
		return _error("Cannot connect native event '%s'." % event_name)
	_connections[event_name] = {
		"source": weakref(source),
		"signal": signal_name
	}
	
	return true


func _disconnect_native(event_name: StringName) -> void:
	if not _connections.has(event_name):
		return
	
	var connection: Dictionary = _connections[event_name]
	var source := (connection["source"] as WeakRef).get_ref() as Object
	if source != null:
		var signal_name: StringName = connection["signal"]
		var callback := Callable(self, "_on_native_signal").bind(event_name)
		if source.is_connected(signal_name, callback):
			source.disconnect(signal_name, callback)
	_connections.erase(event_name)


func _on_native_signal(...arguments: Array) -> void:
	var event_name := StringName(arguments.pop_back())
	emit_event(event_name, arguments)


func _validate_native_signal(source: Object, signal_name: StringName) -> bool:
	for signal_info in source.get_signal_list():
		if StringName(signal_info["name"]) != signal_name:
			continue
	
		for argument in signal_info.get("args", []):
			var argument_type: int = argument.get("type", TYPE_NIL)
			if argument_type not in [
				TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING,
				TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR2I,
				TYPE_VECTOR3, TYPE_COLOR
			]:
				return _error("Signal '%s' has an unsupported argument type." % signal_name)
		return true
	return _error("Cannot inspect native signal '%s'." % signal_name)


func _safe_event_argument(value: Variant) -> bool:
	return typeof(value) in [
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT,
		TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2,
		TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_COLOR
	]
#endregion


#region Hooks
func set_hook(hook_name: StringName, handler: Callable) -> bool:
	errors.clear()
	if not _definition.hooks.has(hook_name):
		return _error("Unknown component hook '%s'." % hook_name)
	
	if not handler.is_valid():
		return _error("Invalid hook handler for '%s'." % hook_name)
	
	_hooks[hook_name] = handler
	return true


func remove_hook(hook_name: StringName) -> void:
	_hooks.erase(hook_name)


func call_hook(hook_name: StringName, arguments: Array = []) -> Variant:
	errors.clear()
	if not _definition.hooks.has(hook_name):
		_error("Unknown component hook '%s'." % hook_name)
		return null
	
	var schema := _hook_schema(hook_name)
	var fallback: Variant = schema.get("fallback", null)
	if not _validate_hook_arguments(hook_name, schema, arguments):
		return fallback
	
	if not _hooks.has(hook_name):
		return fallback
	
	var handler: Callable = _hooks[hook_name]
	if not handler.is_valid():
		_error("Invalid handler for hook '%s'." % hook_name)
		return fallback
	
	var result: Variant = handler.callv(arguments)
	if not _matches_type(result, schema.get("type", TYPE_NIL)):
		_error("Invalid return type for hook '%s'." % hook_name)
		return fallback
	return result


func _hook_schema(hook_name: StringName) -> Dictionary:
	var schema: Variant = _definition.hooks[hook_name]
	if schema is Dictionary:
		return schema
	return {
		"type": schema,
		"fallback": false if schema == TYPE_BOOL else null
	}


func _validate_hook_arguments(hook_name: StringName, schema: Dictionary, arguments: Array) -> bool:
	if not schema.has("args"):
		return true
	
	var expected: Array = schema["args"]
	if expected.size() != arguments.size():
		return _error("Invalid argument count for hook '%s'." % hook_name)
	
	for i in expected.size():
		if not _matches_type(arguments[i], expected[i]):
			return _error("Invalid argument type for hook '%s' at index %d." % [hook_name, i])
	return true


func _matches_type(value: Variant, expected: int) -> bool:
	return typeof(value) == expected \
		or (expected == TYPE_FLOAT and typeof(value) == TYPE_INT)
#endregion


func clear() -> void:
	for event_name in _connections.keys():
		_disconnect_native(event_name)

	_listeners.clear()
	_hooks.clear()
	errors.clear()


func _error(message: String) -> bool:
	errors.append(message)
	return false
