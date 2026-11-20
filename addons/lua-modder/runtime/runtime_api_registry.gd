class_name RuntimeApiRegistry extends Registry

const LUA_KEYWORDS := [
	"and", "break", "do", "else", "elseif", "end",
	"false", "for", "function", "goto", "if", "in",
	"local", "nil", "not", "or", "repeat", "return",
	"then", "true", "until", "while"
]

var _functions: Dictionary[String, Callable] = {}
var _identifier_pattern := RegEx.create_from_string("^[A-Za-z_][A-Za-z0-9_]*$")

func register_function(_namespace: String, function_name: String, callback: Callable) -> bool:
	if not _is_valid_namespace(_namespace):
		errors.append("Invalid runtime API namespace '%s'." % _namespace)
		return false
	
	if not _is_valid_identifier(function_name):
		errors.append("Invalid runtime API function name '%s'." % function_name)
		return false
	
	if callback.is_null() or not callback.is_valid():
		errors.append("Invalid Callable for runtime API function '%s'." % function_name)
		return false
	
	var full_name := _get_full_name(_namespace, function_name)
	if _functions.has(full_name):
		errors.append("Runtime API function '%s' is already registered." % full_name)
		return false
	
	for existing_name in _functions:
		if full_name.begins_with(existing_name + ".") or existing_name.begins_with(full_name + "."):
			errors.append("Runtime API path '%s' conflicts with '%s'." % [full_name, existing_name])
			return false
	
	_functions[full_name] = callback
	return true


func has_function(_namespace: String, function_name: String) -> bool:
	return _functions.has(_get_full_name(_namespace, function_name))


func get_function(_namespace: String, function_name: String) -> Callable:
	return _functions.get(_get_full_name(_namespace, function_name), Callable())


func get_functions() -> Dictionary[String, Callable]:
	var result: Dictionary[String, Callable] = {}
	for full_name in _functions:
		result[full_name] = _functions[full_name]
	return result


func clear() -> void:
	_functions.clear()
	errors.clear()


#region private methods
func _get_full_name(_namespace: String, function_name: String) -> String:
	if _namespace.is_empty():
		return function_name
	return "%s.%s" % [_namespace, function_name]


func _is_valid_namespace(_namespace: String) -> bool:
	if _namespace.is_empty():
		return true
	for segment in _namespace.split(".", true):
		if not _is_valid_identifier(segment):
			return false
	return true


func _is_valid_identifier(identifier: String) -> bool:
	if identifier.is_empty() or identifier in LUA_KEYWORDS:
		return false
	return _identifier_pattern.search(identifier) != null
#endregion
