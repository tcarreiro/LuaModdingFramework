@tool
class_name LuaUtils extends RefCounted

const MAX_FLOAT := 9007199254740991.0

# Should match type, VM and pointer
static func same_lua_object(lua_state: LuaState, left: Variant, right: Variant) -> bool:
	if lua_state == null or not left is LuaObject or not right is LuaObject:
		return false
	
	if left.get_class() != right.get_class():
		return false
	
	return left.get_lua_state() == lua_state \
		and right.get_lua_state() == lua_state \
		and left.get_pointer_value() == right.get_pointer_value()


static func read_table(value: Variant) -> Variant:
	if not value is LuaTable:
		return null
	return value.to_dictionary()


static func normalize_fields(data: Dictionary, array_fields: Array, color_fields: Array = [], integer_fields: Array = []) -> void:
	for field in array_fields:
		if data.has(field) and data[field] is LuaTable:
			data[field] = data[field].to_array()
	
	for field in color_fields:
		if data.has(field):
			data[field] = convert_color(data[field])
	
	for field in integer_fields:
		if not data.has(field):
			continue
	
		var value: Variant = data[field]
		if value is Array:
			for i in range(value.size()):
				value[i] = normalize_integer(value[i])
		else:
			data[field] = normalize_integer(value)


static func normalize_integer(value: Variant) -> Variant:
	if typeof(value) != TYPE_FLOAT:
		return value
	
	var number: float = value
	if not is_finite(number) or number != floorf(number):
		return value
	
	if absf(number) > MAX_FLOAT:
		return value
	
	return int(number)


static func convert_color(value: Variant) -> Variant:
	var data: Dictionary
	if value is LuaTable:
		data = value.to_dictionary()
	elif typeof(value) == TYPE_DICTIONARY:
		data = value
	else:
		return value
	
	for field in ["r", "g", "b"]:
		if not data.has(field):
			return value
		if typeof(data[field]) != TYPE_FLOAT and typeof(data[field]) != TYPE_INT:
			return value
	var alpha: Variant = data.get("a", 1.0)
	if typeof(alpha) != TYPE_FLOAT and typeof(alpha) != TYPE_INT:
		return value
	
	return Color(float(data["r"]), float(data["g"]), float(data["b"]), float(alpha))


static func to_lua_value(lua_state: LuaState, value: Variant) -> Variant:
	if value is LuaTable:
		return value
	
	if typeof(value) == TYPE_COLOR:
		var color: Color = value
		return to_lua_value(lua_state, {
			"r": color.r,
			"g": color.g,
			"b": color.b,
			"a": color.a
		})
	
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		var result := lua_state.create_table()
		for key in data:
			result.rawset(key, to_lua_value(lua_state, data[key]))
		return result
	
	if typeof(value) == TYPE_ARRAY:
		var elements: Array = value
		var result := lua_state.create_table()
		for i in range(elements.size()):
			result.rawset(i + 1, to_lua_value(lua_state, elements[i]))
		return result
	
	return value


static func load_json(errors_array: Array[String], path: String, max_bytes_size: int = 0, mandatory_array: bool = true) -> JSON:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors_array.append("Cannot open JSON: '%s'." % path)
		return null
	
	if max_bytes_size > 0 and file.get_length() > max_bytes_size:
		errors_array.append("JSON file exceeds maximum allowed size: '%s'." % path)
		return null
	
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		errors_array.append("Invalid JSON in '%s' at line %d: %s" % [
			path, json.get_error_line(), json.get_error_message()
		])
		return null
	
	if mandatory_array and typeof(json.data) != TYPE_ARRAY:
		errors_array.append("JSON must contain an array: '%s'." % path)
		return null
	return json


static func get_lua_content_file(errors_array: Array[String], path: String, max_bytes_size: int = 0) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors_array.append("Cannot open Lua script: '%s'." % path)
		return ""
	
	if max_bytes_size > 0 and file.get_length() > max_bytes_size:
		errors_array.append("LUA file exceeds maximum allowed size: '%s'." % path)
		return ""
	
	return file.get_as_text()
