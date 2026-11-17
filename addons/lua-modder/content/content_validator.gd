class_name ContentValidator extends RefCounted

var errors: Array[String] = []

var _types: ContentTypeRegistry
var _normalized_data: Dictionary = {}


func _init(content_types: ContentTypeRegistry) -> void:
	_types = content_types


func validate(type_id: String, data: Dictionary) -> bool:
	errors.clear()
	_normalized_data.clear()

	if not _types.has_type(type_id):
		errors.append("Unknown Template type '%s'." % type_id)
		return false

	var path := "%s[%s]" % [type_id, str(data.get("id", "?"))]
	var result := _validate_object(type_id, data, path, true)

	if not errors.is_empty():
		return false

	_normalized_data = result
	return true


func validate_struct(type_id: String, data: Dictionary) -> bool:
	errors.clear()
	_normalized_data.clear()

	if not _types.has_struct(type_id):
		errors.append("Unknown Struct type '%s'." % type_id)
		return false

	var result := _validate_object(type_id, data, type_id, false)

	if not errors.is_empty():
		return false

	_normalized_data = result
	return true


func get_normalized_data() -> Dictionary:
	return _normalized_data.duplicate(true)


func _validate_object(type_id: String, data: Dictionary, path: String, is_template: bool) -> Dictionary:
	var result := data.duplicate(true)
	var properties := _types.get_properties(type_id)
	var previous_errors := errors.size()

	for raw_key in data:
		if typeof(raw_key) != TYPE_STRING and typeof(raw_key) != TYPE_STRING_NAME:
			errors.append("%s: property names must be strings." % path)
			continue

		var property_name := String(raw_key)
		var property_path := "%s.%s" % [path, property_name]
		var value: Variant = data[raw_key]

		if is_template and property_name == "type":
			if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
				errors.append("%s: type must be a string." % property_path)
			elif String(value) != type_id:
				errors.append("%s: expected '%s', received '%s'." % [property_path, type_id, str(value)])
			continue

		if not properties.has(property_name):
			errors.append("%s: unknown property." % property_path)
			continue

		var property_info: Dictionary = properties[property_name]
		var struct_binding := _types.get_struct_binding(type_id, property_name)

		if not struct_binding.is_empty():
			result[raw_key] = _validate_struct_value(value, struct_binding, property_path)
		else:
			result[raw_key] = _validate_content_property(value, property_info, property_path)

	if errors.size() == previous_errors:
		var validation_error := _types.validate_custom(type_id, result)

		if not validation_error.is_empty():
			errors.append("%s: %s" % [path, validation_error])

	return result


func _validate_struct_value(value: Variant, binding: Dictionary, path: String) -> Variant:
	var struct_id: String = binding["struct_type"]
	var is_array: bool = binding["is_array"]

	if is_array:
		if typeof(value) != TYPE_ARRAY:
			_add_type_error(path, TYPE_ARRAY, value)
			return value

		var result: Array = []

		for index in range(value.size()):
			result.append(_validate_struct_item(struct_id, value[index], "%s[%d]" % [path, index]))

		return result

	return _validate_struct_item(struct_id, value, path)


func _validate_struct_item(struct_id: String, value: Variant, path: String) -> Variant:
	if value == null:
		return null

	if typeof(value) != TYPE_DICTIONARY:
		_add_type_error(path, TYPE_DICTIONARY, value)
		return value

	return _validate_object(struct_id, value, path, false)


func _validate_content_property(value: Variant, property_info: Dictionary, path: String) -> Variant:
	var expected_type: int = property_info.get("type", TYPE_NIL)

	if expected_type == TYPE_ARRAY:
		if typeof(value) != TYPE_ARRAY:
			_add_type_error(path, TYPE_ARRAY, value)
			return value

		var element_types := _get_array_element_types(property_info)
		return _validate_array(value, element_types, 0, path)

	return _validate_scalar(value, expected_type, path)


func _get_array_element_types(property_info: Dictionary) -> Array[int]:
	var result: Array[int] = []

	if property_info.get("hint", PROPERTY_HINT_NONE) != PROPERTY_HINT_TYPE_STRING:
		return result

	var hint_string: String = property_info.get("hint_string", "")
	var segments := hint_string.split(":")

	for index in range(segments.size() - 1):
		var type_token := segments[index].get_slice("/", 0)

		if not type_token.is_valid_int():
			return []

		result.append(int(type_token))

	return result


func _validate_array(value: Array, element_types: Array[int], level: int, path: String) -> Array:
	if level >= element_types.size():
		return value.duplicate(true)

	var expected_type := element_types[level]
	var result: Array = []

	for index in range(value.size()):
		var item: Variant = value[index]
		var item_path := "%s[%d]" % [path, index]

		if expected_type == TYPE_ARRAY:
			if typeof(item) != TYPE_ARRAY:
				_add_type_error(item_path, TYPE_ARRAY, item)
				result.append(item)
			else:
				result.append(_validate_array(item, element_types, level + 1, item_path))

		elif expected_type == TYPE_OBJECT:
			errors.append("%s: object array requires a registered Struct binding." % item_path)
			result.append(item)

		else:
			result.append(_validate_scalar(item, expected_type, item_path))

	return result


func _validate_scalar(value: Variant, expected_type: int, path: String) -> Variant:
	if expected_type == TYPE_NIL:
		return value

	match expected_type:
		TYPE_INT:
			var normalized := LuaUtils.normalize_integer(value)
			if typeof(normalized) == TYPE_INT:
				return normalized
		TYPE_FLOAT:
			if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
				var number := float(value)
				if is_finite(number):
					return number
		TYPE_STRING_NAME:
			if typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME:
				return StringName(value)
		TYPE_COLOR:
			return _validate_color(value, path)
		_:
			if typeof(value) == expected_type:
				return value
	_add_type_error(path, expected_type, value)
	return value


func _validate_color(value: Variant, path: String) -> Variant:
	if typeof(value) == TYPE_COLOR:
		return value
	
	if typeof(value) != TYPE_DICTIONARY:
		_add_type_error(path, TYPE_COLOR, value)
		return value
	
	for channel in ["r", "g", "b"]:
		if not value.has(channel):
			errors.append("%s: missing color channel '%s'." % [path, channel])
			return value
	
	for channel in ["r", "g", "b", "a"]:
		if not value.has(channel):
			continue
	
		var component: Variant = value[channel]
		if typeof(component) != TYPE_INT and typeof(component) != TYPE_FLOAT:
			errors.append("%s.%s: color channel must be numeric." % [path, channel])
			return value
	
		if not is_finite(float(component)):
			errors.append("%s.%s: color channel must be finite." % [path, channel])
			return value
	
	return Color(
		float(value["r"]),
		float(value["g"]),
		float(value["b"]),
		float(value.get("a", 1.0))
	)


func _add_type_error(path: String, expected_type: int, value: Variant) -> void:
	errors.append("%s: expected %s, received %s." % [
		path, type_string(expected_type), type_string(typeof(value))
	])
