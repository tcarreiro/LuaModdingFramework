@tool
class_name SettingsState extends RefCounted

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

var errors: Array[String] = []

var _lua_state: LuaState
var _registry: ModSettingsRegistry
var _current_mod_id: String = ""


func start() -> void:
	close()
	errors.clear()
	
	_registry = ModSettingsRegistry.new()
	_lua_state = LuaState.new()
	
	var libraries := LuaState.LUA_BASE | LuaState.LUA_STRING | \
			LuaState.LUA_TABLE | LuaState.LUA_MATH
	_lua_state.open_libraries(libraries)
	
	var settings_api := _lua_state.create_table()
	settings_api["define"] = _lua_state.create_function(_lua_define)
	settings_api["update"] = _lua_state.create_function(_lua_update)
	settings_api["force"] = _lua_state.create_function(_lua_force)
	
	_lua_state.globals["Settings"] = settings_api


func is_active() -> bool:
	return _lua_state != null


func execute(source: String, mod_id: String, chunk_name: String = "") -> bool:
	if not is_active():
		errors.append("SettingsState is not active")
		return false
	
	if mod_id.strip_edges().is_empty():
		errors.append("Cannot execute settings without a mod ID.")
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
	
	return errors.size() == error_count and _registry.errors.size() == registry_error_count


func finish() -> ModSettingsRegistry:
	if not is_active():
		errors.append("SettingsState is not active")
		return null
	
	var registry := _registry if errors.is_empty() and _registry.errors.is_empty() else null
	close()
	
	return registry


func close() -> void:
	if is_active():
		_lua_state.globals["Settings"] = null
		_lua_state = null
	
	_current_mod_id = ""


func _lua_define(definition: Variant) -> bool:
	var data: Variant = _read_table(definition)
	if data == null:
		return false
	
	var value_type:Variant = data.get(ModSetting.VALUE_TYPE, ModSetting.STRING)
	if typeof(value_type) != TYPE_STRING:
		errors.append("Invalid value_type in setting definition.")
		return false
	
	_normalize_fields(data, value_type)
	
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

func _lua_update(id: Variant, changes: Variant) -> bool:
	if typeof(id) != TYPE_STRING:
		errors.append("Setting ID must be a string.")
		return false
	
	var data: Variant = _read_table(changes)
	if data == null:
		return false
	
	var setting := _registry.get_setting(id)
	if setting == null:
		errors.append("Setting '%s' does not exist." % id)
		return false
	
	var value_type: Variant = data.get(ModSetting.VALUE_TYPE, setting.value_type)
	if typeof(value_type) != TYPE_STRING:
		errors.append("Invalid value_type when updating '%s'." % id)
		return false
	
	_normalize_fields(data, value_type)
	
	return _registry.update(id, data, _current_mod_id)


func _lua_force(id: Variant, value: Variant) -> bool:
	if typeof(id) != TYPE_STRING:
		errors.append("Setting ID must be a string.")
		return false
	
	var setting := _registry.get_setting(id)
	if setting == null:
		errors.append("Setting '%s' does not exist." % id)
		return false
	
	if setting.value_type == ModSetting.COLOR:
		value = _convert_color(value)
	
	return _registry.force(id, value, _current_mod_id)
	


func _read_table(value: Variant) -> Variant:
	if not value is LuaTable:
		errors.append("Expected a Lua Table.")
		return null
	return value.to_dictionary()


func _normalize_fields(data: Dictionary, value_type: String) -> void:
	if data.has(ModSetting.ALLOWED_VALUES) and data[ModSetting.ALLOWED_VALUES] is LuaTable:
		data[ModSetting.ALLOWED_VALUES] = data[ModSetting.ALLOWED_VALUES].to_array()
	
	if value_type == ModSetting.COLOR:
		if data.has(ModSetting.DEFAULT_VALUE):
			data[ModSetting.DEFAULT_VALUE] = _convert_color(data[ModSetting.DEFAULT_VALUE])
			
		if data.has(ModSetting.FORCED_VALUE):
			data[ModSetting.FORCED_VALUE] = _convert_color(data[ModSetting.FORCED_VALUE])


func _convert_color(value: Variant) -> Variant:
	if not value is LuaTable:
		return value
	
	var data = value.to_dictionary()
	for field in ["r", "g", "b"]:
		if not data.has(field):
			return value
		
		if typeof(data[field]) != TYPE_FLOAT and typeof(data[field]) != TYPE_INT:
			return value
	
	var alpha: Variant = data.get("a", 1.0)
	if typeof(alpha) != TYPE_FLOAT and typeof(alpha) != TYPE_INT:
		return value
	
	return Color(float(data["r"]), float(data["g"]), float(data["b"]), float(alpha))







#
