
class_name ContentRegistry extends RefCounted

var errors: Array[String] = []

var _types: ContentTypeRegistry
var _validator: ContentValidator
var _catalog: Dictionary = {}
var _metadata: Dictionary = {}
var _finalized := false


func _init(content_types: ContentTypeRegistry) -> void:
	_types = content_types
	_validator = ContentValidator.new(content_types)


func register_template(data: Dictionary, mod_id: String) -> bool:
	return extend([data], mod_id)


func extend(templates: Array, mod_id: String) -> bool:
	if not _can_modify(mod_id):
		return false

	var initial_error_count := errors.size()
	var pending: Dictionary = {}

	for value in templates:
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("Template must be a Dictionary.")
			continue

		var data: Dictionary = value
		var identity := _read_identity(data)

		if identity.is_empty():
			continue

		var type_id: String = identity["type"]
		var template_id: String = identity["id"]

		if has_template(type_id, template_id):
			errors.append("Template '%s.%s' is already registered." % [type_id, template_id])
			continue

		if not pending.has(type_id):
			pending[type_id] = {}

		var pending_type: Dictionary = pending[type_id]

		if pending_type.has(template_id):
			errors.append("Duplicate Template '%s.%s' in the same batch." % [type_id, template_id])
			continue

		pending_type[template_id] = true

	if errors.size() != initial_error_count:
		return false

	for value in templates:
		var data: Dictionary = value.duplicate(true)
		var type_id: String = String(data["type"])
		var template_id: String = String(data["id"])

		data["type"] = type_id
		data["id"] = template_id

		_insert_template(type_id, template_id, data, mod_id)

	return true


func update(type_id: String, template_id: String, changes: Dictionary, mod_id: String) -> bool:
	if not _can_modify(mod_id):
		return false

	if not has_template(type_id, template_id):
		errors.append("Unknown Template '%s.%s'." % [type_id, template_id])
		return false

	if changes.has("type") or changes.has("id"):
		errors.append("Cannot update the identity of Template '%s.%s'." % [type_id, template_id])
		return false

	var original: Dictionary = _catalog[type_id][template_id]
	var updated := original.duplicate(true)

	_merge_recursive(updated, changes)

	var bucket: Dictionary = _catalog[type_id]
	bucket[template_id] = updated

	_touch(type_id, template_id, mod_id)
	return true


func replace(type_id: String, template_id: String, data: Dictionary, mod_id: String) -> bool:
	if not _can_modify(mod_id):
		return false

	if not has_template(type_id, template_id):
		errors.append("Unknown Template '%s.%s'." % [type_id, template_id])
		return false

	var identity := _read_identity(data)

	if identity.is_empty():
		return false

	if identity["type"] != type_id or identity["id"] != template_id:
		errors.append("Replacement cannot change Template identity '%s.%s'." % [type_id, template_id])
		return false

	var replacement := data.duplicate(true)
	replacement["type"] = type_id
	replacement["id"] = template_id

	var bucket: Dictionary = _catalog[type_id]
	bucket[template_id] = replacement

	_touch(type_id, template_id, mod_id)
	return true


func remove(type_id: String, template_id: String, mod_id: String) -> bool:
	if not _can_modify(mod_id):
		return false

	if not has_template(type_id, template_id):
		errors.append("Unknown Template '%s.%s'." % [type_id, template_id])
		return false

	var bucket: Dictionary = _catalog[type_id]
	bucket.erase(template_id)

	if bucket.is_empty():
		_catalog.erase(type_id)

	var sources: Dictionary = _metadata[type_id]
	sources.erase(template_id)

	if sources.is_empty():
		_metadata.erase(type_id)

	return true


func has_template(type_id: String, template_id: String) -> bool:
	if not _catalog.has(type_id):
		return false

	var bucket: Dictionary = _catalog[type_id]
	return bucket.has(template_id)


func get_template(type_id: String, template_id: String) -> Dictionary:
	if not has_template(type_id, template_id):
		return {}

	var data: Dictionary = _catalog[type_id][template_id]
	return data.duplicate(true)


func get_templates(type_id: String) -> Dictionary:
	if not _catalog.has(type_id):
		return {}

	var bucket: Dictionary = _catalog[type_id]
	return bucket.duplicate(true)


func get_catalog() -> Dictionary:
	return _catalog.duplicate(true)


func get_metadata(type_id: String, template_id: String) -> Dictionary:
	if not _metadata.has(type_id):
		return {}

	var sources: Dictionary = _metadata[type_id]

	if not sources.has(template_id):
		return {}

	var metadata: Dictionary = sources[template_id]
	return metadata.duplicate(true)


func is_finalized() -> bool:
	return _finalized


func finalize() -> bool:
	if _finalized:
		return true

	if not errors.is_empty():
		return false

	if not _validate_type_registry():
		return false

	var normalized_catalog: Dictionary = {}
	var type_ids: Array = _catalog.keys()
	type_ids.sort()

	for type_id in type_ids:
		var bucket: Dictionary = _catalog[type_id]
		var normalized_bucket: Dictionary = {}
		var template_ids: Array = bucket.keys()
		template_ids.sort()

		for template_id in template_ids:
			var data: Dictionary = bucket[template_id]

			if _validator.validate(type_id, data):
				normalized_bucket[template_id] = _validator.get_normalized_data()
			else:
				errors.append_array(_validator.errors)

		normalized_catalog[type_id] = normalized_bucket

	if not errors.is_empty():
		return false

	for type_id in type_ids:
		var bucket: Dictionary = normalized_catalog[type_id]

		for template_id in bucket:
			var data: Dictionary = bucket[template_id]
			var path := "%s[%s]" % [type_id, template_id]

			_validate_object_references(type_id, data, path, normalized_catalog)

	if not errors.is_empty():
		return false

	_catalog = normalized_catalog
	_finalized = true
	return true


func clear() -> void:
	_catalog.clear()
	_metadata.clear()
	errors.clear()
	_finalized = false


func _read_identity(data: Dictionary) -> Dictionary:
	var raw_type: Variant = data.get("type")
	var raw_id: Variant = data.get("id")

	if typeof(raw_type) not in [TYPE_STRING, TYPE_STRING_NAME]:
		errors.append("Template requires a string 'type'.")
		return {}

	if typeof(raw_id) not in [TYPE_STRING, TYPE_STRING_NAME]:
		errors.append("Template requires a string 'id'.")
		return {}

	var type_id := String(raw_type)
	var template_id := String(raw_id)

	if type_id.is_empty() or template_id.strip_edges().is_empty():
		errors.append("Template type and ID cannot be empty.")
		return {}

	if not _types.has_type(type_id):
		errors.append("Unknown Template type '%s'." % type_id)
		return {}

	return {
		"type": type_id,
		"id": template_id
	}


func _insert_template(type_id: String, template_id: String, data: Dictionary, mod_id: String) -> void:
	if not _catalog.has(type_id):
		_catalog[type_id] = {}

	if not _metadata.has(type_id):
		_metadata[type_id] = {}

	var bucket: Dictionary = _catalog[type_id]
	bucket[template_id] = data.duplicate(true)

	var sources: Dictionary = _metadata[type_id]
	sources[template_id] = {
		"owner_mod_id": mod_id,
		"last_modified_by": mod_id
	}


func _touch(type_id: String, template_id: String, mod_id: String) -> void:
	var sources: Dictionary = _metadata[type_id]
	var metadata: Dictionary = sources[template_id]
	metadata["last_modified_by"] = mod_id


func _merge_recursive(target: Dictionary, changes: Dictionary) -> void:
	for key in changes:
		var value: Variant = changes[key]

		if target.has(key) and typeof(target[key]) == TYPE_DICTIONARY and typeof(value) == TYPE_DICTIONARY:
			var nested: Dictionary = target[key]
			_merge_recursive(nested, value)
		elif typeof(value) == TYPE_DICTIONARY or typeof(value) == TYPE_ARRAY:
			target[key] = value.duplicate(true)
		else:
			target[key] = value


func _can_modify(mod_id: String) -> bool:
	if _finalized:
		errors.append("ContentRegistry is finalized and cannot be modified.")
		return false

	if mod_id.strip_edges().is_empty():
		errors.append("Content modification requires a mod ID.")
		return false

	return true


func _validate_type_registry() -> bool:
	if not _types.errors.is_empty():
		errors.append_array(_types.errors)
		return false

	var previous_error_count := _types.errors.size()

	var bindings_valid := _types.validate_struct_bindings()
	var references_valid := _types.validate_references()

	if bindings_valid and references_valid:
		return true

	for index in range(previous_error_count, _types.errors.size()):
		errors.append(_types.errors[index])

	return false


func _validate_object_references(owner_type: String, data: Dictionary, path: String, catalog: Dictionary) -> void:
	for raw_key in data:
		var property_name := String(raw_key)
		var value: Variant = data[raw_key]
		var property_path := "%s.%s" % [path, property_name]

		var target_type := _types.get_reference_target(owner_type, property_name)

		if not target_type.is_empty() and (typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME):
			var target_id := String(value)

			if not target_id.is_empty():
				var target_bucket: Dictionary = catalog.get(target_type, {})

				if not target_bucket.has(target_id):
					errors.append("%s: unknown Reference '%s.%s'." % [property_path, target_type, target_id])

		var binding := _types.get_struct_binding(owner_type, property_name)

		if binding.is_empty():
			continue

		var struct_id: String = binding["struct_type"]

		if binding["is_array"]:
			if typeof(value) != TYPE_ARRAY:
				continue

			for index in range(value.size()):
				if typeof(value[index]) == TYPE_DICTIONARY:
					_validate_object_references(struct_id, value[index], "%s[%d]" % [property_path, index], catalog)
		elif typeof(value) == TYPE_DICTIONARY:
			_validate_object_references(struct_id, value, property_path, catalog)
