class_name UIStyleBoxCompiler extends RefCounted

const VISUAL_PROPERTIES := [
	"background_color", "border_color", "border_width", "border_radius",
	"drop_shadow_color", "drop_shadow_size", "drop_shadow_offset", "background_image",
	"background_image_slice", "background_image_tint", "background_image_stretch",
	"draw_center", "padding",
	"padding_left", "padding_top", "padding_right", "padding_bottom",
	"border_left_width", "border_top_width", "border_right_width", "border_bottom_width",
	"border_top_left_radius", "border_top_right_radius", "border_bottom_right_radius", "border_bottom_left_radius",
	"corner_radius", "corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_right", "corner_radius_bottom_left",
	"background_image_slice_left", "background_image_slice_top", "background_image_slice_right", "background_image_slice_bottom"
]

var errors: Array[String] = []
var texture_resolver: Callable

func validate_properties(properties: Dictionary) -> bool:
	errors.clear()
	for name in properties:
		var field := String(name)
		var value: Variant = properties[name]
		if field not in VISUAL_PROPERTIES:
			errors.append("Unknown visual style property '%s'." % field)
			return false
		if field in ["background_color", "border_color", "drop_shadow_color", "background_image_tint"]:
			if not value is Color:
				errors.append("Visual '%s' must be a Color." % field)
				return false
		elif field in ["border_width", "border_radius", "corner_radius", "background_image_slice", "padding"]:
			if not _valid_edges(value):
				errors.append("Visual '%s' must contain non-negative edges." % field)
				return false
		elif field.begins_with("border_") and (field.ends_with("_width") or field.ends_with("_radius")) \
				or field.begins_with("corner_radius_") or field.begins_with("background_image_slice_") \
				or field in ["padding_left", "padding_top", "padding_right", "padding_bottom"]:
			if not _nonnegative(value):
				errors.append("Visual '%s' must be non-negative." % field)
				return false
		elif field == "drop_shadow_size":
			if not _nonnegative(value):
				errors.append("Visual drop_shadow_size must be non-negative.")
				return false
		elif field == "drop_shadow_offset":
			if not value is Vector2 or not is_finite(value.x) or not is_finite(value.y):
				errors.append("Visual drop_shadow_offset must be a finite Vector2.")
				return false
		elif field == "background_image":
			if typeof(value) != TYPE_STRING or value.is_empty():
				errors.append("Visual background_image must be a nonempty asset ID.")
				return false
		elif field == "background_image_stretch":
			if value not in ["stretch", "tile", "tile_fit"]:
				errors.append("Visual background_image_stretch must be stretch, tile or tile_fit.")
				return false
		elif field == "draw_center":
			if typeof(value) != TYPE_BOOL:
				errors.append("Visual draw_center must be boolean.")
				return false
	if properties.has("background_image"):
		for name in properties:
			var field := String(name)
			if field in ["border_color", "border_width", "border_radius", "corner_radius", "drop_shadow_color", "drop_shadow_size", "drop_shadow_offset"] \
					or field.begins_with("border_") or field.begins_with("corner_radius_"):
				errors.append("background_image cannot be combined with '%s' in a single StyleBoxTexture. Use an additional visual layer." % field)
				return false
	else:
		for name in properties:
			var field := String(name)
			if field in ["background_image_tint", "background_image_stretch", "background_image_slice"] \
					or field.begins_with("background_image_slice_"):
				errors.append("'%s' requires background_image." % field)
				return false
	return true


func _valid_edges(value: Variant) -> bool:
	if value is Vector4:
		return _nonnegative(value.x) and _nonnegative(value.y) and _nonnegative(value.z) and _nonnegative(value.w)
	return _nonnegative(value)


func compile(properties: Dictionary) -> StyleBox:
	if not validate_properties(properties):
		return null
	
	var result: StyleBox
	if properties.has("background_image"):
		result = _create_texture(properties)
	else:
		result = _create_flat(properties)
	
	if result == null or not errors.is_empty():
		return null
	
	if UIStyleProperties.has_edges(properties, "padding"):
		var edges := UIStyleProperties.edges(properties, "padding")
		if not errors.is_empty():
			return null
		result.set_content_margin(SIDE_LEFT, edges.x)
		result.set_content_margin(SIDE_TOP, edges.y)
		result.set_content_margin(SIDE_RIGHT, edges.z)
		result.set_content_margin(SIDE_BOTTOM, edges.w)
	
	return result


func _create_flat(properties: Dictionary) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color.TRANSPARENT
	box.border_color = Color.TRANSPARENT
	box.shadow_color = Color.TRANSPARENT
	box.set_border_width_all(0)
	
	if properties.has("background_color"):
		box.bg_color = _color(properties["background_color"], "background_color")
	
	if properties.has("border_color"):
		box.border_color = _color(properties["border_color"], "border_color")
	
	if UIStyleProperties.has_edges(properties, "border_width"):
		var width := UIStyleProperties.edges(properties, "border_width")
		box.border_width_left = roundi(width.x)
		box.border_width_top = roundi(width.y)
		box.border_width_right = roundi(width.z)
		box.border_width_bottom = roundi(width.w)
	
	if UIStyleProperties.has_edges(properties, "border_radius"):
		var radius := UIStyleProperties.edges(properties, "border_radius")
		box.corner_radius_top_left = roundi(radius.x)
		box.corner_radius_top_right = roundi(radius.y)
		box.corner_radius_bottom_right = roundi(radius.z)
		box.corner_radius_bottom_left = roundi(radius.w)
	
	if properties.has("drop_shadow_color"):
		box.shadow_color = _color(properties["drop_shadow_color"], "drop_shadow_color")
	
	if properties.has("drop_shadow_size"):
		var size: Variant = properties["drop_shadow_size"]
		if not _nonnegative(size):
			errors.append("drop_shadow_size must be non-negative.")
		else:
			box.shadow_size = roundi(size)
	
	if properties.has("drop_shadow_offset"):
		box.shadow_offset = _vector2(
			properties["drop_shadow_offset"],
			"drop_shadow_offset"
		)
	
	if properties.has("draw_center"):
		if typeof(properties["draw_center"]) != TYPE_BOOL:
			errors.append("draw_center must be boolean.")
		else:
			box.draw_center = properties["draw_center"]
	
	return box


func _create_texture(properties: Dictionary) -> StyleBoxTexture:
	var asset: Variant = properties["background_image"]
	
	if typeof(asset) != TYPE_STRING or asset.is_empty():
		errors.append("background_image must be a non-empty asset ID.")
		return null
	
	if not texture_resolver.is_valid():
		errors.append("No texture resolver configured.")
		return null
	
	var texture: Variant = texture_resolver.call(asset)
	if not texture is Texture2D:
		errors.append("Unable to resolve texture '%s'." % asset)
		return null
	
	var box := StyleBoxTexture.new()
	box.texture = texture
	if UIStyleProperties.has_edges(properties, "background_image_slice"):
		var slices := UIStyleProperties.edges(properties, "background_image_slice")
		box.set_texture_margin(SIDE_LEFT, slices.x)
		box.set_texture_margin(SIDE_TOP, slices.y)
		box.set_texture_margin(SIDE_RIGHT, slices.z)
		box.set_texture_margin(SIDE_BOTTOM, slices.w)
	
	if properties.has("background_image_tint"):
		box.modulate_color = _color(
			properties["background_image_tint"],
			"background_image_tint"
		)
	
	if properties.has("background_image_stretch"):
		var stretch: Variant = properties["background_image_stretch"]
		var mode := _stretch_mode(stretch)
		if not errors.is_empty():
			return null
		box.axis_stretch_horizontal = mode
		box.axis_stretch_vertical = mode
	
	if properties.has("draw_center"):
		if typeof(properties["draw_center"]) != TYPE_BOOL:
			errors.append("draw_center must be boolean.")
		else:
			box.draw_center = properties["draw_center"]
	
	return box


func _stretch_mode(value: Variant) -> int:
	match value:
		"stretch":
			return StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		"tile":
			return StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		"tile_fit":
			return StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	errors.append("Invalid background_image_stretch '%s'." % str(value))
	return StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH


func _color(value: Variant, field: String) -> Color:
	if value is Color:
		return value
	
	if typeof(value) == TYPE_STRING and Color.html_is_valid(value):
		return Color.html(value)
	
	errors.append("Invalid color '%s'." % field)
	return Color.TRANSPARENT


func _vector2(value: Variant, field: String) -> Vector2:
	if value is Vector2:
		return value
	
	if value is Dictionary:
		if _number(value.get("x")) and _number(value.get("y")):
			return Vector2(value["x"], value["y"])
	
	errors.append("Invalid Vector2 '%s'." % field)
	return Vector2.ZERO


func _edges(value: Variant, field: String) -> Vector4:
	if _nonnegative(value):
		return Vector4(value, value, value, value)
	
	if value is Vector4:
		if _nonnegative(value.x) and _nonnegative(value.y) \
				and _nonnegative(value.z) and _nonnegative(value.w):
			return value
	
	if value is Dictionary:
		for side in ["left", "top", "right", "bottom"]:
			if not _nonnegative(value.get(side)):
				errors.append("Invalid edge '%s.%s'." % [field, side])
				return Vector4.ZERO
	
		return Vector4(
			value["left"],
			value["top"],
			value["right"],
			value["bottom"]
		)
	
	errors.append("Invalid edges for '%s'." % field)
	return Vector4.ZERO


func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] \
			and is_finite(float(value))


func _nonnegative(value: Variant) -> bool:
	return _number(value) and float(value) >= 0.0
