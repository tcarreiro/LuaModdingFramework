class_name UIContentRegistration extends RefCounted

const MAX_DEPTH := 12
const MAX_NODES := 64
const MAX_PROPERTIES := 64
const MAX_STRING_LENGTH := 4096

const PROPERTY_TYPES := {
	"string": TYPE_STRING,
	"bool": TYPE_BOOL,
	"int": TYPE_INT,
	"float": TYPE_FLOAT
}

var errors: Array[String] = []

var _registry: UIComponentRegistry
var _lua_state: LuaState


func _init(registry: UIComponentRegistry, lua_state: LuaState) -> void:
	_registry = registry
	_lua_state = lua_state


func register(mod_id: String, component_id: Variant, descriptor: Variant) -> bool:
	errors.clear()
	if mod_id.is_empty():
		return _fail("UI component registration requires an active mod.")
	
	if typeof(component_id) != TYPE_STRING:
		return _fail("UI component ID must be a string.")
	
	if component_id.length() > 128 or not component_id.begins_with(mod_id + ":"):
		return _fail("UI component '%s' must belong to '%s'." % [component_id, mod_id])
	
	if _registry.is_finalized():
		return _fail("UI components cannot be registered after finalization.")
	
	if not _is_table(descriptor):
		return _fail("UI.define_component expects a definition table.")
	
	var data := (descriptor as LuaTable).to_dictionary()
	if not _validate_keys(data, ["properties", "tree", "events"], "component"):
		return false
	
	if not data.has("tree"):
		return _fail("UI component '%s' requires a tree." % component_id)
	
	var properties := _read_properties(data.get("properties"))
	var budget: Array[int] = [0]
	var tree := _read_tree(data["tree"], 0, budget)
	var routes := _read_events(data.get("events"))
	if not errors.is_empty():
		return false
	
	var definition := UIComponentDefinition.from_template(
		component_id,
		mod_id,
		tree,
		properties
	)
	
	for event_name in routes:
		definition.events.append(StringName(event_name))
	definition.event_routes = routes
	if not _registry.register_template(definition):
		errors.append_array(_registry.errors)
		return false
	
	return true


func _read_properties(value: Variant) -> Dictionary:
	if value == null:
		return {}
	
	if not _is_table(value):
		_fail("UI properties schema must be a table.")
		return {}
	
	var source := (value as LuaTable).to_dictionary()
	var result: Dictionary = {}
	if source.size() > MAX_PROPERTIES:
		_fail("UI component declares too many properties.")
		return {}
	
	for name in source:
		if typeof(name) != TYPE_STRING or name.is_empty():
			_fail("UI property names must be non-empty strings.")
			return {}
	
		if not _is_table(source[name]):
			_fail("UI property '%s' needs a schema table." % name)
			return {}
	
		var schema := (source[name] as LuaTable).to_dictionary()
		if not _validate_keys(schema, ["type", "default", "required", "mod_editable"], name):
			return {}
	
		var type_name: Variant = schema.get("type")
		if typeof(type_name) != TYPE_STRING or not PROPERTY_TYPES.has(type_name):
			_fail("Unsupported UI property type for '%s'." % name)
			return {}
	
		var property_schema := {
			"type": PROPERTY_TYPES[type_name],
			"mod_editable": true
		}
		if schema.has("required"):
			if typeof(schema["required"]) != TYPE_BOOL:
				_fail("Invalid required flag for '%s'." % name)
				return {}
			property_schema["required"] = schema["required"]
	
		if schema.has("mod_editable"):
			if typeof(schema["mod_editable"]) != TYPE_BOOL:
				_fail("Invalid mod_editable flag for '%s'." % name)
				return {}
			property_schema["mod_editable"] = schema["mod_editable"]
	
		if schema.has("default"):
			var default_value := _read_scalar(schema["default"])
			if not errors.is_empty():
				return {}
			var actual_type := typeof(default_value)
			var expected_type: int = property_schema["type"]
			if actual_type != expected_type \
					and not (expected_type == TYPE_FLOAT and actual_type == TYPE_INT):
				_fail("Invalid default type for UI property '%s'." % name)
				return {}
			property_schema["default"] = default_value
		result[name] = property_schema
	return result


func _read_tree(value: Variant, depth: int, budget: Array[int]) -> Dictionary:
	budget[0] += 1
	if depth > MAX_DEPTH or budget[0] > MAX_NODES:
		_fail("UI component tree exceeds complexity limits.")
		return {}
	
	if not _is_table(value):
		_fail("UI component tree nodes must be tables.")
		return {}
	
	var source := (value as LuaTable).to_dictionary()
	if not _validate_keys(source, ["component", "name", "slot", "props", "children"], "tree node"):
		return {}
	
	var component_id: Variant = source.get("component")
	if typeof(component_id) != TYPE_STRING or component_id.is_empty():
		_fail("UI tree node requires a component ID.")
		return {}
	
	var node: Dictionary = {
		"component": component_id
	}
	if source.has("name"):
		if typeof(source["name"]) != TYPE_STRING or source["name"].is_empty():
			_fail("UI tree node name must be a non-empty string.")
			return {}
		node["name"] = source["name"]
	
	if source.has("slot"):
		if typeof(source["slot"]) != TYPE_STRING or source["slot"].is_empty():
			_fail("UI tree slot must be a non-empty string.")
			return {}
		node["slot"] = source["slot"]
	
	if source.has("props"):
		var props := _read_node_props(source["props"])
		if not errors.is_empty():
			return {}
		node["props"] = props
	
	if source.has("children"):
		if not _is_table(source["children"]):
			_fail("UI tree children must be an array.")
			return {}
	
		var indexed := (source["children"] as LuaTable).to_dictionary()
		var children: Array = []
		for index in range(1, indexed.size() + 1):
			if not indexed.has(index):
				_fail("UI tree children must have sequential numeric indexes.")
				return {}
			var child := _read_tree(indexed[index], depth + 1, budget)
			if not errors.is_empty():
				return {}
			children.append(child)
		node["children"] = children
	return node


func _read_node_props(value: Variant) -> Dictionary:
	if not _is_table(value):
		_fail("UI node props must be a table.")
		return {}
	var source := (value as LuaTable).to_dictionary()
	var result: Dictionary = {}
	if source.size() > MAX_PROPERTIES:
		_fail("UI node declares too many props.")
		return {}
	
	for name in source:
		if typeof(name) != TYPE_STRING or name.is_empty():
			_fail("UI node property names must be strings.")
			return {}
		var raw_value: Variant = source[name]
		if _is_table(raw_value):
			var binding := (raw_value as LuaTable).to_dictionary()
			if binding.size() != 1 or typeof(binding.get("$prop")) != TYPE_STRING:
				_fail("Invalid binding for UI property '%s'." % name)
				return {}
			result[name] = {"$prop": binding["$prop"]}
		else:
			result[name] = _read_scalar(raw_value)
		if not errors.is_empty():
			return {}
	return result


func _read_events(value: Variant) -> Dictionary:
	if value == null:
		return {}
	
	if not _is_table(value):
		_fail("UI events must be a table.")
		return {}
	
	var source := (value as LuaTable).to_dictionary()
	var result: Dictionary = {}
	for event_name in source:
		if typeof(event_name) != TYPE_STRING or event_name.is_empty():
			_fail("UI event names must be strings.")
			return {}
	
		if not _is_table(source[event_name]):
			_fail("UI event '%s' requires a routing table." % event_name)
			return {}
	
		var route := (source[event_name] as LuaTable).to_dictionary()
		if not _validate_keys(route, ["source", "event"], event_name):
			return {}
	
		var source_name: Variant = route.get("source")
		var source_event: Variant = route.get("event")
		if typeof(source_name) != TYPE_STRING or source_name.is_empty() \
				or typeof(source_event) != TYPE_STRING or source_event.is_empty():
			_fail("Invalid event route '%s'." % event_name)
			return {}
		result[event_name] = {
			"source": source_name,
			"event": source_event
		}
	return result


func _read_scalar(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT:
		if is_finite(value):
			return LuaUtils.normalize_integer(value)
	elif typeof(value) in [TYPE_BOOL, TYPE_INT]:
		return value
	elif typeof(value) == TYPE_STRING:
		if value.length() <= MAX_STRING_LENGTH:
			return value
	_fail("Unsupported UI value. Only strings, booleans and finite numbers are allowed.")
	return null


func _is_table(value: Variant) -> bool:
	return value is LuaTable and value.get_lua_state() == _lua_state


func _validate_keys(data: Dictionary, allowed: Array, context: String) -> bool:
	for key in data:
		if typeof(key) != TYPE_STRING or not allowed.has(key):
			return _fail("Unsupported field '%s' in %s." % [str(key), context])
	return true


func _fail(message: String) -> bool:
	errors.append(message)
	return false
