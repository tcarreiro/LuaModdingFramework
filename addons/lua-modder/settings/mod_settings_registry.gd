@tool
class_name ModSettingsRegistry extends RefCounted

const EDITABLE_FIELDS := [
	"display_name", "description", "order", "value_type", "scope", "default_value",
	"forced_value", "allowed_values", "minimum_value", "maximum_value", "allow_blank",
	"hidden",
]

var errors: Array[String] = []
var warnings: Array[String] = []

var _settings: Dictionary[String, ModSetting] = {}

func register(setting: ModSetting, mod_id: String) -> bool:
	if setting == null:
		errors.append("Cannot register a null setting.")
		return false
	
	if mod_id.strip_edges().is_empty():
		errors.append("Setting '%s' has an invalid mod ID." % setting.id)
		return false
	
	if _settings.has(setting.id):
		errors.append("Setting '%s' is already registered." % setting.id)
		return false
	
	var registered := setting.clone()
	registered.owner_mod_id = mod_id
	registered.last_modified_by = mod_id
	
	if registered.is_forced():
		registered.forced_by_mod_id = mod_id
	
	var error := registered.validate()
	if not error.is_empty():
		errors.append("Setting '%s': %s" % [registered.id, error])
		return false
	
	_settings[registered.id] = registered
	return true


func update(id: String, changes: Dictionary, mod_id: String) -> bool:
	if not _settings.has(id):
		errors.append("Setting '%s' doesn't exist." % id)
		return false
	
	if mod_id.strip_edges().is_empty():
		errors.append("Invalid mod ID when updating '%s'." % id)
		return false
	
	if changes.is_empty():
		return true
	
	var current := _settings[id]
	var updated := current.clone()
	
	for field in changes:
		if not EDITABLE_FIELDS.has(field):
			errors.append("Property '%s' cannot be modified on setting '%s'." % [field, id])
			return false
		
		var value: Variant = changes[field]
		
		if field == "allowed_values":
			if typeof(value) != TYPE_ARRAY:
				errors.append("Property 'allowed_values' must be an Array.")
				return false
			
			updated.allowed_values = value.duplicate(true)
			continue
		
		if field == "hidden" or field == "allow_blank":
			if typeof(value) != TYPE_BOOL:
				errors.append("Property '%s' must be a boolean." % field)
				return false
		
		if field in ["display_name", "description", "order", "value_type", "scope"]:
			if typeof(field) != TYPE_STRING:
				errors.append("Property '%s' must be a string." % field)
				return false
		
		updated.set(field, value)
	
	if changes.has("forced_value"):
		updated.forced_by_mod_id = mod_id if updated.is_forced() else ""
	
	updated.last_modified_by = mod_id
	
	var error := updated.validate()
	if not error.is_empty():
		errors.append("Cannot update setting '%s': '%s'" % [id, error])
		return false
	
	if changes.has("forced_value") and current.is_forced() and updated.is_forced():
		if current.forced_value != updated.forced_value and current.forced_by_mod_id != mod_id:
			warnings.append("Setting '%s': mod '%s' overrides value forced by mod '%s'." % [
				id, mod_id, current.forced_by_mod_id
			])
	
	_settings[id] = updated
	return true


func force(id: String, value: Variant, mod_id: String) -> bool:
	return update(id, {"forced_value": value, "hidden": true}, mod_id)


func has_setting(id: String) -> bool:
	return _settings.has(id)


func get_setting(id: String) -> ModSetting:
	if not has_setting(id):
		return null
	return _settings[id].clone()


func get_effective_value(id: String) -> Variant:
	if not has_setting(id):
		return null
	return _settings[id].get_effective_value()


func validate_player_value(id: String, value: Variant) -> String:
	if not has_setting(id):
		return "Setting '%s' does not exist." % id
	
	var setting := _settings[id]
	
	if setting.is_forced():
		return "Setting '%s' has a forced value." % id
	
	if setting.hidden:
		return "Setting '%s' is hidden." % id
	
	return setting.validate_value(value)


func get_all_settings() -> Array[ModSetting]:
	var result: Array[ModSetting]
	
	for setting in _settings.values():
		result.append(setting.clone())
	
	result.sort_custom(func(a: ModSetting, b:ModSetting) -> bool:
		if a.owner_mod_id != b.owner_mod_id:
			return a.owner_mod_id.naturalcasecmp_to(b.owner_mod_id) < 0
		if a.order != b.order:
			return a.order.naturalcasecmp_to(b.order) < 0
		return a.id.naturalcasecmp_to(b.id) < 0
	)
	
	return result


func get_visible_settings() -> Array[ModSetting]:
	return get_all_settings().filter(func(st: ModSetting) -> bool:
		return not st.hidden
	)


func clear() -> void:
	_settings.clear()
	errors.clear()
	warnings.clear()
