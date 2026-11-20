class_name UIRuntimeBridge extends RefCounted

const MAX_COMPONENTS := 256
const MAX_VALUE_DEPTH := 8
const MAX_VALUE_ENTRIES := 512
const MAX_STRING_LENGTH := 4096

var errors: Array[String] = []

var _registry: UIComponentRegistry
var _mount: Control
var _ui_root: UIRootHost
var _presentation_nodes: Dictionary[int, Control] = {}
var _state: RuntimeState
var _trusted_consumer := false
var _instances: Dictionary[int, UIComponentInstance] = {}
var _events: Dictionary[int, Dictionary] = {}
var _hooks: Dictionary[int, Dictionary] = {}
var _next_handle := 1

func setup(registry: UIComponentRegistry, mount: Control, state: RuntimeState, ui_root: UIRootHost = null) -> void:
	_registry = registry
	_mount = mount
	_state = state
	_trusted_consumer = state != null and state.mod_id == "core"
	_ui_root = ui_root


func get_api_functions() -> Dictionary[String, Callable]:
	return {
		"open": Callable(self, "_api_open"),
		"set": Callable(self, "_api_set"),
		"animate": Callable(self, "_api_animate"),
		"get_properties": Callable(self, "_api_get_properties"),
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
func _api_open(component_id: Variant, properties: Variant = null, options: Variant = null) -> int:
	if not _can_use_ui() or typeof(component_id) != TYPE_STRING:
		return 0
	
	if _instances.size() >= MAX_COMPONENTS:
		errors.append("UI component limit exceeded.")
		return 0
	
	var definition := _registry.get_definition(component_id)
	if definition == null:
		errors.append("Unknown UI component '%s'." % component_id)
		return 0
	
	var values := _read_properties(properties)
	if not errors.is_empty():
		return 0
	
	var presentation := _read_open_options(options)
	if not errors.is_empty():
		return 0
	
	var default_root := "overlay" if definition.presentation == "overlay" else "inline"
	var anchor_handle: int = int(presentation.get("anchor", 0))
	var use_cursor: bool = presentation.get("at_cursor", false)
	if anchor_handle != 0 and not _instances.has(anchor_handle):
		errors.append("Anchor must reference a component handle in this UI runtime.")
		return 0
	if (anchor_handle != 0 or use_cursor) and not instance_supports_anchor(definition):
		errors.append("Only anchored overlay components support anchor/at_cursor.")
		return 0
	var placement: String = presentation.get("root", "overlay" if anchor_handle != 0 or use_cursor else default_root)
	
	var backdrop_enabled: bool = presentation.get(
		"backdrop",
		placement == "modal"
	)
	
	var backdrop_style_id: String = presentation.get("backdrop_style", "")
	var filter_name: String = presentation.get(
		"backdrop_mouse_filter",
		"stop" if placement == "modal" else "ignore"
	)
	if placement != "inline":
		if _ui_root == null or not is_instance_valid(_ui_root):
			errors.append("UI root host is unavailable.")
			return 0
	
		var layer_id := StringName(placement)
		if not _ui_root.has_layer(layer_id):
			errors.append("Unknown UI layer '%s'." % placement)
			return 0
	
		if not _trusted_consumer and not _ui_root.is_layer_exposed_to_mods(layer_id):
			errors.append("UI layer '%s' is not available to mods." % placement)
			return 0
	
		if _ui_root.get_mount(layer_id) == null:
			errors.append("UI layer '%s' has no valid mount." % placement)
			return 0
	
	if (anchor_handle != 0 or use_cursor) and placement != "overlay":
		errors.append("Anchored UI must use the overlay root.")
		return 0
	if (anchor_handle != 0 or use_cursor) and backdrop_enabled:
		errors.append("Anchored UI cannot use a fullscreen backdrop.")
		return 0
	if presentation.has("position") and (anchor_handle != 0 or use_cursor):
		errors.append("Position cannot be combined with anchor/at_cursor.")
		return 0
	if placement == "inline" and backdrop_enabled:
		errors.append("Inline components cannot have a fullscreen backdrop.")
		return 0
	
	var initial_position: Variant = null
	if presentation.has("position"):
		if placement in ["inline", "screen"]:
			errors.append("Position is only available for floating UI.")
			return 0
		var coordinates: Dictionary = presentation["position"]
		initial_position = Vector2(
			float(coordinates["x"]),
			float(coordinates["y"])
		)
	
	if not backdrop_enabled and not backdrop_style_id.is_empty():
		errors.append("Backdrop style requires an enabled backdrop.")
		return 0
	
	var backdrop_style: StyleBox
	if backdrop_enabled and not backdrop_style_id.is_empty():
		backdrop_style = _resolve_backdrop_style(backdrop_style_id)
		if backdrop_style == null:
			return 0
	var filter := _backdrop_filter(filter_name)
	var instance := _registry.instantiate_component(component_id, values, _trusted_consumer)
	if instance == null:
		errors.append_array(_registry.errors)
		return 0
	
	if _ui_root != null:
		instance.root.set_meta(UIRootHost.ROOT_META, weakref(_ui_root))
	
	var mounted: Control = instance.root
	if placement == "inline":
		_mount.add_child(instance.root)
	else:
		mounted = _ui_root.mount_component(
			instance.root,
			placement,
			backdrop_enabled,
			backdrop_style,
			filter,
			initial_position
		)
		if mounted == null:
			instance.root.free()
			errors.append("Cannot mount UI component '%s'." % component_id)
			return 0
	
	var handle := _next_handle
	_next_handle += 1
	_instances[handle] = instance
	_presentation_nodes[handle] = mounted
	_events[handle] = {}
	_hooks[handle] = {}
	if anchor_handle != 0 or use_cursor:
		_finish_anchor_open.call_deferred(handle, anchor_handle, presentation)
	return handle


func instance_supports_anchor(definition: UIComponentDefinition) -> bool:
	return definition.id == UIBuiltinIds.CONTEXT_MENU


func _finish_anchor_open(handle: int, anchor_handle: int, options: Dictionary) -> void:
	var instance := _instances.get(handle) as UIComponentInstance
	if instance == null or not is_instance_valid(instance.content_root):
		return
	var menu := instance.content_root as UIComponentContextMenu
	if menu == null:
		return
	if options.get("at_cursor", false):
		menu.open_at_mouse()
		return
	var anchor_instance := _instances.get(anchor_handle) as UIComponentInstance
	if anchor_instance == null or not is_instance_valid(anchor_instance.root):
		_api_close(handle)
		return
	var offset_data: Dictionary = options.get("offset", {"x": 0, "y": 8})
	var offset := Vector2(float(offset_data.get("x", 0)), float(offset_data.get("y", 8)))
	menu.open_anchored(anchor_instance.root, options.get("placement", "bottom"), options.get("alignment", "start"), offset, options.get("flip", true))


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


# game.ui.get_properties("ui:button") or game.ui.get_properties(handle)
func _api_get_properties(component: Variant) -> Variant:
	if not _can_use_ui():
		return null
	var id := ""
	if typeof(component) == TYPE_STRING:
		id = component
	elif typeof(component) == TYPE_INT and _instances.has(component):
		id = (_instances[component] as UIComponentInstance).component_id
	else:
		errors.append("UI.get_properties requires a component ID or valid handle.")
		return null
	var definition := _registry.get_definition(id)
	if definition == null or (not _trusted_consumer and not definition.exposed_to_mods):
		errors.append("UI component '%s' is unavailable." % id)
		return null
	return LuaUtils.to_lua_value(_state._lua_state, _registry.describe_recognized_properties(id, _trusted_consumer))


func _api_animate(handle: Variant, animation_id: Variant) -> bool:
	var instance := _get_instance(handle)
	if instance == null:
		return false
	if typeof(animation_id) != TYPE_STRING or animation_id.is_empty():
		errors.append("UI.animate requires a nonempty animation ID.")
		return false
	if not instance.play_animation(animation_id):
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
	var visual_root := _presentation_nodes.get(handle, instance.root) as Control
	_presentation_nodes.erase(handle)
	_detach_control(visual_root)
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


func _is_lua_sequence(values: Dictionary) -> bool:
	if values.is_empty():
		return false
	for index in range(1, values.size() + 1):
		if not values.has(index):
			return false
	return true


func _convert_value(value: Variant, depth: int, budget: Array[int]) -> Variant:
	budget[0] += 1
	if depth > MAX_VALUE_DEPTH or budget[0] > MAX_VALUE_ENTRIES:
		errors.append("UI property data exceeds complexity limits.")
		return null
	
	if value is LuaTable:
		if value.get_lua_state() != _state._lua_state:
			errors.append("UI properties contain a foreign Lua table.")
			return null
		var raw = value.to_dictionary()
		if _is_lua_sequence(raw):
			var result: Array = []
			for index in range(1, raw.size() + 1):
				result.append(_convert_value(raw[index], depth + 1, budget))
				if not errors.is_empty():
					return null
			return result
		return _convert_value(raw, depth + 1, budget)
	
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
		var visual_root := _presentation_nodes.get(handle, instance.root) as Control
		_detach_control(visual_root)

	_instances.clear()
	_events.clear()
	_hooks.clear()

	_state = null
	_registry = null
	_mount = null
	_presentation_nodes.clear()
	_ui_root = null

#endregion


func _read_open_options(value: Variant) -> Dictionary:
	var result := _read_properties(value)
	if not errors.is_empty():
		return {}
	
	for name in result:
		match name:
			"root":
				if typeof(result[name]) != TYPE_STRING:
					errors.append("UI root must be a string.")
					return {}
				var root_id: String = result[name]
				if root_id.strip_edges().is_empty() or root_id.length() > 128:
					errors.append("Invalid UI root identifier.")
					return {}
			"backdrop":
				if typeof(result[name]) != TYPE_BOOL:
					errors.append("Backdrop must be a boolean.")
					return {}
			"backdrop_style":
				if typeof(result[name]) != TYPE_STRING:
					errors.append("Backdrop style must be a string.")
					return {}
			"backdrop_mouse_filter":
				if typeof(result[name]) != TYPE_STRING \
						or result[name] not in ["stop", "pass", "ignore"]:
					errors.append("Invalid backdrop mouse filter.")
					return {}
			"anchor":
				if typeof(result[name]) != TYPE_INT or result[name] <= 0:
					errors.append("UI anchor must be a valid component handle.")
					return {}
			"at_cursor", "flip":
				if typeof(result[name]) != TYPE_BOOL:
					errors.append("UI presentation option '%s' must be boolean." % name)
					return {}
			"placement":
				if typeof(result[name]) != TYPE_STRING or result[name] not in ["top", "bottom", "left", "right"]:
					errors.append("Invalid UI anchor placement.")
					return {}
			"alignment":
				if typeof(result[name]) != TYPE_STRING or result[name] not in ["start", "center", "end"]:
					errors.append("Invalid UI anchor alignment.")
					return {}
			"offset":
				var coordinates: Variant = result[name]
				if not coordinates is Dictionary or coordinates.size() != 2 or not coordinates.has("x") or not coordinates.has("y"):
					errors.append("UI anchor offset requires x and y.")
					return {}
				for axis in ["x", "y"]:
					var axis_value: Variant = coordinates[axis]
					if typeof(axis_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(axis_value)):
						errors.append("Invalid UI anchor offset coordinate.")
						return {}
			"position":
				var coordinates: Variant = result[name]
				if not coordinates is Dictionary:
					errors.append("UI position must be a table with x and y.")
					return {}
				if coordinates.size() != 2 \
						or not coordinates.has("x") \
						or not coordinates.has("y"):
					errors.append("UI position requires x and y.")
					return {}
				for axis in ["x", "y"]:
					var axis_value: Variant = coordinates[axis]
					if typeof(axis_value) not in [TYPE_INT, TYPE_FLOAT] \
							or not is_finite(float(axis_value)):
						errors.append("Invalid UI position coordinate '%s'." % axis)
						return {}
			_:
				errors.append("Unknown UI presentation option '%s'." % name)
				return {}
	return result


func _backdrop_filter(value: String) -> int:
	match value:
		"pass":
			return Control.MOUSE_FILTER_PASS
		"ignore":
			return Control.MOUSE_FILTER_IGNORE
		_:
			return Control.MOUSE_FILTER_STOP


func _resolve_backdrop_style(style_id: String) -> StyleBox:
	if _registry.style_registry == null:
		errors.append("UI StyleRegistry is unavailable.")
		return null
	
	var style := _registry.style_registry.prepare_instance(style_id, {}, _trusted_consumer)
	if style == null:
		errors.append_array(_registry.style_registry.errors)
		return null
	
	var box := style.styleboxes.get("panel") as StyleBox
	if box == null:
		errors.append("Backdrop style '%s' has no panel StyleBox." % style_id)
		return null
	return box
