@tool
class_name ContentTypeRegistry extends RefCounted

const TEMPLATE := "template"
const STRUCT := "struct"

var errors: Array[String] = []
var _registered: Dictionary[String, Dictionary] = {}

func register_type(type_id: String, template_script: Script, validator: Callable = Callable(), parent_type_id: String = "") -> bool:
	return _register(type_id, template_script, validator, TEMPLATE, parent_type_id)


func register_struct(type_id: String, struct_script: Script, validator: Callable = Callable()) -> bool:
	return _register(type_id, struct_script, validator, STRUCT, "")


func _register(type_id: String, script: Script, validator: Callable, kind: String, parent_type_id: String) -> bool:
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

	if not parent_type_id.is_empty():
		if kind != TEMPLATE or not _is_valid_type_id(parent_type_id):
			errors.append("Invalid parent Template '%s' for '%s'." % [parent_type_id, type_id])
			return false

	var properties := _get_script_properties(script)

	_registered[type_id] = {
		"kind": kind,
		"parent_type_id": parent_type_id,
		"script": script,
		"validator": validator,
		"properties": properties,
		"struct_bindings": {},
		"references": {},
	}
	return true


func _get_script_properties(script: Script) -> Dictionary:
	var hierarchy: Array[Script] = []
	var current: Script = script

	while current != null:
		hierarchy.push_front(current)
		current = current.get_base_script()

	var properties: Dictionary = {}
	for ancestor in hierarchy:
		for property in ancestor.get_script_property_list():
			var usage: int = property.get("usage", 0)
			if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
				continue
			if (usage & PROPERTY_USAGE_STORAGE) == 0:
				continue
			var property_name: String = property.get("name", "")
			properties[property_name] = property.duplicate(true)

	return properties


func _get_inferred_parent_candidates(type_id: String) -> Array[String]:
	var candidates: Array[String] = []
	if not has_type(type_id):
		return candidates

	var script: Script = _registered[type_id]["script"]
	var ancestor := script.get_base_script()

	while ancestor != null:
		for candidate_id in get_registered_types():
			if candidate_id != type_id and _registered[candidate_id]["script"] == ancestor:
				candidates.append(candidate_id)
		if not candidates.is_empty():
			return candidates
		ancestor = ancestor.get_base_script()

	return candidates


func get_parent_type(type_id: String) -> String:
	if not has_type(type_id):
		return ""

	var declared_parent: String = _registered[type_id]["parent_type_id"]
	if not declared_parent.is_empty():
		return declared_parent

	var candidates := _get_inferred_parent_candidates(type_id)
	return candidates[0] if candidates.size() == 1 else ""


func get_type_lineage(type_id: String) -> Array[String]:
	var lineage: Array[String] = []
	if not has_type(type_id):
		return lineage

	var visited: Dictionary = {}
	var current := type_id
	while not current.is_empty():
		if visited.has(current) or not has_type(current):
			return []
		visited[current] = true
		lineage.push_front(current)
		current = get_parent_type(current)

	return lineage


func is_subtype(type_id: String, parent_type: String) -> bool:
	if not has_type(parent_type):
		return false
	return get_type_lineage(type_id).has(parent_type)


func get_derived_types(parent_type: String) -> Array[String]:
	var result: Array[String] = []
	if not has_type(parent_type):
		return result

	for candidate_id in get_registered_types():
		if is_subtype(candidate_id, parent_type):
			result.append(candidate_id)

	return result


func get_root_type(type_id: String) -> String:
	var lineage := get_type_lineage(type_id)
	return lineage[0] if not lineage.is_empty() else ""


func validate_inheritance() -> bool:
	var valid := true

	for type_id in get_registered_types():
		var declared_parent: String = _registered[type_id]["parent_type_id"]
		if declared_parent.is_empty() and _get_inferred_parent_candidates(type_id).size() > 1:
			errors.append("Template '%s' has ambiguous GDScript parents; declare its parent explicitly." % type_id)
			valid = false
			continue

		var parent_type := get_parent_type(type_id)
		if not parent_type.is_empty() and not has_type(parent_type):
			errors.append("Template '%s' has unknown parent Template '%s'." % [type_id, parent_type])
			valid = false
			continue

		if get_type_lineage(type_id).is_empty():
			errors.append("Template inheritance cycle detected for '%s'." % type_id)
			valid = false

	return valid


func validate_references() -> bool:
	var valid:= true
	
	for type_id in _registered:
		var references: Dictionary = _get_registered_references(type_id)
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
	
	var properties := get_properties(owner_type)
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
	
	var references: Dictionary = _get_registered_references(owner_type)
	if references.has(property_name):
		errors.append("Reference '%s.%s' is already registered." % [
			owner_type, property_name
		])
		return false
	
	references[property_name] = target_type
	return true



func register_struct_binding(owner_type: String, property_name: String, struct_type: String) -> bool:
	if not _registered.has(owner_type):
		errors.append("Content type '%s' is not registered." % owner_type)
		return false

	if not _is_valid_type_id(struct_type):
		errors.append("Invalid Struct type ID '%s'." % struct_type)
		return false

	var properties := get_properties(owner_type)

	if not properties.has(property_name):
		errors.append("Property '%s' does not exist in content type '%s'." % [property_name, owner_type])
		return false

	var property_info: Dictionary = properties[property_name]
	var property_type: int = property_info.get("type", TYPE_NIL)

	if property_type not in [TYPE_OBJECT, TYPE_DICTIONARY, TYPE_ARRAY]:
		errors.append("Property '%s.%s' cannot contain a Struct." % [owner_type, property_name])
		return false

	if property_type == TYPE_ARRAY and property_info.get("hint", PROPERTY_HINT_NONE) == PROPERTY_HINT_TYPE_STRING:
		var hint_string: String = property_info.get("hint_string", "")
		var element_type_string := hint_string.get_slice(":", 0).get_slice("/", 0)

		if element_type_string.is_valid_int():
			var element_type := int(element_type_string)

			if element_type not in [TYPE_OBJECT, TYPE_DICTIONARY]:
				errors.append("Property '%s.%s' has an incompatible array element type." % [owner_type, property_name])
				return false

	var bindings: Dictionary = _get_registered_struct_bindings(owner_type)

	if bindings.has(property_name):
		errors.append("Struct binding '%s.%s' is already registered." % [owner_type, property_name])
		return false

	bindings[property_name] = {
		"struct_type": struct_type,
		"is_array": property_type == TYPE_ARRAY
	}

	return true


func validate_struct_bindings() -> bool:
	var valid := true

	for type_id in _registered:
		var bindings: Dictionary = _get_registered_struct_bindings(type_id)

		for property_name in bindings:
			var binding: Dictionary = bindings[property_name]
			var struct_type: String = binding["struct_type"]

			if not has_struct(struct_type):
				errors.append("Struct binding '%s.%s' targets unknown Struct '%s'." % [type_id, property_name, struct_type])
				valid = false

	return valid


func has_type(type_id: String) -> bool:
	return _registered.has(type_id) and _get_registered_kind(type_id) == TEMPLATE


func has_struct(type_id: String) -> bool:
	return _registered.has(type_id) and _get_registered_kind(type_id) == STRUCT


func get_registered_script(type_id: String) -> Script:
	if not _registered.has(type_id):
		return null
	return _registered[type_id]["script"]


func get_properties(type_id: String) -> Dictionary:
	if has_struct(type_id):
		return _get_registered_properties(type_id).duplicate(true)

	var properties: Dictionary = {}
	for ancestor in get_type_lineage(type_id):
		var own_properties: Dictionary = _get_registered_properties(ancestor)
		for property_name in own_properties:
			properties[property_name] = own_properties[property_name].duplicate(true)
	return properties


func get_reference_target(owner_type: String, property_name: String) -> String:
	var lineage := get_type_lineage(owner_type)
	if has_struct(owner_type):
		lineage.append(owner_type)
	lineage.reverse()
	for ancestor in lineage:
		var references: Dictionary = _get_registered_references(ancestor)
		if references.has(property_name):
			return references[property_name]
	return ""


func get_registered_types() -> Array[String]:
	return _get_registered_ids(TEMPLATE)


func get_registered_structs() -> Array[String]:
	return _get_registered_ids(STRUCT)


func _get_registered_ids(kind: String) -> Array[String]:
	var result: Array[String] = []
	
	for type_id in _registered:
		if _get_registered_kind(type_id) == kind:
			result.append(type_id)
	
	result.sort()
	return result


func get_struct_binding(owner_type: String, property_name: String) -> Dictionary:
	if not _registered.has(owner_type):
		return {}

	var lineage := get_type_lineage(owner_type)
	if has_struct(owner_type):
		lineage.append(owner_type)
	lineage.reverse()
	for ancestor in lineage:
		var bindings: Dictionary = _get_registered_struct_bindings(ancestor)
		if bindings.has(property_name):
			var binding: Dictionary = bindings[property_name]
			return binding.duplicate(true)

	var properties := get_properties(owner_type)
	if not properties.has(property_name):
		return {}
	
	var property: Dictionary = properties[property_name]
	var property_type: int = property.get("type", TYPE_NIL)
	var hint: int = property.get("hint", PROPERTY_HINT_NONE)
	var hint_string: String = property.get("hint_string", "")
	
	var class_name_hint := ""
	var is_array := false
	
	match property_type:
		TYPE_OBJECT:
			if hint != PROPERTY_HINT_RESOURCE_TYPE:
				return {}
			class_name_hint = hint_string
		TYPE_ARRAY:
			if hint != PROPERTY_HINT_TYPE_STRING:
				return {}
			
			var separator := hint_string.find(":")
			if separator < 0:
				return {}
			
			var type_info := hint_string.substr(0, separator).split("/")
			if type_info.is_empty() or not type_info[0].is_valid_int():
				return {}
			
			if int(type_info[0]) != TYPE_OBJECT:
				return {}
			
			class_name_hint = hint_string.substr(separator + 1)
			is_array = true
		_:
			return {}
	
	for struct_id in get_registered_structs():
		var struct_script := get_registered_script(struct_id)
		
		if String(struct_script.get_global_name()) == class_name_hint:
			return {
				"struct_type": struct_id,
				"is_array": is_array
			}
	
	return {}


func _get_registered_properties(type_id: String) -> Dictionary:
	if not _registered.has(type_id):
		return {}
	return _registered[type_id]["properties"]


func _get_registered_references(type_id: String) -> Dictionary:
	if not _registered.has(type_id):
		return {}
	return _registered[type_id]["references"]


func _get_registered_kind(type_id: String) -> String:
	if not _registered.has(type_id):
		return ""
	return _registered[type_id]["kind"]


func _get_registered_struct_bindings(type_id: String) -> Dictionary:
	if not _registered.has(type_id):
		return {}
	return _registered[type_id]["struct_bindings"]


func _get_registered_validator(type_id: String) -> Callable:
	if not _registered.has(type_id):
		return Callable()
	return _registered[type_id]["validator"]


func validate_custom(type_id: String, data: Dictionary) -> String:
	if not _registered.has(type_id):
		return "Unknown content type '%s'." % type_id

	var lineage: Array[String] = get_type_lineage(type_id)
	if not has_type(type_id):
		lineage.append(type_id)
	for ancestor in lineage:
		var validator: Callable = _get_registered_validator(ancestor)
		if validator.is_null():
			continue
		if not validator.is_valid():
			return "Validator for '%s' is no longer valid." % ancestor

		var result: Variant = validator.call(data.duplicate(true))
		if typeof(result) != TYPE_STRING:
			return "Validator for '%s' must return a String." % ancestor
		if not result.is_empty():
			return "[%s] %s" % [ancestor, result]

	return ""


func _is_valid_type_id(type_id: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9_-]+$")
	return regex.search(type_id) != null


func clear() -> void:
	_registered.clear()
	errors.clear()
