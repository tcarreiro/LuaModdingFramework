@tool
class_name UIStyleProperties extends RefCounted

const LAYOUT_KEYS := [
	"padding", "margin", "min_size", "stretch_x", "stretch_y", "stretch_ratio",
	"display", "direction", "alignment", "cross_alignment", "gap", "scale_mode",
	"pivot_ratio", "pivot_offset", "icon_max_width", "icon_spacing",
	"justify_self", "align_self", "translate", "opacity", "scale",
	"padding_left", "padding_top", "padding_right", "padding_bottom",
	"margin_left", "margin_top", "margin_right", "margin_bottom"
]
const COLOR_KEYS := [
	"font_color", "font_hover_color", "font_pressed_color", "font_disabled_color",
	"font_focus_color", "font_hover_pressed_color", "font_outline_color",
	"icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_disabled_color"
]
const SOUND_KEYS := ["hover_sound", "pressed_sound", "pressed_disabled_sound", "focus_sound"]
const VISUAL_KEYS := [
	"background_color", "border_color", "border_width", "border_radius",
	"drop_shadow_color", "drop_shadow_size", "drop_shadow_offset",
	"background_image", "background_image_slice", "background_image_tint",
	"background_image_stretch", "draw_center", "padding"
]
const VISUAL_LONGHANDS := [
	"border_left_width", "border_top_width", "border_right_width", "border_bottom_width",
	"border_top_left_radius", "border_top_right_radius", "border_bottom_right_radius", "border_bottom_left_radius",
	"corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_right", "corner_radius_bottom_left",
	"corner_radius",
	"background_image_slice_left", "background_image_slice_top",
	"background_image_slice_right", "background_image_slice_bottom"
]
const TRANSITION_KEYS := [
	"transition_property", "transition_duration", "transition_delay", "transition_timing_function"
]
const EDGE_SUFFIXES := ["left", "top", "right", "bottom"]
const CORNERS := ["top_left", "top_right", "bottom_right", "bottom_left"]


static func is_property(name: String) -> bool:
	return name in LAYOUT_KEYS or name in COLOR_KEYS or name in SOUND_KEYS \
		or name in VISUAL_KEYS or name in VISUAL_LONGHANDS \
		or name == "font_size" or name == "states" or name in TRANSITION_KEYS


static func assign(style: UIStyleDefinition, name: String, value: Variant) -> bool:
	if name in LAYOUT_KEYS:
		style.layout[name] = value
	elif name in VISUAL_KEYS or name in VISUAL_LONGHANDS:
		style.visual[name] = value
	elif name in COLOR_KEYS:
		style.colors[name] = value
	elif name == "font_size":
		style.font_sizes[name] = value
	elif name in SOUND_KEYS:
		style.sounds[name] = value
	else:
		return false
	return true


static func has_edges(values: Dictionary, base: String) -> bool:
	if values.has(base) or base == "border_radius" and values.has("corner_radius"):
		return true
	for name in _longhands(base):
		if values.has(name):
			return true
	return false


static func edges(values: Dictionary, base: String) -> Vector4:
	var result := _as_edges(values.get(base, 0))
	if base == "border_radius" and not values.has("border_radius") and values.has("corner_radius"):
		result = _as_edges(values["corner_radius"])
	var names := _longhands(base)
	for i in range(names.size()):
		if values.has(names[i]):
			result[i] = float(values[names[i]])
	if base == "border_radius":
		for i in range(CORNERS.size()):
			var alias = "corner_radius_" + CORNERS[i]
			if values.has(alias) and not values.has(names[i]):
				result[i] = float(values[alias])
	return result


static func merge_layer(previous: Dictionary, incoming: Dictionary) -> Dictionary:
	var result := previous.duplicate(true)
	for base in ["padding", "margin", "border_width", "border_radius", "background_image_slice"]:
		if not has_edges(incoming, base) and not (base == "border_radius" and incoming.has("corner_radius")):
			continue
		var current := edges(result, base)
		if incoming.has(base):
			current = _as_edges(incoming[base])
		elif base == "border_radius" and incoming.has("corner_radius"):
			current = _as_edges(incoming["corner_radius"])
		var names := _longhands(base)
		for i in range(names.size()):
			if incoming.has(names[i]):
				current[i] = float(incoming[names[i]])
			elif base == "border_radius" and incoming.has("corner_radius_" + CORNERS[i]):
				current[i] = float(incoming["corner_radius_" + CORNERS[i]])
		result[base] = current
		for name in names:
			result.erase(name)
		if base == "border_radius":
			result.erase("corner_radius")
			for corner in CORNERS:
				result.erase("corner_radius_" + corner)
	for name in incoming:
		if _is_edge_name(name):
			continue
		result[name] = incoming[name]
	return result


static func _is_edge_name(name: String) -> bool:
	if name in ["padding", "margin", "border_width", "border_radius", "corner_radius", "background_image_slice"]:
		return true
	if is_edge_longhand(name):
		return true
	return false


static func _longhands(base: String) -> Array[String]:
	var result: Array[String] = []
	if base == "border_radius":
		for corner in CORNERS:
			result.append("border_%s_radius" % corner)
	elif base == "border_width":
		for side in EDGE_SUFFIXES:
			result.append("border_%s_width" % side)
	else:
		for side in EDGE_SUFFIXES:
			result.append("%s_%s" % [base, side])
	return result


static func _as_edges(value: Variant) -> Vector4:
	if value is Vector4:
		return value
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return Vector4(value, value, value, value)
	return Vector4.ZERO


static func is_edge_longhand(name: String) -> bool:
	return name in VISUAL_LONGHANDS and name != "corner_radius" \
		or name in LAYOUT_KEYS and (
			name.begins_with("padding_") or name.begins_with("margin_")
		)


static func property_description(name: String) -> String:
	if name == "states":
		return "map"
	if name in TRANSITION_KEYS:
		return "string[]" if name == "transition_property" else ("number" if name in ["transition_duration", "transition_delay"] else "string")
	if is_edge_longhand(name) or name in ["padding", "margin", "border_width", "border_radius", "corner_radius", "background_image_slice"]:
		return "number" if is_edge_longhand(name) else "number|edges"
	if name.ends_with("color") or name == "background_image_tint":
		return "color"
	if name in ["min_size", "pivot_ratio", "pivot_offset", "translate", "drop_shadow_offset", "scale"]:
		return "vector2"
	if name in ["stretch_ratio", "drop_shadow_size", "opacity"]:
		return "number"
	if name in ["font_size", "gap", "icon_max_width", "icon_spacing"]:
		return "integer"
	if name == "draw_center":
		return "bool"
	return "string"


static func all_property_names() -> Array[String]:
	var names: Array[String] = []
	for group in [LAYOUT_KEYS, COLOR_KEYS, SOUND_KEYS, VISUAL_KEYS, VISUAL_LONGHANDS, ["font_size", "states"], TRANSITION_KEYS]:
		for name in group:
			if not names.has(name):
				names.append(name)
	return names
