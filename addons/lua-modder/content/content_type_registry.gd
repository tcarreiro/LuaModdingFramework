@tool
class_name ContentTypeRegistry extends RefCounted

const TEMPLATE := "template"
const STRUCT := "struct"

var errors: Array[String] = []
var _registered: Dictionary[String, Dictionary] = {}

func register_type(type_id: String, template_script: Script, validator: Callable = Callable()) -> bool:
	return _register(type_id, template_script, validator, TEMPLATE)


func register_struct(type_id: String, struct_script: Script, validator: Callable = Callable()) -> bool:
	return _register(type_id, struct_script, validator, STRUCT)


func _register(type_id: String, script: Script, validator: Callable, kind: String) -> bool:
	if not _is_valid_type_id(type_id):
		errors.append("Invalid content type ID '%s'." % type_id)
		return false
	
	if _registered.has(type_id):
		errors.append("Content type '%s' is already registered." % type_id)
		return false
	
	if script == null or not script.can_instantiate():
		errors.append("Content type '%s' requires a valid instantiable Script." % type_id)
		return false
	
	if not validator.is_null() and not validator.is_valid():
		errors.append("Invalid validator for content type '%s'." % type_id)
		return false
	
	var properties: Dictionary = {}
	for property in script.get_script_property_list():
		var usage: int = property.get("usage", 0)
		
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		
		var property_name: String = property.get("name", "")
		properties[property_name] = property.duplicate(true)
	
	_registered[type_id] = {
		"kind": kind,
		"script": script,
		"validator": validator,
		"properties": properties,
		"references": {},
	}
	return true


func validate_references() -> bool:
	var valid:= true
	
	for type_id in _registered:
		var references: Dictionary = _registered[type_id]["references"]
		for property_name in references:
			var target_type: String = references[property_name]
			
			if not has_type(target_type):
				errors.append("Reference '%s.%s' targets unknown template '%s'." % [
					type_id, property_name, target_type
				])
				valid = false
	
	return valid


func register_reference(owner_type: String, property_name: String, target_type: String) -> bool:
	if not _registered.has(owner_type):
		errors.append("Content type '%s' is not registered." % owner_type)
		return false
	
	if not _is_valid_type_id(target_type):
		errors.append("Invalid reference target '%s'." % target_type)
		return false
	
	var properties: Dictionary = _registered[owner_type]["properties"]
	if not properties.has(property_name):
		errors.append("Property '%s' does not exist in content type '%s'." % [
			property_name, owner_type
		])
		return false
	
	var property_type: int = properties[property_name].get("type", TYPE_NIL)
	if property_type != TYPE_STRING and property_type != TYPE_STRING_NAME:
		errors.append("Reference property '%s.%s' must be a String or StringName." % [
			owner_type, property_name
		])
		return false
	
	var references: Dictionary = _registered[owner_type]["references"]
	if references.has(property_name):
		errors.append("Reference '%s.%s' is already registered." % [
			owner_type, property_name
		])
		return false
	
	references[property_name] = target_type
	return true


func has_type(type_id: String) -> bool:
	return _registered.has(type_id) and _registered[type_id]["kind"] == TEMPLATE


func has_struct(type_id: String) -> bool:
	return _registered.has(type_id) and _registered[type_id]["kind"] == STRUCT


func get_registered_script(type_id: String) -> Script:
	if not _registered.has(type_id):
		return null
	return _registered[type_id]["script"]


func get_properties(type_id: String) -> Dictionary:
	if not _registered.has(type_id):
		return {}
	
	var properties: Dictionary = _registered[type_id]["properties"]
	return properties.duplicate(true)


func get_reference_target(owner_type: String, property_name: String) -> String:
	if not _registered.has(owner_type):
		return ""
	
	var references: Dictionary = _registered[owner_type]["references"]
	return references.get(property_name, "")


func get_registered_types() -> Array[String]:
	return _get_registered_ids(TEMPLATE)


func get_registered_structs() -> Array[String]:
	return _get_registered_ids(STRUCT)


func _get_registered_ids(kind: String) -> Array[String]:
	var result: Array[String] = []
	
	for type_id in _registered:
		if _registered[type_id]["kind"] == kind:
			result.append(type_id)
	
	result.sort()
	return result


func validate_custom(type_id: String, data: Dictionary) -> String:
	if not _registered.has(type_id):
		return "Unknown content type '%s'." % type_id
	
	var validator: Callable = _registered[type_id]["validator"]
	if validator.is_null():
		return ""
	
	if not validator.is_valid():
		return "Validator for '%s' is no longer valid." % type_id
	
	var result: Variant = validator.call(data.duplicate(true))
	if typeof(result) != TYPE_STRING:
		return "Validator for '%s' must return a String." % type_id
	
	return result


func _is_valid_type_id(type_id: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9_-]+$")
	return regex.search(type_id) != null


func clear() -> void:
	_registered.clear()
	errors.clear()


#
