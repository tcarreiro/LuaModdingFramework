@tool
class_name UIStyleRegistry extends Registry

const GROUPS := ["layout", "styleboxes", "colors", "font_sizes", "fonts", "sounds"]
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

var texture_resolver: Callable
var sound_resolver: Callable

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
	
	for id in _prepared:
		if not _compile_visual_style(_prepared[id]):
			return false
	
	_finalized = true
	return true


func is_finalized() -> bool:
	return _finalized


func has_style(id: String) -> bool:
	return _definitions.has(id)


func get_style(id: String) -> UIStyleDefinition:
	return _definitions.get(id)


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


func prepare_inline(id: String, properties: Dictionary, trusted: bool = false, overrides: Dictionary = {}) -> UIStyleDefinition:
	var style: UIStyleDefinition
	if id.is_empty():
		if not overrides.is_empty():
			errors.append("Inline style overrides require a named style.")
			return null
		style = UIStyleDefinition.new()
		style.id = "<inline>"
	else:
		style = prepare_instance(id, overrides, trusted)
		if style == null:
			return null
	var registration := UIStyleContentRegistration.new(self)
	var inline := registration.parse_inline(properties)
	if inline == null:
		errors.append_array(registration.errors)
		return null
	if not _validate_groups(inline) or not _validate_animation(inline):
		return null
	style.layout = UIStyleProperties.merge_layer(style.layout, inline.layout)
	style.colors.merge(inline.colors, true)
	style.font_sizes.merge(inline.font_sizes, true)
	style.sounds.merge(inline.sounds, true)
	for state_name in inline.states:
		style.states[state_name] = UIStyleProperties.merge_layer(
			style.states.get(state_name, {}), inline.states[state_name]
		)
	style.transition.merge(inline.transition, true)
	style.visual = UIStyleProperties.merge_layer(style.visual, inline.visual)
	if not _validate_groups(style) or not _validate_animation(style):
		return null
	if not inline.visual.is_empty() or not inline.states.is_empty():
		for name in ["panel", "normal", "hover", "pressed", "hover_pressed", "disabled"]:
			style.styleboxes.erase(name)
		style.state_styleboxes.clear()
		if not _compile_visual_style(style):
			return null
		for name in overrides.get("styleboxes", {}):
			style.styleboxes[name] = (overrides["styleboxes"][name] as StyleBox).duplicate(true)
	elif not inline.sounds.is_empty():
		if not _compile_style_sounds(style):
			return null
	return style


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
		inherited = UIStyleProperties.merge_layer(inherited, definition.states[state_name])
		result.states[state_name] = inherited
	
	result.transition.merge(definition.transition, true)
	var visual := definition.visual.duplicate(true)
	if UIStyleProperties.has_edges(visual, "padding"):
		result.layout = UIStyleProperties.merge_layer(result.layout, {
			"padding": UIStyleProperties.edges(visual, "padding")
		})
		for key in ["padding", "padding_left", "padding_top", "padding_right", "padding_bottom"]:
			visual.erase(key)
	result.layout = UIStyleProperties.merge_layer(result.layout, definition.layout)
	result.colors.merge(definition.colors, true)
	result.font_sizes.merge(definition.font_sizes, true)
	result.fonts.merge(definition.fonts, true)
	
	for name in definition.styleboxes:
		result.styleboxes[name] = (definition.styleboxes[name] as StyleBox).duplicate(true)
	
	result.visual = UIStyleProperties.merge_layer(result.visual, visual)
	result.sounds.merge(definition.sounds, true)
	
	_prepared[id] = result
	return true


func _compile_visual_style(style: UIStyleDefinition) -> bool:
	var compiler := UIStyleBoxCompiler.new()
	compiler.texture_resolver = texture_resolver
	var base_visual := style.visual.duplicate(true)
	if base_visual.is_empty():
		for state_name in style.states:
			for property_name in UIStyleBoxCompiler.VISUAL_PROPERTIES:
				if style.states[state_name].has(property_name):
					base_visual["background_color"] = Color.TRANSPARENT
					break
			if not base_visual.is_empty():
				break
	
	if not base_visual.is_empty():
		var normal_box := compiler.compile(base_visual)
		if normal_box == null:
			return _style_compile_error(style.id, compiler.errors)
	
		if not style.styleboxes.has("panel"):
			style.styleboxes["panel"] = normal_box
	
		for name in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			if not style.styleboxes.has(name):
				style.styleboxes[name] = normal_box.duplicate(true)
	
	for state_name in style.states:
		var state: Dictionary = style.states[state_name]
		var visual_override: Dictionary = {}
		for property_name in UIStyleBoxCompiler.VISUAL_PROPERTIES:
			if state.has(property_name):
				visual_override[property_name] = state[property_name]
		if visual_override.is_empty():
			continue
		var visual_base := base_visual.duplicate(true)
		if UIStyleProperties.has_edges(style.layout, "padding"):
			visual_base = UIStyleProperties.merge_layer(visual_base, {
				"padding": UIStyleProperties.edges(style.layout, "padding")
			})
		var appearance := UIStyleProperties.merge_layer(visual_base, visual_override)
		var state_box := compiler.compile(appearance)
		if state_box == null:
			return _style_compile_error(style.id, compiler.errors)
		style.state_styleboxes[state_name] = state_box
	
		if state_name in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			style.styleboxes[state_name] = state_box.duplicate(true)
	
	if not _compile_style_sounds(style):
		return false
	return true


func _compile_style_sounds(style: UIStyleDefinition) -> bool:
	for name in style.sounds:
		var value: Variant = style.sounds[name]
		if value is AudioStream:
			continue
	
		if typeof(value) != TYPE_STRING or not sound_resolver.is_valid():
			errors.append("Cannot resolve sound '%s' in style '%s'." % [name, style.id])
			return false
	
		var stream: Variant = sound_resolver.call(value)
		if not stream is AudioStream:
			errors.append("Invalid sound asset '%s' in style '%s'." % [value, style.id])
			return false
		style.sounds[name] = stream
	return true


func _style_compile_error(style_id: String, messages: Array[String]) -> bool:
	for message in messages:
		errors.append("Style '%s': %s" % [style_id, message])
	return false
#endregion


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

	var compiler := UIStyleBoxCompiler.new()
	if not compiler.validate_properties(definition.visual):
		for message in compiler.errors:
			errors.append("Style '%s': %s" % [definition.id, message])
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
		"sounds":
			return name in [
				"hover_sound", "pressed_sound", "pressed_disabled_sound", "focus_sound"
			] and (value is AudioStream or typeof(value) == TYPE_STRING)
	return false


func _valid_layout(name: String, value: Variant) -> bool:
	match name:
		"padding", "margin":
			return _valid_edges(value)
		"padding_left", "padding_top", "padding_right", "padding_bottom", \
		"margin_left", "margin_top", "margin_right", "margin_bottom":
			return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value >= 0
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
		"scale_mode":
			return value is String and value in [
				"transform", "visual_only"
			]
		"pivot_ratio", "pivot_offset":
			if not value is Vector2:
				return false
			var pivot: Vector2 = value
			return is_finite(pivot.x) and is_finite(pivot.y)
		"icon_max_width", "icon_spacing":
			return typeof(value) == TYPE_INT and value >= 0
		"justify_self", "align_self":
			return typeof(value) == TYPE_STRING and value in ["start", "center", "end", "stretch"]
		"translate", "scale":
			return value is Vector2 and is_finite(value.x) and is_finite(value.y)
		"opacity":
			return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value >= 0 and value <= 1
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
			errors.append("Unknown visual state '%s'." % state_name)
			return false
		var values: Variant = definition.states[state_name]
		if not values is Dictionary:
			errors.append("Invalid visual state '%s'." % state_name)
			return false
		for property_name in values:
			var value: Variant = values[property_name]
			match property_name:
				"opacity":
					if typeof(value) not in [TYPE_INT, TYPE_FLOAT] \
							or not is_finite(float(value)) \
							or value < 0 or value > 1:
						return _invalid_state_property(definition.id, state_name, property_name)
				"scale":
					if not value is Vector2 or not is_finite(value.x) or not is_finite(value.y):
						return _invalid_state_property(definition.id, state_name, property_name)
				"background_color", "border_color", "drop_shadow_color", "background_image_tint", "font_color":
					if not value is Color:
						return _invalid_state_property(definition.id, state_name, property_name)
				"border_width", "border_radius", "corner_radius", "background_image_slice", "padding":
					if not _valid_edges(value):
						return _invalid_state_property(definition.id, state_name, property_name)
				"padding_left", "padding_top", "padding_right", "padding_bottom", \
				"border_left_width", "border_top_width", "border_right_width", "border_bottom_width", \
				"border_top_left_radius", "border_top_right_radius", "border_bottom_right_radius", \
				"border_bottom_left_radius", "corner_radius_top_left", "corner_radius_top_right", \
				"corner_radius_bottom_right", "corner_radius_bottom_left", \
				"background_image_slice_left", "background_image_slice_top", \
				"background_image_slice_right", "background_image_slice_bottom":
					if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or value < 0:
						return _invalid_state_property(definition.id, state_name, property_name)
				"drop_shadow_size":
					if typeof(value) not in [TYPE_INT, TYPE_FLOAT] \
							or not is_finite(float(value)) or value < 0:
						return _invalid_state_property(definition.id, state_name, property_name)
				"drop_shadow_offset":
					if not value is Vector2:
						return _invalid_state_property(definition.id, state_name, property_name)
				"background_image":
					if typeof(value) != TYPE_STRING or value.is_empty():
						return _invalid_state_property(definition.id, state_name, property_name)
				"background_image_stretch":
					if value not in ["stretch", "tile", "tile_fit"]:
						return _invalid_state_property(definition.id, state_name, property_name)
				"draw_center":
					if typeof(value) != TYPE_BOOL:
						return _invalid_state_property(definition.id, state_name, property_name)
				_:
					return _invalid_state_property(definition.id, state_name, property_name)

	return _validate_transition(definition)


func _invalid_state_property(style_id: String, state: String, property_name: String) -> bool:
	errors.append(
		"Invalid visual property '%s.%s' in style '%s'." % [
			state, property_name, style_id
		]
	)
	return false


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
			"duration", "delay":
				if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or value < 0:
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
