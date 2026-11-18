@tool
class_name UIComponentDefinition extends RefCounted

enum Kind { SCENE, TEMPLATE }

var id: String
var kind: Kind
var owner_mod_id: String = ""
var scene: PackedScene
var template: Dictionary = {}
var properties: Dictionary = {}
var slots: Dictionary = {}
var apply_properties: Callable
var events: Array[StringName] = []
var hooks: Dictionary = {}
var event_sources: Dictionary = {}
var event_routes: Dictionary = {}
var drag_target: NodePath
var drag_handle: NodePath
var exposed_to_mods: bool = true


static func from_scene(component_id: String, packed_scene: PackedScene, applier: Callable, property_schema: Dictionary = {}, slot_paths: Dictionary = {}) -> UIComponentDefinition:
	var definition := UIComponentDefinition.new()
	definition.id = component_id
	definition.kind = Kind.SCENE
	definition.scene = packed_scene
	definition.apply_properties = applier
	definition.properties = property_schema.duplicate(true)
	definition.slots = slot_paths.duplicate(true)
	if definition.slots.is_empty():
		definition.slots["default"] = NodePath(".")
	return definition


static func from_template(component_id: String, mod_id: String, tree: Dictionary, property_schema: Dictionary = {}) -> UIComponentDefinition:
	var definition := UIComponentDefinition.new()
	definition.id = component_id
	definition.kind = Kind.TEMPLATE
	definition.owner_mod_id = mod_id
	definition.template = tree.duplicate(true)
	definition.properties = property_schema.duplicate(true)
	return definition


func get_defaults() -> Dictionary:
	var defaults: Dictionary = {}
	for property_name in properties:
		var schema: Dictionary = properties[property_name]
		if schema.has("default"):
			defaults[property_name] = schema["default"]
	return defaults.duplicate(true)


func copy() -> UIComponentDefinition:
	var result := UIComponentDefinition.new()
	result.id = id
	result.kind = kind
	result.owner_mod_id = owner_mod_id
	result.scene = scene
	result.template = template.duplicate(true)
	result.properties = properties.duplicate(true)
	result.slots = slots.duplicate(true)
	result.apply_properties = apply_properties
	result.events = events.duplicate()
	result.hooks = hooks.duplicate(true)
	result.event_sources = event_sources.duplicate(true)
	result.event_routes = event_routes.duplicate(true)
	result.drag_target = drag_target
	result.drag_handle = drag_handle
	result.exposed_to_mods = exposed_to_mods
	return result
