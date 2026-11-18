@tool
class_name UIStyleApplier extends RefCounted


static func apply(control: Control, style: UIStyleDefinition, errors: Array[String]) -> Control:
	if not _validate_control(control, style.layout, errors):
		return null
	
	if style.layout.has("padding") and style.styleboxes.is_empty():
		errors.append("Style '%s' requires a StyleBox to apply padding." % style.id)
		return null
	_apply_theme(control, style)
	_apply_layout(control, style.layout)
	return _wrap_margin(control, style.layout)


static func _validate_control(control: Control, layout: Dictionary, errors: Array[String]) -> bool:
	var display: String = layout.get("display", "")
	if display == "flex" and not control is BoxContainer:
		errors.append("Display 'flex' requires a BoxContainer.")
		return false
	
	if display == "block" and control is BoxContainer:
		errors.append("Display 'block' cannot use a BoxContainer.")
		return false
	
	if layout.has("direction") or layout.has("alignment") or layout.has("gap") or layout.has("cross_alignment"):
		if not control is BoxContainer:
			errors.append("Flex layout properties require a BoxContainer.")
			return false
	
	var direction: String = layout.get("direction", "")
	if control is VBoxContainer and direction == "horizontal":
		errors.append("VBoxContainer cannot use horizontal direction.")
		return false
	
	if control is HBoxContainer and direction == "vertical":
		errors.append("HBoxContainer cannot use vertical direction.")
		return false
	
	return true


static func _apply_theme(control: Control, style: UIStyleDefinition) -> void:
	var padding: Variant = style.layout.get("padding", null)
	for name in style.styleboxes:
		var box := style.styleboxes[name] as StyleBox
		if padding != null:
			_apply_padding(box, padding)
		control.add_theme_stylebox_override(StringName(name), box)
	
	for name in style.colors:
		control.add_theme_color_override(StringName(name), style.colors[name])
	
	for name in style.font_sizes:
		control.add_theme_font_size_override(StringName(name), style.font_sizes[name])
	
	for name in style.fonts:
		control.add_theme_font_override(StringName(name), style.fonts[name])


static func _apply_padding(box: StyleBox, value: Variant) -> void:
	var edges := _edges(value)
	box.set_content_margin(SIDE_LEFT, edges.x)
	box.set_content_margin(SIDE_TOP, edges.y)
	box.set_content_margin(SIDE_RIGHT, edges.z)
	box.set_content_margin(SIDE_BOTTOM, edges.w)


static func _apply_layout(control: Control, layout: Dictionary) -> void:
	if layout.has("min_size"):
		control.custom_minimum_size = layout["min_size"]
	
	if layout.has("stretch_x"):
		control.size_flags_horizontal = size_flags(layout["stretch_x"])
	
	if layout.has("stretch_y"):
		control.size_flags_vertical = size_flags(layout["stretch_y"])
	
	if layout.has("stretch_ratio"):
		control.size_flags_stretch_ratio = layout["stretch_ratio"]
	
	if control is BoxContainer:
		_apply_flex_layout(control as BoxContainer, layout)


static func _apply_flex_layout(control: BoxContainer, layout: Dictionary) -> void:
	if layout.has("direction"):
		if not control is HBoxContainer and not control is VBoxContainer:
			control.vertical = layout["direction"] == "vertical"
	
	if layout.has("alignment"):
		match layout["alignment"]:
			"start":
				control.alignment = BoxContainer.ALIGNMENT_BEGIN
			"center":
				control.alignment = BoxContainer.ALIGNMENT_CENTER
			"end":
				control.alignment = BoxContainer.ALIGNMENT_END
	
	if layout.has("gap"):
		control.add_theme_constant_override("separation", layout["gap"])


static func _wrap_margin(control: Control, layout: Dictionary) -> Control:
	var value: Variant = layout.get("margin", 0)
	var edges := _edges(value)
	if edges == Vector4.ZERO:
		return control
	
	var wrapper := MarginContainer.new()
	wrapper.name = "%s_Margin" % control.name
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.size_flags_horizontal = control.size_flags_horizontal
	wrapper.size_flags_vertical = control.size_flags_vertical
	wrapper.size_flags_stretch_ratio = control.size_flags_stretch_ratio
	_set_margin(wrapper, "margin_left", edges.x)
	_set_margin(wrapper, "margin_top", edges.y)
	_set_margin(wrapper, "margin_right", edges.z)
	_set_margin(wrapper, "margin_bottom", edges.w)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.add_child(control)
	return wrapper


static func _set_margin(wrapper: MarginContainer, name: String, value: float) -> void:
	wrapper.add_theme_constant_override(StringName(name), roundi(value))


static func _edges(value: Variant) -> Vector4:
	if value is Vector4:
		return value
	
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return Vector4(value, value, value, value)
	
	return Vector4.ZERO


static func size_flags(mode: String) -> int:
	match mode:
		"fill":
			return Control.SIZE_FILL
		"expand":
			return Control.SIZE_EXPAND
		"expand_fill":
			return Control.SIZE_EXPAND_FILL
		"center":
			return Control.SIZE_SHRINK_CENTER
		"end":
			return Control.SIZE_SHRINK_END
		_:
			return Control.SIZE_SHRINK_BEGIN


static func apply_cross_alignment(parent: UIComponentInstance, child: UIComponentInstance) -> void:
	if not parent.content_root is BoxContainer:
		return
	
	if not parent._style_layout.has("cross_alignment"):
		return
	
	var alignment: String = parent._style_layout["cross_alignment"]
	var flags := size_flags(alignment)
	var box := parent.content_root as BoxContainer
	
	if box.vertical:
		if not child._style_layout.has("stretch_x"):
			child.root.size_flags_horizontal = flags
	else:
		if not child._style_layout.has("stretch_y"):
			child.root.size_flags_vertical = flags
