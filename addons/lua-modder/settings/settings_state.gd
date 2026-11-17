class_name SettingsState extends State

const DEFINITION_FIELDS := [
	ModSetting.ID, ModSetting.DISPLAY_NAME, ModSetting.DESCRIPTION, ModSetting.ORDER,
	ModSetting.VALUE_TYPE, ModSetting.SCOPE, ModSetting.DEFAULT_VALUE, ModSetting.FORCED_VALUE,
	ModSetting.ALLOWED_VALUES, ModSetting.MINIMUM_VALUE, ModSetting.MAXIMUM_VALUE,
	ModSetting.ALLOW_BLANK, ModSetting.HIDDEN,
]

const STRING_FIELDS := [
	ModSetting.ID, ModSetting.DISPLAY_NAME, ModSetting.DESCRIPTION, ModSetting.ORDER,
	ModSetting.VALUE_TYPE, ModSetting.SCOPE,
]

const BOOL_FIELDS := [
	ModSetting.ALLOW_BLANK, ModSetting.HIDDEN,
]

const ARRAY_FIELDS := [
	ModSetting.ALLOWED_VALUES,
]

const COLOR_FIELDS := [
	ModSetting.DEFAULT_VALUE, ModSetting.FORCED_VALUE,
]

const INTEGER_FIELDS := [
	ModSetting.DEFAULT_VALUE, ModSetting.FORCED_VALUE,
	ModSetting.MINIMUM_VALUE, ModSetting.MAXIMUM_VALUE,
	ModSetting.ALLOWED_VALUES,
]

var _registry: SettingsRegistry
var _settings_api: LuaTable
var _settings_functions: Dictionary = {}

func start() -> void:
	close()
	errors.clear()
	
	_registry = SettingsRegistry.new()
	_lua_state = LuaState.new()
	
	var libraries := LuaState.LUA_BASE | LuaState.LUA_STRING | \
			LuaState.LUA_TABLE | LuaState.LUA_MATH
	_lua_state.open_libraries(libraries)
	LuaExecutionGuard.restrict_base_functions(_lua_state)
	
	_settings_api = _lua_state.create_table()
	_settings_functions = {
		"define": _lua_state.create_function(_lua_define),
		"get": _lua_state.create_function(_lua_get),
		"update": _lua_state.create_function(_lua_update),
		"force": _lua_state.create_function(_lua_force)
	}
	
	for method_name in _settings_functions:
		_settings_api[method_name] = _settings_functions[method_name]
	
	_lua_state.globals["Settings"] = _settings_api


func is_active() -> bool:
	return _lua_state != null


func get_errors() -> Array[String]:
	var result: Array[String] = []
	result.append_array(errors)
	if _registry != null:
		result.append_array(_registry.errors)
	return result


func get_warnings() -> Array[String]:
	var result: Array[String] = []
	if _registry != null:
		result.append_array(_registry.warnings)
	return result


func execute(source: String, mod_id: String, chunk_name: String = "") -> bool:
	if not is_active():
		errors.append("SettingsState is not active.")
		return false
	
	if not errors.is_empty() or not _registry.errors.is_empty():
		return false
	
	if mod_id.strip_edges().is_empty():
		errors.append("Cannot execute settings without a mod ID.")
		return false
	
	_current_mod_id = mod_id
	var success := _execution_guard.execute(_lua_state, source, chunk_name)
	_current_mod_id = ""
	
	if not success:
		errors.append("Lua error in mod '%s' (%s): %s" % [
			mod_id, chunk_name, _execution_guard.last_error
		])
		return false
	
	if not errors.is_empty() or not _registry.errors.is_empty():
		return false
	
	return _validate_settings_api(mod_id)


func finish() -> SettingsRegistry:
	if not is_active():
		errors.append("SettingsState is not active")
		return null
	var registry := _registry if errors.is_empty() and _registry.errors.is_empty() else null
	close()
	return registry


func close() -> void:
	if is_active():
		_lua_state.globals["Settings"] = null

	_settings_api = null
	_settings_functions.clear()
	_lua_state = null
	_current_mod_id = ""


func define_from_json(data: Dictionary, mod_id: String) -> bool:
	if not super.define_from_json(data, mod_id):
		return false

	var previous_mod_id := _current_mod_id
	_current_mod_id = mod_id
	var result := _define_setting(data.duplicate(true))

	_current_mod_id = previous_mod_id
	return result


func _lua_define(definition: Variant) -> bool:
	if not errors.is_empty() or not _registry.errors.is_empty():
		return false
	
	var data: Variant = LuaUtils.read_table(definition)
	if data == null:
		errors.append("Expected a Lua table.")
		return false

	return _define_setting(data)


func _define_setting(data: Dictionary) -> bool:
	var value_type: Variant = data.get(ModSetting.VALUE_TYPE, ModSetting.STRING)
	if typeof(value_type) != TYPE_STRING:
		errors.append("Invalid value_type in setting definition.")
		return false

	var color_fields := COLOR_FIELDS if value_type == ModSetting.COLOR else []
	var integer_fields := INTEGER_FIELDS if value_type == ModSetting.INT else []
	LuaUtils.normalize_fields(data, ARRAY_FIELDS, color_fields, integer_fields)
	
	var setting := ModSetting.new()

	for field in data:
		if not DEFINITION_FIELDS.has(field):
			errors.append("Unknown property '%s' in setting definition." % str(field))
			return false

		var value: Variant = data[field]

		if STRING_FIELDS.has(field) and typeof(value) != TYPE_STRING:
			errors.append("Property '%s' must be a string." % field)
			return false

		if BOOL_FIELDS.has(field) and typeof(value) != TYPE_BOOL:
			errors.append("Property '%s' must be a boolean." % field)
			return false

		if ARRAY_FIELDS.has(field) and typeof(value) != TYPE_ARRAY:
			errors.append("Property '%s' must be an array." % field)
			return false

		setting.set(field, value)

	return _registry.register(setting, _current_mod_id)


func _lua_get(id: Variant) -> Variant:
	if typeof(id) != TYPE_STRING:
		errors.append("Setting ID must be a string.")
		return null

	var setting := _registry.get_setting(id)
	if setting == null:
		return null

	var data := {}

	for field in DEFINITION_FIELDS:
		var value: Variant = setting.get(field)
		if value != null:
			data[field] = value

	data["owner_mod_id"] = setting.owner_mod_id

	return LuaUtils.to_lua_value(_lua_state, data)


func _lua_update(id: Variant, changes: Variant) -> bool:
	if not errors.is_empty() or not _registry.errors.is_empty():
		return false
	
	if typeof(id) != TYPE_STRING:
		errors.append("Setting ID must be a string.")
		return false

	var data: Variant = LuaUtils.read_table(changes)
	if data == null:
		errors.append("Expected a Lua table.")
		return false

	var setting := _registry.get_setting(id)
	if setting == null:
		errors.append("Setting '%s' does not exist." % id)
		return false
	
	var value_type: Variant = data.get(ModSetting.VALUE_TYPE, setting.value_type)
	if typeof(value_type) != TYPE_STRING:
		errors.append("Invalid value_type when updating '%s'." % id)
		return false
	
	var color_fields := COLOR_FIELDS if value_type == ModSetting.COLOR else []
	var integer_fields := INTEGER_FIELDS if value_type == ModSetting.INT else []
	LuaUtils.normalize_fields(data, ARRAY_FIELDS, color_fields, integer_fields)

	return _registry.update(id, data, _current_mod_id)


func _lua_force(id: Variant, value: Variant) -> bool:
	if not errors.is_empty() or not _registry.errors.is_empty():
		return false
	
	if typeof(id) != TYPE_STRING:
		errors.append("Setting ID must be a string.")
		return false
	
	var setting := _registry.get_setting(id)
	if setting == null:
		errors.append("Setting '%s' does not exist." % id)
		return false
	
	if setting.value_type == ModSetting.COLOR:
		value = LuaUtils.convert_color(value)
	elif setting.value_type == ModSetting.INT:
		value = LuaUtils.normalize_integer(value)
	
	return _registry.force(id, value, _current_mod_id)


func _validate_settings_api(mod_id: String) -> bool:
	var current_api: Variant = _lua_state.globals.rawget("Settings")
	
	if not current_api is LuaTable:
		errors.append("Mod '%s' removed or replaced the Settings API." % mod_id)
		return false
	
	if not LuaUtils.same_lua_object(_lua_state, current_api, _settings_api):
		errors.append("Mod '%s' replaced the Settings API table." % mod_id)
		return false
	
	for method_name in _settings_functions:
		var current_function: Variant = _settings_api.rawget(method_name)
		var expected_function: Variant = _settings_functions[method_name]
	
		if not LuaUtils.same_lua_object(_lua_state, current_function, expected_function):
			errors.append("Mod '%s' replaced Settings.%s." % [mod_id, method_name])
			return false
	
	return true
