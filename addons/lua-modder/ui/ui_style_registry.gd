@tool
class_name UIStyleRegistry extends Registry

const GROUPS := ["layout", "styleboxes", "colors", "font_sizes", "fonts"]
const STYLEBOX_NAMES := [
	"normal", "hover", "pressed", "hover_pressed",
	"disabled", "focus", "panel"
]
const VISUAL_STATES := [
	"normal", "hover", "pressed", "hover_pressed", "disabled", "focus"
]
const TRANSITION_PROPERTIES := [
	"background_color", "font_color", "opacity", "scale"
]

var _definitions: Dictionary[String, UIStyleDefinition] = {}
var _prepared: Dictionary[String, UIStyleDefinition] = {}
var _finalized := false

func register_style(definition: UIStyleDefinition) -> bool:
	if _finalized:
		errors.append("Style Registry is finalized.")
		return false

	if definition == null or definition.id.strip_edges().is_empty():
		errors.append("Invalid style definition.")
		return false

	if _definitions.has(definition.id):
		errors.append("Duplicate style '%s'." % definition.id)
		return false

	if not definition.owner_mod_id.is_empty() and not definition.id.begins_with(definition.owner_mod_id + ":"):
		errors.append("Style '%s' has an invalid owner namespace." % definition.id)
		return false

	if not _validate_groups(definition):
		return false
	
	if not _validate_animation(definition):
		return false

	_definitions[definition.id] = definition.copy()
	return true


func finalize() -> bool:
	if _finalized:
		return true

	if not errors.is_empty():
		return false

	for id in _definitions:
		if not _prepare_style(id, []):
			return false

	_finalized = true
	return true


func is_finalized() -> bool:
	return _finalized


func has_style(id: String) -> bool:
	return _definitions.has(id)


func prepare_instance(id: String, overrides: Dictionary = {}, trusted: bool = false) -> UIStyleDefinition:
	if not _finalized or not _prepared.has(id):
		errors.append("Style '%s' is unavailable." % id)
		return null

	var style := _prepared[id]

	if not trusted and not style.exposed_to_mods:
		errors.append("Style '%s' is not exposed to mods." % id)
		return null

	if not _validate_overrides(style, overrides, trusted):
		return null

	var result := style.copy()
	_apply_overrides(result, overrides)
	return result


func _prepare_style(id: String, visiting: Array[String]) -> bool:
	if _prepared.has(id):
		return true

	if visiting.has(id):
		errors.append("Cyclic style inheritance: %s -> %s." % [
			" -> ".join(PackedStringArray(visiting)), id
		])
		return false

	var definition := _definitions[id]
	var result := UIStyleDefinition.new()

	if not definition.parent.is_empty():
		if not _definitions.has(definition.parent):
			errors.append("Style '%s' has unknown parent '%s'." % [id, definition.parent])
			return false

		visiting.append(id)
		if not _prepare_style(definition.parent, visiting):
			return false
		visiting.pop_back()

		result = _prepared[definition.parent].copy()

	result.id = definition.id
	result.parent = definition.parent
	result.owner_mod_id = definition.owner_mod_id
	result.exposed_to_mods = definition.exposed_to_mods
	result.mod_overrides = definition.mod_overrides.duplicate()
	
	
	for state_name in definition.states:
		var inherited: Dictionary = result.states.get(state_name, {}).duplicate(true)
		inherited.merge(definition.states[state_name], true)
		result.states[state_name] = inherited

	result.transition.merge(definition.transition, true)
	result.layout.merge(definition.layout, true)
	result.colors.merge(definition.colors, true)
	result.font_sizes.merge(definition.font_sizes, true)
	result.fonts.merge(definition.fonts, true)

	for name in definition.styleboxes:
		result.styleboxes[name] = (definition.styleboxes[name] as StyleBox).duplicate(true)

	_prepared[id] = result
	return true


#region Validation

func _validate_groups(definition: UIStyleDefinition) -> bool:
	for group_name in GROUPS:
		var entries: Dictionary = definition.get(group_name)

		for name in entries:
			if not _valid_entry(group_name, str(name), entries[name]):
				errors.append("Invalid style property '%s.%s' in '%s'." % [
					group_name, name, definition.id
				])
				return false

	return true


func _validate_overrides(style: UIStyleDefinition, overrides: Dictionary, trusted: bool) -> bool:
	for group_name in overrides:
		if group_name not in GROUPS or not overrides[group_name] is Dictionary:
			errors.append("Invalid style override group '%s'." % group_name)
			return false

		var entries: Dictionary = overrides[group_name]

		for name in entries:
			var property_path := "%s.%s" % [group_name, name]

			if not trusted:
				if group_name in ["styleboxes", "fonts"] or not style.mod_overrides.has(property_path):
					errors.append("Mods cannot override '%s'." % property_path)
					return false

			if not _valid_entry(group_name, str(name), entries[name]):
				errors.append("Invalid style override '%s'." % property_path)
				return false

	return true


func _valid_entry(group_name: String, name: String, value: Variant) -> bool:
	match group_name:
		"layout":
			return _valid_layout(name, value)
		"styleboxes":
			return name in STYLEBOX_NAMES and value is StyleBox
		"colors":
			return value is Color
		"font_sizes":
			return typeof(value) == TYPE_INT and value > 0
		"fonts":
			return value is Font

	return false


func _valid_layout(name: String, value: Variant) -> bool:
	match name:
		"padding", "margin":
			return _valid_edges(value)
		"min_size":
			return value is Vector2 and value.x >= 0 and value.y >= 0
		"stretch_x", "stretch_y":
			return value is String and value in [
				"fill", "expand", "expand_fill",
				"start", "center", "end"
			]
		"stretch_ratio":
			return typeof(value) in [TYPE_INT, TYPE_FLOAT] and value > 0
		"display":
			return value is String and value in ["block", "flex"]
		"direction":
			return value is String and value in ["horizontal", "vertical"]
		"alignment":
			return value is String and value in ["start", "center", "end"]
		"cross_alignment":
			return value is String and value in ["fill", "start", "center", "end"]
		"gap":
			return typeof(value) == TYPE_INT and value >= 0

	return false


func _valid_edges(value: Variant) -> bool:
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return value >= 0
	if value is Vector4:
		return value.x >= 0 and value.y >= 0 and value.z >= 0 and value.w >= 0
	return false


func _validate_animation(definition: UIStyleDefinition) -> bool:
	for state_name in definition.states:
		if state_name not in VISUAL_STATES:
			errors.append("Unknown visual state '%s' in '%s'." % [state_name, definition.id])
			return false
		var values: Variant = definition.states[state_name]
		if not values is Dictionary:
			errors.append("Invalid visual state '%s' in '%s'." % [state_name, definition.id])
			return false
		for property_name in values:
			var value: Variant = values[property_name]
			match property_name:
				"opacity":
					if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or value < 0 or value > 1:
						errors.append("Invalid opacity in '%s.%s'." % [definition.id, state_name])
						return false
				"scale":
					if not value is Vector2:
						errors.append("Invalid scale in '%s.%s'." % [definition.id, state_name])
						return false
				_:
					errors.append("Unsupported visual property '%s' in '%s'." % [
						property_name, definition.id
					])
					return false
	return _validate_transition(definition)


func _validate_transition(definition: UIStyleDefinition) -> bool:
	var config := definition.transition
	for property_name in config:
		var value: Variant = config[property_name]
		match property_name:
			"properties":
				if not value is Array:
					return _transition_error(definition.id, property_name)
				for item in value:
					if typeof(item) != TYPE_STRING or item not in TRANSITION_PROPERTIES:
						return _transition_error(definition.id, property_name)
			"duration":
				if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value < 0:
					return _transition_error(definition.id, property_name)
			"trans":
				if typeof(value) != TYPE_INT or value < Tween.TRANS_LINEAR or value > Tween.TRANS_SPRING:
					return _transition_error(definition.id, property_name)
			"ease":
				if typeof(value) != TYPE_INT or value < Tween.EASE_IN or value > Tween.EASE_OUT_IN:
					return _transition_error(definition.id, property_name)
			"iterations":
				if typeof(value) != TYPE_INT or value < 1 or value > 16:
					return _transition_error(definition.id, property_name)
			_:
				return _transition_error(definition.id, property_name)
	return true


func _transition_error(style_id: String, property_name: String) -> bool:
	errors.append("Invalid transition property '%s' in style '%s'." % [property_name, style_id])
	return false
#endregion


func _apply_overrides(style: UIStyleDefinition, overrides: Dictionary) -> void:
	for group_name in overrides:
		var destination: Dictionary = style.get(group_name)

		for name in overrides[group_name]:
			var value: Variant = overrides[group_name][name]

			if group_name == "styleboxes":
				value = (value as StyleBox).duplicate(true)

			destination[name] = value


func clear() -> void:
	_definitions.clear()
	_prepared.clear()
	_finalized = false
	errors.clear()
	warnings.clear()
