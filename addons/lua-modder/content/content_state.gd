@tool
class_name ContentState extends RefCounted

var errors: Array[String] = []

var _types: ContentTypeRegistry
var _registry: ContentRegistry
var _lua_state: LuaState
var _raw: LuaTable
var _current_mod_id: String = ""


func _init(content_types: ContentTypeRegistry) -> void:
	_types = content_types


func start(startup_settings: Dictionary = {}, mod_versions: Dictionary = {}) -> void:
	close()
	errors.clear()

	_registry = ContentRegistry.new(_types)
	_lua_state = LuaState.new()

	var libraries := LuaState.LUA_BASE | LuaState.LUA_STRING | \
			LuaState.LUA_TABLE | LuaState.LUA_MATH
	_lua_state.open_libraries(libraries)

	var content_api := _lua_state.create_table()
	_raw = _lua_state.create_table()
	content_api["raw"] = _raw
	content_api["extend"] = _lua_state.create_function(_lua_extend)

	_lua_state.globals["Content"] = content_api
	
	
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

	if mod_id.strip_edges().is_empty():
		errors.append("Cannot execute content without a mod ID.")
		return false

	var error_count := errors.size()
	var registry_error_count := _registry.errors.size()

	_current_mod_id = mod_id
	var result: Variant = _lua_state.do_string(source, chunk_name)
	_current_mod_id = ""

	if result is LuaError:
		errors.append("Lua error in mod '%s' (%s): %s" % [
			mod_id, chunk_name, str(result)
		])
		return false

	if errors.size() != error_count or _registry.errors.size() != registry_error_count:
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

		var templates: Dictionary = {}
		var raw_templates: Dictionary = lua_bucket.to_dictionary()

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

			if typeof(data.get("type")) != TYPE_STRING or data["type"] != type_id:
				errors.append("Template '%s.%s' has an invalid type." % [type_id, template_id])
				continue

			if typeof(data.get("id")) != TYPE_STRING or data["id"] != template_id:
				errors.append("Template '%s.%s' has an invalid ID." % [type_id, template_id])
				continue

			if template_id.strip_edges().is_empty():
				errors.append("Template ID cannot be empty in '%s'." % type_id)
				continue

			templates[template_id] = data
		catalog[type_id] = templates
	return catalog


func define_from_json(data: Dictionary, mod_id: String) -> bool:
	if not is_active():
		errors.append("ContentState is not active.")
		return false

	if mod_id.strip_edges().is_empty():
		errors.append("Cannot register content without a mod ID.")
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
	if not templates is LuaTable:
		errors.append("Content.extend expects a Lua table.")
		return false

	var source: Dictionary = templates.to_dictionary()
	var batch: Array = []
	var lua_templates: Array[LuaTable] = []

	for index in range(1, source.size() + 1):
		if not source.has(index):
			errors.append("Content.extend expects a sequential array.")
			return false

		var value: Variant = source[index]

		if not value is LuaTable:
			errors.append("Content.extend: element %d must be a table." % index)
			return false

		var type_id: Variant = value.rawget("type")
		var template_id: Variant = value.rawget("id")

		if typeof(type_id) != TYPE_STRING or typeof(template_id) != TYPE_STRING:
			errors.append("Content.extend: Template must have string type and id.")
			return false

		if _raw_has_template(type_id, template_id):
			errors.append("Template '%s.%s' already exists in Content.raw." % [type_id, template_id])
			return false

		var error_count := errors.size()
		var data := _read_lua_map(value, type_id, 0)

		if errors.size() != error_count:
			return false

		batch.append(data)
		lua_templates.append(value)

	if not _registry.extend(batch, _current_mod_id):
		return false

	for index in range(batch.size()):
		var data: Dictionary = batch[index]
		_insert_raw(data["type"], data["id"], lua_templates[index])

	return true


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

	_raw = null
	_lua_state = null
	_current_mod_id = ""
