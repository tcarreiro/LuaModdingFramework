class_name UIPremadeContract extends RefCounted

static func property(type_id: int, default_value: Variant, mod_editable: bool = true) -> Dictionary:
	return {
		"type": type_id,
		"default": default_value,
		"mod_editable": mod_editable
	}


static func create_definition(id: String, properties: Dictionary = {},
		default_style: String = "", events: Array = [], slots: Dictionary = {}) -> UIComponentDefinition:
	var definition := UIComponentDefinition.new()
	definition.id = id
	definition.kind = UIComponentDefinition.Kind.SCENE
	
	definition.properties = {
		UIKeys.PROP_STYLE: property(TYPE_STRING, default_style),
		UIKeys.PROP_VISIBLE: property(TYPE_BOOL, true),
		UIKeys.PROP_POINTER_EVENTS: {
			"type": TYPE_STRING,
			"mod_editable": true
		}
	}
	definition.properties.merge(properties, true)
	
	definition.slots = slots.duplicate(true)
	if definition.slots.is_empty():
		definition.slots["default"] = NodePath(".")
	
	for event_name in events:
		var name := StringName(event_name)
		definition.events.append(name)
		definition.event_sources[name] = {
			"path": NodePath("."),
			"signal": name
		}
	
	return definition


static func apply_common(control: Control, values: Dictionary) -> void:
	if values.has(UIKeys.PROP_VISIBLE):
		control.visible = values[UIKeys.PROP_VISIBLE]
	
	if values.has(UIKeys.PROP_POINTER_EVENTS):
		match values[UIKeys.PROP_POINTER_EVENTS]:
			UIKeys.VAL_NONE:
				control.mouse_filter = Control.MOUSE_FILTER_IGNORE
			UIKeys.VAL_STOP:
				control.mouse_filter = Control.MOUSE_FILTER_STOP
			UIKeys.VAL_PASS:
				control.mouse_filter = Control.MOUSE_FILTER_PASS
