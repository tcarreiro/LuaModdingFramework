class_name ContentState extends State

var _types: ContentTypeRegistry
var _registry: ContentRegistry
var _content_api: LuaTable
var _extend_function: LuaFunction
var _ui_registry: UIComponentRegistry
var _ui_registration: UIContentRegistration
var _ui_api: LuaTable
var _ui_define_function: LuaFunction
var _ui_get_properties_function: LuaFunction
var _ui_style_registration: UIStyleContentRegistration
var _ui_style_function: LuaFunction
var _ui_animation_registration: UIAnimationContentRegistration
var _ui_animation_function: LuaFunction
var _style_registration_mods: Array[String] = ["core"]

func _init(content_types: ContentTypeRegistry, ui_components: UIComponentRegistry = null, style_registration_mods: Array[String] = ["core"]) -> void:
	_types = content_types
	_ui_registry = ui_components
	_style_registration_mods = style_registration_mods.duplicate()


func start(startup_settings: Dictionary = {}, mod_versions: Dictionary = {}) -> void:
	close()
	errors.clear()
	warnings.clear()
	_registry = ContentRegistry.new(_types)
	_lua_state = LuaState.new()
	var libraries := LuaState.LUA_BASE | LuaState.LUA_STRING | \
			LuaState.LUA_TABLE | LuaState.LUA_MATH
	_lua_state.open_libraries(libraries)
	LuaExecutionGuard.restrict_base_functions(_lua_state)
	_content_api = _lua_state.create_table()
	_raw = _lua_state.create_table()
	_extend_function = _lua_state.create_function(_lua_extend)
	_content_api["raw"] = _raw
	_content_api["extend"] = _extend_function
	_lua_state.globals["Content"] = _content_api
	if _ui_registry != null:
		_ui_registration = UIContentRegistration.new(_ui_registry, _lua_state)
		_ui_api = _lua_state.create_table()
		_ui_define_function = _lua_state.create_function(_lua_define_component)
		_ui_api["define_component"] = _ui_define_function
		_ui_get_properties_function = _lua_state.create_function(_lua_get_properties)
		_ui_api["get_properties"] = _ui_get_properties_function
		if _ui_registry.style_registry != null:
			_ui_style_registration = UIStyleContentRegistration.new(_ui_registry.style_registry)
			_ui_style_function = _lua_state.create_function(_lua_define_style)
			_ui_api["define_style"] = _ui_style_function
		if _ui_registry.animation_registry != null:
			_ui_animation_registration = UIAnimationContentRegistration.new(_ui_registry.animation_registry)
			_ui_animation_function = _lua_state.create_function(_lua_define_animation)
			_ui_api["define_animation"] = _ui_animation_function
		_lua_state.globals["UI"] = _ui_api
	var startup: Dictionary = {}
	for setting_id in startup_settings:
		startup[setting_id] = {
			"value": startup_settings[setting_id]
		}
	_lua_state.globals["mods"] = LuaUtils.to_lua_value(_lua_state, mod_versions)
	_lua_state.globals["settings"] = LuaUtils.to_lua_value(_lua_state, {
		"startup": startup
	})


func is_active() -> bool:
	return _lua_state != null


func get_registry() -> ContentRegistry:
	return _registry


func get_errors() -> Array[String]:
	var result: Array[String] = []
	result.append_array(errors)
	if _registry != null:
		result.append_array(_registry.errors)
	return result


func execute(source: String, mod_id: String, chunk_name: String = "") -> bool:
	if not is_active():
		errors.append("ContentState is not active.")
		return false
	if not errors.is_empty() or not _registry.errors.is_empty():
		return false
	if mod_id.strip_edges().is_empty():
		errors.append("Cannot execute content without a mod ID.")
		return false
	var error_count := errors.size()
	var registry_error_count := _registry.errors.size()
	_current_mod_id = mod_id
	var success := _execution_guard.execute(_lua_state, source, chunk_name)
	_current_mod_id = ""
	if not success:
		errors.append("Lua error in mod '%s' (%s): %s" % [
			mod_id, chunk_name, _execution_guard.last_error
		])
		return false
	if errors.size() != error_count or _registry.errors.size() != registry_error_count:
		return false
	if not _validate_content_api(mod_id):
		return false
	return _synchronize_raw(mod_id)


func finish() -> ContentRegistry:
	if not is_active():
		errors.append("ContentState is not active.")
		return null
	var result: ContentRegistry = null
	if errors.is_empty() and _registry.errors.is_empty():
		if _registry.finalize():
			result = _registry
	close()
	return result



func _validate_content_api(mod_id: String) -> bool:
	var current_content: Variant = _lua_state.globals.rawget("Content")
	if not current_content is LuaTable:
		errors.append("Mod '%s' removed or replaced the Content API." % mod_id)
		return false
	
	if not LuaUtils.same_lua_object(_lua_state, current_content, _content_api):
		errors.append("Mod '%s' replaced the Content API table." % mod_id)
		return false
	
	var current_raw: Variant = current_content.rawget("raw")
	if not LuaUtils.same_lua_object(_lua_state, current_raw, _raw):
		errors.append("Mod '%s' replaced Content.raw." % mod_id)
		return false
	
	var current_extend: Variant = current_content.rawget("extend")
	if not LuaUtils.same_lua_object(_lua_state, current_extend, _extend_function):
		errors.append("Mod '%s' replaced Content.extend." % mod_id)
		return false
	
	if _ui_registry != null:
		var current_ui: Variant = _lua_state.globals.rawget("UI")
		if not LuaUtils.same_lua_object(_lua_state, current_ui, _ui_api):
			errors.append("Mod '%s' replaced the UI API table." % mod_id)
			return false
	
		var current_define: Variant = current_ui.rawget("define_component")
		if not LuaUtils.same_lua_object(_lua_state, current_define, _ui_define_function):
			errors.append("Mod '%s' replaced UI.define_component." % mod_id)
			return false
		if not LuaUtils.same_lua_object(_lua_state, current_ui.rawget("get_properties"), _ui_get_properties_function):
			errors.append("Mod '%s' replaced UI.get_properties." % mod_id)
			return false
		if _ui_style_function != null and not LuaUtils.same_lua_object(_lua_state, current_ui.rawget("define_style"), _ui_style_function):
			errors.append("Mod '%s' replaced UI.define_style." % mod_id)
			return false
		if _ui_animation_function != null and not LuaUtils.same_lua_object(_lua_state, current_ui.rawget("define_animation"), _ui_animation_function):
			errors.append("Mod '%s' replaced UI.define_animation." % mod_id)
			return false
	return true


func _synchronize_raw(mod_id: String) -> bool:
	var previous_error_count := errors.size()
	var current_catalog := _read_raw_catalog()
	if errors.size() != previous_error_count:
		return false
	var previous_catalog := _registry.get_catalog()
	# Removed templates
	for type_id in previous_catalog:
		var previous_templates: Dictionary = previous_catalog[type_id]
		var current_templates: Dictionary = current_catalog.get(type_id, {})
		for template_id in previous_templates:
			if current_templates.has(template_id):
				continue
			if not _registry.remove(type_id, template_id, mod_id):
				return false
	# New or updated templates
	for type_id in current_catalog:
		var current_templates: Dictionary = current_catalog[type_id]
		for template_id in current_templates:
			var data: Dictionary = current_templates[template_id]
			if not _registry.has_template(type_id, template_id):
				if not _registry.register_template(data, mod_id):
					return false
			elif _registry.get_template(type_id, template_id) != data:
				if not _registry.replace(type_id, template_id, data, mod_id):
					return false
	return true


func _read_raw_catalog() -> Dictionary:
	var catalog: Dictionary = {}
	var raw_types: Dictionary = _raw.to_dictionary()
	for raw_type_id in raw_types:
		if typeof(raw_type_id) != TYPE_STRING:
			errors.append("Content.raw type keys must be strings.")
			continue
		var type_id: String = raw_type_id
		if not _types.has_type(type_id):
			errors.append("Unknown Template type '%s'." % type_id)
			continue
		var lua_bucket: Variant = raw_types[raw_type_id]
		if not lua_bucket is LuaTable:
			errors.append("Content.raw['%s'] must be a Lua table." % type_id)
			continue
		catalog[type_id] = _read_raw_bucket(type_id, lua_bucket)
	return catalog


func _read_raw_bucket(type_id: String, bucket: LuaTable) -> Dictionary:
	var templates: Dictionary = {}
	var raw_templates: Dictionary = bucket.to_dictionary()
	for raw_template_id in raw_templates:
		if typeof(raw_template_id) != TYPE_STRING:
			errors.append("Template IDs in '%s' must be strings." % type_id)
			continue
		var template_id: String = raw_template_id
		var lua_template: Variant = raw_templates[raw_template_id]
		if not lua_template is LuaTable:
			errors.append("Template '%s.%s' must be a Lua table." % [type_id, template_id])
			continue
		var data := _read_lua_map(lua_template, type_id, 0)
		if not _validate_raw_identity(type_id, template_id, data):
			continue
		templates[template_id] = data
	return templates


func _validate_raw_identity(type_id: String, template_id: String, data: Dictionary) -> bool:
	if typeof(data.get("type")) != TYPE_STRING or data["type"] != type_id:
		errors.append("Template '%s.%s' has an invalid type." % [type_id, template_id])
		return false
	if typeof(data.get("id")) != TYPE_STRING or data["id"] != template_id:
		errors.append("Template '%s.%s' has an invalid ID." % [type_id, template_id])
		return false
	if template_id.strip_edges().is_empty():
		errors.append("Template ID cannot be empty in '%s'." % type_id)
		return false
	return true


func define_from_json(data: Dictionary, mod_id: String) -> bool:
	if not super.define_from_json(data, mod_id):
		return false
	var type_id: String = str(data.get("type", ""))
	var template_id: String = str(data.get("id", ""))
	if _raw_has_template(type_id, template_id):
		errors.append("Template '%s.%s' already exists in Content.raw." % [type_id, template_id])
		return false
	if not _registry.register_template(data, mod_id):
		return false
	_insert_raw(type_id, template_id, LuaUtils.to_lua_value(_lua_state, data))
	return true


func _lua_extend(templates: Variant) -> bool:
	if not errors.is_empty() or not _registry.errors.is_empty():
		return false
	if not templates is LuaTable:
		errors.append("Content.extend expects a Lua table.")
		return false
	var lua_templates: Array[LuaTable] = []
	var batch := _read_extend_batch(templates, lua_templates)
	if not errors.is_empty():
		return false
	if not _registry.extend(batch, _current_mod_id):
		return false
	for index in range(batch.size()):
		var data: Dictionary = batch[index]
		_insert_raw(data["type"], data["id"], lua_templates[index])
	return true


func _lua_define_component(component_id: Variant, descriptor: Variant) -> bool:
	if _ui_registration == null:
		errors.append("UI component registration is unavailable.")
		return false
	if not _ui_registration.register(_current_mod_id, component_id, descriptor):
		errors.append_array(_ui_registration.errors)
		return false
	return true


func _lua_get_properties(component_id: Variant) -> Variant:
	if _ui_registry == null or typeof(component_id) != TYPE_STRING:
		errors.append("UI.get_properties requires a component ID.")
		return null
	var definition := _ui_registry.get_definition(component_id)
	if definition == null or (_current_mod_id != "core" and not definition.exposed_to_mods):
		errors.append("Unknown or private component '%s'." % component_id)
		return null
	return LuaUtils.to_lua_value(
		_lua_state, _ui_registry.describe_recognized_properties(component_id, _current_mod_id == "core")
	)


func _lua_define_style(style_id: Variant, descriptor: Variant) -> bool:
	if _ui_style_registration == null:
		errors.append("UI style registration is unavailable.")
		return false
	if not _style_registration_mods.has(_current_mod_id):
		errors.append("Mod '%s' is not authorized to define UI styles." % _current_mod_id)
		return false
	if not _ui_style_registration.register(_current_mod_id, style_id, descriptor):
		errors.append_array(_ui_style_registration.errors)
		return false
	return true


func _lua_define_animation(animation_id: Variant, descriptor: Variant) -> bool:
	if _ui_animation_registration == null:
		errors.append("UI animation registration is unavailable.")
		return false
	if not _style_registration_mods.has(_current_mod_id):
		errors.append("Mod '%s' is not authorized to define UI animations." % _current_mod_id)
		return false
	if not _ui_animation_registration.register(_current_mod_id, animation_id, descriptor):
		errors.append_array(_ui_animation_registration.errors)
		return false
	return true


func _read_extend_batch(templates: LuaTable, lua_templates: Array[LuaTable]) -> Array:
	var source: Dictionary = templates.to_dictionary()
	var batch: Array = []
	for index in range(1, source.size() + 1):
		if not source.has(index):
			errors.append("Content.extend expects a sequential array.")
			return []
		var value: Variant = source[index]
		if not value is LuaTable:
			errors.append("Content.extend: element %d must be a table." % index)
			return []
		var type_id: Variant = value.rawget("type")
		var template_id: Variant = value.rawget("id")
		if typeof(type_id) != TYPE_STRING or typeof(template_id) != TYPE_STRING:
			errors.append("Content.extend: Template must have string type and id.")
			return []
		if _raw_has_template(type_id, template_id):
			errors.append("Template '%s.%s' already exists in Content.raw." % [type_id, template_id])
			return []
		var data := _read_lua_map(value, type_id, 0)
		if not errors.is_empty():
			return []
		batch.append(data)
		lua_templates.append(value)
	return batch


func _raw_has_template(type_id: String, template_id: String) -> bool:
	var bucket: Variant = _raw.rawget(type_id)
	if not bucket is LuaTable:
		return false
	return bucket.rawget(template_id) != null


func _insert_raw(type_id: String, template_id: String, value: LuaTable) -> void:
	var bucket: Variant = _raw.rawget(type_id)
	if not bucket is LuaTable:
		bucket = _lua_state.create_table()
		_raw.rawset(type_id, bucket)
	bucket.rawset(template_id, value)


func _read_lua_map(table: LuaTable, owner_type: String, depth: int) -> Dictionary:
	if depth > 32:
		errors.append("Maximum content nesting depth exceeded.")
		return {}
	var result: Dictionary = {}
	var source: Dictionary = table.to_dictionary()
	var properties := _types.get_properties(owner_type)
	for key in source:
		var value: Variant = source[key]
		var binding := _types.get_struct_binding(owner_type, str(key))
		var property_info: Dictionary = properties.get(key, {})
		if not binding.is_empty():
			if binding["is_array"]:
				result[key] = _read_lua_array(value, binding["struct_type"], depth + 1)
			elif value is LuaTable:
				result[key] = _read_lua_map(value, binding["struct_type"], depth + 1)
			else:
				result[key] = value
		elif value is LuaTable:
			match property_info.get("type", TYPE_NIL):
				TYPE_ARRAY:
					result[key] = _read_lua_array(value, "", depth + 1)
				TYPE_DICTIONARY:
					result[key] = _read_lua_map(value, "", depth + 1)
				TYPE_COLOR:
					result[key] = LuaUtils.convert_color(value)
				_:
					result[key] = _read_lua_generic(value, depth + 1)
		else:
			result[key] = value
	return result


func _read_lua_array(value: Variant, struct_type: String, depth: int) -> Variant:
	if not value is LuaTable:
		return value
	if depth > 32:
		errors.append("Maximum content nesting depth exceeded.")
		return []
	var source: Dictionary = value.to_dictionary()
	var result: Array = []
	for index in range(1, source.size() + 1):
		if not source.has(index):
			errors.append("Content array must contain sequential numeric keys.")
			return []
		var item: Variant = source[index]
		if not struct_type.is_empty() and item is LuaTable:
			result.append(_read_lua_map(item, struct_type, depth + 1))
		else:
			result.append(_read_lua_generic(item, depth + 1))
	return result


func _read_lua_generic(value: Variant, depth: int) -> Variant:
	if not value is LuaTable:
		return value
	if depth > 32:
		errors.append("Maximum content nesting depth exceeded.")
		return null
	var source: Dictionary = value.to_dictionary()
	if not source.is_empty():
		var sequential := true
		for index in range(1, source.size() + 1):
			if not source.has(index):
				sequential = false
				break
		if sequential:
			return _read_lua_array(value, "", depth + 1)
	return _read_lua_map(value, "", depth + 1)



func close() -> void:
	if is_active():
		_lua_state.globals.rawset("Content", null)
		if _ui_api != null:
			_lua_state.globals.rawset("UI", null)
	_ui_registration = null
	_ui_style_registration = null
	_ui_animation_registration = null
	_ui_animation_function = null
	_ui_style_function = null
	_ui_api = null
	_ui_define_function = null
	_ui_get_properties_function = null
	_content_api = null
	_extend_function = null
	_raw = null
	_lua_state = null
	_current_mod_id = ""
