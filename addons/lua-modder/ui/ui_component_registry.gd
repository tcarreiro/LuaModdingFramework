@tool
class_name UIComponentRegistry extends Registry

var _definitions: Dictionary[String, UIComponentDefinition] = {}
var style_registry: UIStyleRegistry
var animation_registry: UIAnimationRegistry
var _finalized := false

func register_scene(definition: UIComponentDefinition) -> bool:
	if definition == null or definition.kind != UIComponentDefinition.Kind.SCENE:
		errors.append("register_scene expects a SCENE definition.")
		return false
	return _register(definition)


func register_template(definition: UIComponentDefinition) -> bool:
	if definition == null or definition.kind != UIComponentDefinition.Kind.TEMPLATE:
		errors.append("register_template expects a TEMPLATE definition.")
		return false
	return _register(definition)


func _register(definition: UIComponentDefinition) -> bool:
	if _finalized:
		errors.append("UI component registry is finalized.")
		return false
	if definition.id.strip_edges().is_empty() or _definitions.has(definition.id):
		errors.append("Invalid or duplicate UI component ID '%s'." % definition.id)
		return false
	if definition.kind == UIComponentDefinition.Kind.SCENE:
		if definition.scene == null or not definition.apply_properties.is_valid():
			errors.append("Scene component '%s' needs a scene and a valid applier." % definition.id)
			return false
	else:
		if definition.template.is_empty():
			errors.append("Template component '%s' needs a root node." % definition.id)
			return false
		if not definition.owner_mod_id.is_empty() and not definition.id.begins_with(definition.owner_mod_id + ":"):
			errors.append("Template '%s' must belong to mod '%s'." % [definition.id, definition.owner_mod_id])
			return false
	for property_name in definition.properties:
		var schema: Variant = definition.properties[property_name]
		if typeof(property_name) not in [TYPE_STRING, TYPE_STRING_NAME] or not schema is Dictionary or typeof(schema.get("type")) != TYPE_INT:
			errors.append("Invalid schema for '%s.%s'." % [definition.id, property_name])
			return false
		if schema.has("default") and not _valid_type(schema, schema["default"]):
			errors.append("Invalid default for '%s.%s'." % [definition.id, property_name])
			return false
	if definition.presentation not in ["inline", "overlay"]:
		errors.append("Invalid presentation for component '%s'." % definition.id)
		return false
	if definition.kind == UIComponentDefinition.Kind.TEMPLATE and definition.presentation == "overlay":
		errors.append("Overlay presentation must be provided by a native component.")
		return false
	_definitions[definition.id] = definition.copy()
	return true



func finalize() -> bool:
	if _finalized:
		return true
	
	if not errors.is_empty():
		return false
	
	for definition in _definitions.values():
		if definition.kind == UIComponentDefinition.Kind.TEMPLATE:
			if not _validate_tree(definition.template, definition):
				return false
		if not _validate_interaction_contract(definition):
			return false
	
	for id in _definitions:
		if not _validate_cycles(id, []):
			return false
	
	_finalized = true
	return true



func is_finalized() -> bool:
	return _finalized


func has_component(id: String) -> bool:
	return _definitions.has(id)


func get_definition(id: String) -> UIComponentDefinition:
	return _definitions[id].copy() if _definitions.has(id) else null


func get_recognized_properties(id: String, trusted: bool = false) -> Dictionary:
	if not _definitions.has(id):
		return {}
	var definition: UIComponentDefinition = _definitions[id]
	if not trusted and not definition.exposed_to_mods:
		return {}
	var result := definition.properties.duplicate(true)
	for name in UIStyleProperties.all_property_names():
		if not result.has(name):
			result[name] = {
				"type": TYPE_NIL,
				"type_name": UIStyleProperties.property_description(name),
				"inline_style": true,
				"mod_editable": true
			}
	return result


func describe_recognized_properties(id: String, trusted: bool = false) -> Dictionary:
	var schemas := get_recognized_properties(id, trusted)
	var result: Dictionary = {}
	for name in schemas:
		var schema: Dictionary = schemas[name]
		var info := {
			"type": schema.get("type_name", _property_type_name(int(schema.get("type", TYPE_NIL)))),
			"required": bool(schema.get("required", false)),
			"mod_editable": bool(schema.get("mod_editable", true))
		}
		if schema.has("default"):
			info["default"] = schema["default"]
		result[name] = info
	return result


func _property_type_name(type_id: int) -> String:
	match type_id:
		TYPE_STRING:
			return "string"
		TYPE_BOOL:
			return "bool"
		TYPE_INT:
			return "int"
		TYPE_FLOAT:
			return "float"
		TYPE_ARRAY:
			return "array"
		TYPE_DICTIONARY:
			return "dictionary"
		TYPE_COLOR:
			return "color"
	return type_string(type_id).to_lower()


func instantiate_component(id: String, values: Dictionary = {}, trusted: bool = false) -> UIComponentInstance:
	if not _finalized:
		errors.append("UI component registry must be finalized before instantiation.")
		return null
	return _instantiate(id, values, trusted)


func _instantiate(id: String, values: Dictionary, trusted: bool) -> UIComponentInstance:
	if not _definitions.has(id):
		errors.append("Unknown component '%s'." % id)
		return null
	
	var definition := _definitions[id]
	if not trusted and not definition.exposed_to_mods:
		errors.append("Component '%s' is not exposed to mods." % id)
		return null
	if not _validate_values(definition, values, trusted):
		return null
	
	var instance := UIComponentInstance.new()
	instance.component_id = id
	instance._registry = self
	instance._trusted = trusted and definition.owner_mod_id in ["", "core"]
	instance.values = definition.get_defaults()
	instance.values.merge(values, true)
	
	for property_name in definition.properties:
		var schema: Dictionary = definition.properties[property_name]
		if schema.get("required", false) and not instance.values.has(property_name):
			errors.append("Missing required property '%s.%s'." % [id, property_name])
			return null
	if definition.kind == UIComponentDefinition.Kind.SCENE:
		var node := definition.scene.instantiate()
		if not node is Control:
			errors.append("Scene component '%s' must have a Control root." % id)
			if node != null:
				node.free()
			return null
		instance.content_root = node as Control
		instance.root = instance.content_root
		if definition.presentation == "inline":
			var flags := Vector2i(Control.SIZE_SHRINK_BEGIN, Control.SIZE_SHRINK_BEGIN)
			if instance.root.has_method("get_premade_default_size_flags"):
				flags = instance.root.call("get_premade_default_size_flags")
			instance.root.size_flags_horizontal = flags.x
			instance.root.size_flags_vertical = flags.y
		if not _apply_instance_style(instance):
			instance.root.free()
			return null
		var native_values := instance.values.duplicate()
		for name in definition.properties:
			if UIStyleProperties.is_property(str(name)) and not values.has(name) and instance._style_layout.has(name):
				native_values.erase(name)
		if not definition.apply_properties.is_valid():
			errors.append("Scene component '%s' has an invalid property applier." % id)
			instance.root.free()
			return null
		definition.apply_properties.call(instance.content_root, native_values)
		if instance.transition != null:
			instance.transition.refresh()
		return instance
	instance._root_component = _build_tree(definition.template, instance, true)
	if instance._root_component == null:
		return null
	instance.root = instance._root_component.root
	return instance



func _build_tree(node_data: Dictionary, owner: UIComponentInstance, is_root: bool = false) -> UIComponentInstance:
	var id: String = node_data["component"]
	var resolved: Dictionary = {}
	var sources: Dictionary = {}
	var raw_props: Dictionary = node_data.get("props", {})
	for name in raw_props:
		var value: Variant = raw_props[name]
		if _is_binding(value):
			var source: String = value["$prop"]
			if not owner.values.has(source):
				errors.append("Missing template property '%s.%s'." % [owner.component_id, source])
				return null
			resolved[name] = owner.values[source]
			sources[name] = source
		else:
			resolved[name] = value
	if is_root:
		var owner_definition: UIComponentDefinition = _definitions[owner.component_id]
		for name in owner.values:
			if UIStyleProperties.is_property(str(name)) and not owner_definition.properties.has(name):
				resolved[name] = owner.values[name]
	
	var instance := _instantiate(id, resolved, owner._trusted)
	if instance == null:
		return null
	
	if not is_root and node_data.has("name"):
		var local_name: String = node_data["name"]
		owner._named_children[local_name] = instance
	
	for name in sources:
		var source: String = sources[name]
		if not owner._bindings.has(source):
			owner._bindings[source] = []
		owner._bindings[source].append({
			"target": instance,
			"property": name
		})
	
	for child_data in node_data.get("children", []):
		var child := _build_tree(child_data, owner, false)
		if child == null:
			instance.root.free()
			return null
		var slot_name: String = child_data.get("slot", "default")
		var slot := get_slot(instance, slot_name)
		if slot == null:
			errors.append("Component '%s' has no slot '%s'." % [id, slot_name])
			child.root.free()
			instance.root.free()
			return null
	
		slot.add_child(child.root)
		UIStyleApplier.apply_cross_alignment(instance, child)
		instance._children.append(child)
	return instance



func update_component(instance: UIComponentInstance, changes: Dictionary) -> bool:
	if changes.has("style") or changes.has("style_overrides"):
		errors.append("Runtime style changes are not available yet.")
		return false
	for name in changes:
		if UIStyleProperties.is_property(str(name)) and not _definitions[instance.component_id].properties.has(name):
			errors.append("Inline CSS styles can currently be set when creating a component, not through update().")
			return false
	var operations: Array[Dictionary] = []
	if not _plan_updates(instance, changes, operations):
		return false
	for operation in operations:
		var target: UIComponentInstance = operation["instance"]
		var definition := _definitions[target.component_id]
		if definition.kind == UIComponentDefinition.Kind.SCENE and not definition.apply_properties.is_valid():
			errors.append("Scene component '%s' has an invalid property applier." % target.component_id)
			return false
	for operation in operations:
		var target: UIComponentInstance = operation["instance"]
		var values: Dictionary = operation["values"]
		var definition := _definitions[target.component_id]
		if definition.kind == UIComponentDefinition.Kind.SCENE:
			definition.apply_properties.call(target.content_root, values)
		target.values.merge(values, true)
		if target.transition != null:
			target.transition.refresh()
	return true


func _plan_updates(instance: UIComponentInstance, changes: Dictionary, operations: Array[Dictionary]) -> bool:
	if instance == null or instance.root == null or not is_instance_valid(instance.root):
		errors.append("Cannot update a freed UI component.")
		return false
	var definition := _definitions.get(instance.component_id) as UIComponentDefinition
	if definition == null or not _validate_values(definition, changes, instance._trusted):
		return false
	for property_name in changes:
		for binding in instance._bindings.get(property_name, []):
			var target: UIComponentInstance = binding["target"]
			if not _plan_updates(target, {binding["property"]: changes[property_name]}, operations):
				return false
	operations.append({"instance": instance, "values": changes})
	return true


func get_slot(instance: UIComponentInstance, slot_name: String = "default") -> Control:
	if instance == null:
		return null
	if instance._root_component != null:
		return get_slot(instance._root_component, slot_name)
	var definition := _definitions.get(instance.component_id) as UIComponentDefinition
	if definition == null or not definition.slots.has(slot_name):
		return null
	var path: NodePath = definition.slots[slot_name]
	return instance.content_root.get_node_or_null(path)


func get_drag_target(instance: UIComponentInstance) -> Control:
	return _drag_node(instance, true)


func get_drag_handle(instance: UIComponentInstance) -> Control:
	return _drag_node(instance, false)


func _drag_node(instance: UIComponentInstance, target: bool) -> Control:
	if instance == null:
		return null
	if instance._root_component != null:
		return _drag_node(instance._root_component, target)
	var definition := _definitions.get(instance.component_id) as UIComponentDefinition
	if definition == null:
		return null
	var path := definition.drag_target if target else definition.drag_handle
	if path.is_empty():
		return null
	return instance.content_root.get_node_or_null(path)


func _validate_values(definition: UIComponentDefinition, values: Dictionary, trusted: bool) -> bool:
	for name in values:
		if name == "style_overrides":
			if not trusted or not values[name] is Dictionary:
				errors.append("style_overrides requires a trusted consumer Dictionary.")
				return false
			continue
		if not definition.properties.has(name):
			if not UIStyleProperties.is_property(name):
				errors.append("Unknown property '%s.%s'." % [definition.id, name])
				return false
			var parser := UIStyleContentRegistration.new(style_registry)
			if parser.parse_inline({name: values[name]}) == null:
				errors.append_array(parser.errors)
				return false
			continue
		var schema: Dictionary = definition.properties[name]
		var value: Variant = values[name]
		if not _valid_type(schema, value):
			errors.append("Invalid type for '%s.%s'." % [definition.id, name])
			return false
		if not trusted:
			if not schema.get("mod_editable", false):
				errors.append("Property '%s.%s' cannot be modified by mods." % [definition.id, name])
				return false
			if typeof(value) in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL]:
				errors.append("Native objects are not allowed in mod properties.")
				return false
			var choices: Array = schema.get("choices", [])
			if not choices.is_empty() and not choices.has(value):
				errors.append("Invalid option for '%s.%s'." % [definition.id, name])
				return false
	return true


func _valid_type(schema: Dictionary, value: Variant) -> bool:
	var expected: int = schema["type"]
	if value == null:
		return expected == TYPE_NIL or schema.get("nullable", false)
	if expected == TYPE_ARRAY:
		if not value is Array:
			return false
		if schema.has("item_type"):
			var expected_item_type: int = schema["item_type"]
			for item in value:
				if typeof(item) != expected_item_type:
					return false
		return true
	return typeof(value) == expected \
			or (expected == TYPE_FLOAT and typeof(value) == TYPE_INT)


func _is_binding(value: Variant) -> bool:
	return value is Dictionary and value.size() == 1 and typeof(value.get("$prop")) == TYPE_STRING


func _validate_tree(node: Dictionary, owner: UIComponentDefinition) -> bool:
	var id: Variant = node.get("component")
	if typeof(id) != TYPE_STRING or not _definitions.has(id):
		errors.append("Template '%s' references unknown component '%s'." % [owner.id, str(id)])
		return false
	var target := _definitions[id]
	if not owner.owner_mod_id.is_empty() and not target.exposed_to_mods:
		errors.append("Template '%s' references private component '%s'." % [owner.id, id])
		return false
	return _validate_template_props(node, owner, target) and _validate_template_children(node, owner, target)


func _validate_template_props(node: Dictionary, owner: UIComponentDefinition, target: UIComponentDefinition) -> bool:
	var raw_props: Variant = node.get("props", {})
	if not raw_props is Dictionary:
		errors.append("Template '%s' has invalid props." % owner.id)
		return false
	for name in raw_props:
		if not target.properties.has(name) and UIStyleProperties.is_property(name):
			var inline_value: Variant = raw_props[name]
			if _is_binding(inline_value):
				if not owner.properties.has(inline_value["$prop"]):
					errors.append("Unknown style binding '%s' in '%s'." % [inline_value["$prop"], owner.id])
					return false
			else:
				var parser := UIStyleContentRegistration.new(style_registry)
				if parser.parse_inline({name: inline_value}) == null:
					errors.append_array(parser.errors)
					return false
			continue
		if not target.properties.has(name):
			errors.append("Unknown property '%s.%s' in template '%s'." % [target.id, name, owner.id])
			return false
		var schema: Dictionary = target.properties[name]
		if not owner.owner_mod_id.is_empty() and not schema.get("mod_editable", false):
			errors.append("Template '%s' modifies restricted property '%s.%s'." % [owner.id, target.id, name])
			return false
		var value: Variant = raw_props[name]
		if _is_binding(value):
			var source: String = value["$prop"]
			if not owner.properties.has(source) or owner.properties[source]["type"] != schema["type"]:
				errors.append("Invalid property binding '%s' in template '%s'." % [source, owner.id])
				return false
		elif not _valid_type(schema, value):
			errors.append("Invalid literal for '%s.%s' in template '%s'." % [target.id, name, owner.id])
			return false
	return true


func _validate_template_children(node: Dictionary, owner: UIComponentDefinition, target: UIComponentDefinition) -> bool:
	var children: Variant = node.get("children", [])
	if not children is Array:
		errors.append("Template '%s' has invalid children." % owner.id)
		return false
	for child in children:
		if not child is Dictionary or not _validate_tree(child, owner):
			return false
		var slot_name: String = child.get("slot", "default")
		if target.kind == UIComponentDefinition.Kind.SCENE and not target.slots.has(slot_name):
			errors.append("Component '%s' does not expose slot '%s'." % [target.id, slot_name])
			return false
		if target.kind == UIComponentDefinition.Kind.TEMPLATE and slot_name != "default":
			errors.append("Template '%s' does not expose slot '%s' yet." % [target.id, slot_name])
			return false
	return true


func _validate_cycles(id: String, stack: Array[String]) -> bool:
	if stack.has(id):
		errors.append("UI component template cycle: %s -> %s." % [" -> ".join(PackedStringArray(stack)), id])
		return false
	var definition := _definitions[id]
	if definition.kind == UIComponentDefinition.Kind.SCENE:
		return true
	stack.append(id)
	var references: Array[String] = []
	_collect_references(definition.template, references)
	for reference in references:
		if not _validate_cycles(reference, stack):
			return false
	stack.pop_back()
	return true


func _collect_references(tree: Dictionary, result: Array[String]) -> void:
	result.append(tree["component"])
	for child in tree.get("children", []):
		_collect_references(child, result)


func play_animation(instance: UIComponentInstance, animation_id: String) -> bool:
	if instance == null or instance.root == null or not is_instance_valid(instance.root):
		errors.append("Cannot animate a freed UI component.")
		return false
	if animation_registry == null or not animation_registry.is_finalized():
		errors.append("Animation Registry is not available.")
		return false
	if instance.animation == null:
		instance.animation = UIAnimationPlayer.new()
		var target := instance.content_root if instance.content_root != null else instance.root
		instance.animation.setup(animation_registry, target, instance._trusted)
	if not instance.animation.play(animation_id):
		errors.append_array(instance.animation.errors)
		return false
	return true


func ensure_interaction(instance: UIComponentInstance) -> UIComponentInteraction:
	if instance == null or instance.root == null or not is_instance_valid(instance.root):
		errors.append("Cannot access interactions of a freed UI component.")
		return null
	
	if instance.interaction != null:
		return instance.interaction
	
	var definition := _definitions.get(instance.component_id) as UIComponentDefinition
	if definition == null:
		errors.append("Unknown UI component '%s'." % instance.component_id)
		return null
	instance.interaction = UIComponentInteraction.new()
	var target := instance.content_root if instance.content_root != null else instance.root
	instance.interaction.setup(definition, target)
	
	if definition.kind == UIComponentDefinition.Kind.TEMPLATE:
		if not _connect_template_routes(instance, definition):
			instance.clear_callbacks()
			return null
	return instance.interaction


func _apply_instance_style(instance: UIComponentInstance) -> bool:
	var style_id: String = instance.values.get("style", "")
	var inline: Dictionary = {}
	var definition: UIComponentDefinition = _definitions[instance.component_id]
	for name in instance.values:
		if UIStyleProperties.is_property(str(name)) and not definition.properties.has(name):
			inline[name] = instance.values[name]
	if style_id.is_empty() and inline.is_empty():
		return true
	
	if style_registry == null:
		errors.append("No Style Registry configured for component '%s'." % instance.component_id)
		return false
	
	var overrides: Variant = instance.values.get("style_overrides", {})
	if not overrides is Dictionary:
		errors.append("Invalid style overrides for '%s'." % instance.component_id)
		return false
	
	var style: UIStyleDefinition
	if inline.is_empty():
		style = style_registry.prepare_instance(style_id, overrides, instance._trusted)
	else:
		style = style_registry.prepare_inline(style_id, inline, instance._trusted, overrides)
	if style == null:
		errors.append_array(style_registry.errors)
		return false
	
	var styled_root := UIStyleApplier.apply(instance.content_root, style, errors)
	if styled_root == null:
		return false
	
	instance.root = styled_root
	instance._style_layout = style.layout.duplicate(true)
	if not style.states.is_empty() or not style.transition.get("properties", []).is_empty():
		instance.transition = UIStyleTransition.new()
		instance.transition.setup(instance.content_root, style, instance.content_root.get_meta(&"ui_visual_target", instance.content_root) as Control)
	
	return true


func _connect_template_routes(instance: UIComponentInstance, definition: UIComponentDefinition) -> bool:
	for public_event in definition.event_routes:
		var route: Dictionary = definition.event_routes[public_event]
		var source_name: String = route["source"]
		var source_event := StringName(route["event"])
		var child: UIComponentInstance
		if source_name == "$root":
			child = instance._root_component
		else:
			child = instance._named_children.get(source_name)
		if child == null:
			errors.append("Unknown event source '%s' in '%s'." % [
				source_name, definition.id
			])
			return false
		var listener := Callable(self, "_forward_template_event").bind(
			instance,
			StringName(public_event)
		)
		if not child.on_event(source_event, listener):
			errors.append("Cannot connect event '%s' in '%s'." % [
				public_event, definition.id
			])
			return false
		instance._event_forwarders.append({
			"child": child,
			"event": source_event,
			"listener": listener
		})
	return true


func _forward_template_event(event: Dictionary, owner: UIComponentInstance, public_event: StringName) -> void:
	owner.emit_event(public_event, event.get("arguments", []))


func clear() -> void:
	_definitions.clear()
	_finalized = false
	errors.clear()
	warnings.clear()


func _validate_interaction_contract(definition: UIComponentDefinition) -> bool:
	for event_name in definition.event_sources:
		if not definition.events.has(StringName(event_name)):
			errors.append("Undeclared event source '%s' in '%s'." % [event_name, definition.id])
			return false
	
		if definition.kind != UIComponentDefinition.Kind.SCENE:
			errors.append("Native event sources require a scene component.")
			return false
	
		var source: Variant = definition.event_sources[event_name]
		if not source is Dictionary \
				or not source.get("path", NodePath(".")) is NodePath \
				or typeof(source.get("signal")) not in [TYPE_STRING, TYPE_STRING_NAME]:
			errors.append("Invalid event source '%s' in '%s'." % [event_name, definition.id])
			return false
	
	if definition.kind == UIComponentDefinition.Kind.TEMPLATE:
		if not _validate_template_routes(definition):
			return false
	elif not definition.event_routes.is_empty():
		errors.append("Scene components cannot declare template event routes.")
		return false
	
	for hook_name in definition.hooks:
		var schema: Variant = definition.hooks[hook_name]
		if typeof(schema) == TYPE_INT:
			if schema < TYPE_NIL or schema >= TYPE_MAX:
				return _invalid_hook_contract(definition.id, hook_name)
			continue
	
		if not schema is Dictionary:
			return _invalid_hook_contract(definition.id, hook_name)
	
		var result_type: Variant = schema.get("type")
		if typeof(result_type) != TYPE_INT or result_type < TYPE_NIL or result_type >= TYPE_MAX:
			return _invalid_hook_contract(definition.id, hook_name)
	
		if schema.has("fallback") and not _valid_hook_type(schema["fallback"], result_type):
			return _invalid_hook_contract(definition.id, hook_name)
	
		if schema.has("args"):
			if not schema["args"] is Array:
				return _invalid_hook_contract(definition.id, hook_name)
	
			for argument_type in schema["args"]:
				if typeof(argument_type) != TYPE_INT or argument_type < TYPE_NIL or argument_type >= TYPE_MAX:
					return _invalid_hook_contract(definition.id, hook_name)
	return true


func _valid_hook_type(value: Variant, expected: int) -> bool:
	return typeof(value) == expected \
		or (expected == TYPE_FLOAT and typeof(value) == TYPE_INT)


func _invalid_hook_contract(component_id: String, hook_name: StringName) -> bool:
	errors.append("Invalid hook contract '%s.%s'." % [component_id, hook_name])
	return false


func _validate_template_routes(definition: UIComponentDefinition) -> bool:
	var named: Dictionary = {}
	if not _collect_named_children(definition.template, named, true):
		return false
	for public_event in definition.event_routes:
		if not definition.events.has(StringName(public_event)):
			errors.append("Undeclared template event '%s'." % public_event)
			return false
		var route: Variant = definition.event_routes[public_event]
		if not route is Dictionary:
			errors.append("Invalid template event route '%s'." % public_event)
			return false
		var source_name: Variant = route.get("source")
		var source_event: Variant = route.get("event")
		if typeof(source_name) != TYPE_STRING \
				or typeof(source_event) != TYPE_STRING:
			errors.append("Invalid event route '%s'." % public_event)
			return false
		var child_id: String
		if source_name == "$root":
			child_id = definition.template["component"]
		else:
			if not named.has(source_name):
				errors.append("Unknown named child '%s' in '%s'." % [
					source_name, definition.id
				])
				return false
			child_id = named[source_name]
		var child_definition := _definitions[child_id]
		if not child_definition.events.has(StringName(source_event)):
			errors.append("Component '%s' does not declare event '%s'." % [
				child_id, source_event
			])
			return false
	return true


func _collect_named_children(node: Dictionary, named: Dictionary, is_root: bool = false) -> bool:
	if not is_root and node.has("name"):
		var local_name: String = node["name"]
		if local_name.is_empty() or named.has(local_name):
			errors.append("Invalid or duplicate UI child name '%s'." % local_name)
			return false
		named[local_name] = node["component"]
	for child in node.get("children", []):
		if not _collect_named_children(child, named, false):
			return false
	return true
