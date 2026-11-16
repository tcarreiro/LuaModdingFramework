@tool
class_name ModSetting extends RefCounted

# Types
const BOOL := "bool"
const INT := "int"
const DOUBLE := "double"
const STRING := "string"
const COLOR := "color"

# Scopes
const STARTUP := "startup"
const RUNTIME_GLOBAL := "runtime-global"
const RUNTIME_PER_USER := "runtime-per-user"

# Properties
const ID := "id"
const DISPLAY_NAME := "display_name"
const DESCRIPTION := "description"
const ORDER := "order"
const VALUE_TYPE := "value_type"
const SCOPE := "scope"
const DEFAULT_VALUE := "default_value"
const FORCED_VALUE := "forced_value"
const ALLOWED_VALUES := "allowed_values"
const MINIMUM_VALUE := "minimum_value"
const MAXIMUM_VALUE := "maximum_value"
const ALLOW_BLANK := "allow_blank"
const HIDDEN := "hidden"

const VALUE_TYPES := [BOOL, INT, DOUBLE, STRING, COLOR]
# scope is for future-proof. Not in use right now
const SCOPES := ["startup", "runtime-global", "runtime-per-user"]
# startup: defined before game session and is immutable
# runtime-global: belongs to the game session and is mutable
# runtime-per-user: belongs to the player

var id: String
var display_name: String
var description: String = ""
var order: String = ""

var value_type: String = STRING
var scope: String = "startup"

var default_value: Variant = null
var forced_value: Variant = null
var allowed_values: Array = []

var minimum_value: Variant = null
var maximum_value: Variant = null
var allow_blank: bool = false
var hidden: bool = false

var owner_mod_id: String = ""
var last_modified_by: String = ""
var forced_by_mod_id: String = ""

func get_effective_value() -> Variant:
	return forced_value if is_forced() else default_value


func is_forced() -> bool:
	return forced_value != null


func validate() -> String:
	# ID mandatory
	if id.strip_edges().is_empty():
		return "Setting ID cannot be empty."
	
	if not VALUE_TYPES.has(value_type):
		return "Invalid value_type '%s'."%value_type
	
	if not SCOPES.has(scope):
		return "Invalid setting scope '%s'."%scope
	
	if value_type != INT and value_type != DOUBLE:
		if minimum_value != null or maximum_value != null:
			return "Minimum and Maximum values are only supported for numeric settings."
	
	if value_type != INT and value_type != DOUBLE and value_type != STRING:
		if not allowed_values.is_empty():
			return "Allowed values are not supported for '%s' settings."%value_type
	
	if minimum_value != null and not _matches_type(minimum_value):
		return "Invalid minimum value type."
	
	if maximum_value != null and not _matches_type(maximum_value):
		return "Invalid maximum value type."
	
	if minimum_value != null and maximum_value != null:
		if float(minimum_value) > float(maximum_value):
			return "Minimum value cannot be greater than maximum value"
	
	for value in allowed_values:
		var error:= validate_value(value)
		if not error.is_empty():
			return "Invalid allowed value: '%s'" % error
	
	var default_error:= validate_value(default_value)
	if not default_error.is_empty():
		return "Invalid default value: '%s'" % default_error
	
	if is_forced():
		if not hidden:
			return "A forced settings must be hidden."
		
		var forced_error:= validate_value(forced_value)
		if not forced_error.is_empty():
			return "Invalid forced value: '%s'" % forced_error
	
	return ""


func validate_value(value: Variant, check_allowed_values: bool = true) -> String:
	if not _matches_type(value):
		return "Expected '%s' value."%value_type
	
	if value_type == STRING and not allow_blank:
		if String(value).strip_edges().is_empty():
			return "Blank strings are not allowed."
	
	if value_type == INT or value_type == DOUBLE:
		if minimum_value != null and float(value) < float(minimum_value):
			return "Value is below the minimum."
	
	if value_type == INT or value_type == DOUBLE:
		if maximum_value != null and float(value) > float(maximum_value):
			return "Value exceeds the maximum."
	
	if check_allowed_values and not allowed_values.is_empty():
		if not allowed_values.has(value):
			return "Value is not included in allowed_values."
	
	return ""


func _matches_type(value: Variant) -> bool:
	match value_type:
		BOOL:
			return typeof(value) == TYPE_BOOL
		INT:
			return typeof(value) == TYPE_INT
		DOUBLE:
			return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT
		STRING:
			return typeof(value) == TYPE_STRING
		COLOR:
			return typeof(value) == TYPE_COLOR
	return false


func clone() -> ModSetting:
	var result := ModSetting.new()
	
	for prop in get_property_list():
		if prop.type == TYPE_DICTIONARY or prop.type == TYPE_ARRAY:
			result.set(prop.name, get(prop.name).duplicate(true))
		else:
			result.set(prop.name, get(prop.name))
	
	return result
