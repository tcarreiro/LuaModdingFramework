@tool
class_name ModDependency extends RefCounted

enum Type {
	REQUIRED,
	OPTIONAL,
	RECOMMENDED,
	HIDDEN_OPTIONAL,
	INCOMPATIBLE,
	NO_ORDER
}

@export var id: String
@export var type: Type = Type.REQUIRED
@export var operator: String = ""
@export var version: String = ""

func is_required() -> bool:
	return type == Type.REQUIRED or type == Type.NO_ORDER


func affects_load_order() -> bool:
	return type != Type.NO_ORDER and type != Type.INCOMPATIBLE


static func is_valid_mod_id(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9_-]+$")
	return regex.search(value) != null


static func parse(raw: String) -> ModDependency:
	var source := raw.strip_edges()
	var dependency := ModDependency.new()
	
	if source.begins_with("(?)"):
		dependency.type = Type.HIDDEN_OPTIONAL
	elif source.begins_with("?"):
		dependency.type = Type.OPTIONAL
	elif source.begins_with("+"):
		dependency.type = Type.RECOMMENDED
	elif source.begins_with("!"):
		dependency.type = Type.INCOMPATIBLE
	elif source.begins_with("~"):
		dependency.type = Type.NO_ORDER
	
	var regex := RegEx.new()
	regex.compile("^([A-Za-z0-9_-]+)(?:\\s*(<=|>=|=|<|>)\\s*(\\d+\\.\\d+\\.\\d+))?$")
	
	var result := regex.search(source)
	if result == null:
		return null
	
	dependency.id = result.get_string(1)
	dependency.operator = result.get_string(2)
	dependency.version = result.get_string(3)
	
	if not dependency.version.is_empty() and not ModVersion.is_valid(dependency.version):
		return null
	
	if dependency.type == Type.INCOMPATIBLE:
		dependency.operator = ""
		dependency.version = ""
	
	return dependency
