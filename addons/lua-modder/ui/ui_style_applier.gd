@tool
class_name UIStyleApplier extends RefCounted


static func apply(control: Control, style: UIStyleDefinition, errors: Array[String]) -> Control:
	if not _validate_control(control, style.layout, errors):
		return null
	_apply_layout(control, style.layout)
	var visual_target: Control = control
	var needs_box := not style.styleboxes.is_empty() or UIStyleProperties.has_edges(style.layout, "padding")
	var has_native_box := not native_stylebox_slot(control).is_empty()
	if needs_box and not has_native_box:
		var panel := PanelContainer.new()
		panel.name = "%s_Visual" % control.name
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.size_flags_horizontal = control.size_flags_horizontal
		panel.size_flags_vertical = control.size_flags_vertical
		panel.size_flags_stretch_ratio = control.size_flags_stretch_ratio
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.add_child(control)
		visual_target = panel
		control.set_meta(&"ui_visual_target", panel)
	_apply_theme(control, style, visual_target)
	var styled_root := _wrap_translate(_wrap_margin(visual_target, style.layout), style.layout)
	if style.layout.has("justify_self"):
		styled_root.set_meta(&"ui_justify_self", style.layout["justify_self"])
	if style.layout.has("align_self"):
		styled_root.set_meta(&"ui_align_self", style.layout["align_self"])
	return styled_root


static func _validate_control(control: Control, layout: Dictionary, errors: Array[String]) -> bool:
	var display: String = layout.get("display", "")
	if display == "flex" and not control is BoxContainer and not control.has_method("get_content_box"):
		errors.append("Display 'flex' requires a BoxContainer.")
		return false
	
	if display == "block" and control is BoxContainer:
		errors.append("Display 'block' cannot use a BoxContainer.")
		return false
	
	if layout.has("direction") or layout.has("alignment") or layout.has("cross_alignment"):
		if not control is BoxContainer and not control.has_method("get_content_box"):
			errors.append("Layout 'direction', 'alignment' and 'cross_alignment' require a BoxContainer or a premade exposing get_content_box(); received '%s'." % control.get_class())
			return false
	
	if (layout.has("icon_max_width") or layout.has("icon_spacing")) and not control is Button:
		errors.append("icon_max_width and icon_spacing require a Button control.")
		return false
	
	if layout.has("gap"):
		var supports_gap := control is BoxContainer \
				or control is GridContainer \
				or control.has_method("set_content_gap") \
				or control.has_method("get_content_box") and control.call("get_content_box") is BoxContainer
		
		if not supports_gap:
			errors.append("The Control does not support layout gap.")
			return false
		
	var direction: String = layout.get("direction", "")
	var content_box := control as BoxContainer
	if content_box == null and control.has_method("get_content_box"):
		content_box = control.call("get_content_box") as BoxContainer
	if content_box is VBoxContainer and direction == "horizontal":
		errors.append("VBoxContainer content cannot use horizontal direction.")
		return false
	if content_box is HBoxContainer and direction == "vertical":
		errors.append("HBoxContainer content cannot use vertical direction.")
		return false
	return true


static func _apply_theme(control: Control, style: UIStyleDefinition, box_target: Control) -> void:
	var has_padding := UIStyleProperties.has_edges(style.layout, "padding")
	var padding := UIStyleProperties.edges(style.layout, "padding") if has_padding else Vector4.ZERO
	if box_target != control:
		var box: StyleBox = style.styleboxes.get("panel", style.styleboxes.get("normal"))
		if box == null:
			var blank := StyleBoxFlat.new()
			blank.bg_color = Color.TRANSPARENT
			box = blank
		box = box.duplicate(true)
		if has_padding and not control.has_method("set_content_padding"):
			_apply_padding(box, padding)
		box_target.add_theme_stylebox_override(&"panel", box)
	else:
		var base_slot := native_stylebox_slot(control)
		if control is BaseButton:
			for name in style.styleboxes:
				var box := (style.styleboxes[name] as StyleBox).duplicate(true) as StyleBox
				if has_padding and not control.has_method("set_content_padding"):
					_apply_padding(box, _state_padding(style, str(name), padding))
				control.add_theme_stylebox_override(StringName(name), box)
		elif not base_slot.is_empty():
			# A LineEdit, Tree, ScrollContainer, etc. already draws a StyleBox.
			# Assign to its ACTUAL Theme key, not an unused 'panel'/'normal'.
			var box: StyleBox = style.styleboxes.get("panel", style.styleboxes.get("normal"))
			if base_slot == &"normal":
				box = style.styleboxes.get("normal", style.styleboxes.get("panel"))
			if box != null:
				box = box.duplicate(true)
				if has_padding and not control.has_method("set_content_padding"):
					_apply_padding(box, padding)
				control.add_theme_stylebox_override(base_slot, box)
			if base_slot == &"normal" and style.styleboxes.has("focus"):
				control.add_theme_stylebox_override(&"focus", style.styleboxes["focus"].duplicate(true))
		if has_padding and style.styleboxes.is_empty() and not control.has_method("set_content_padding"):
			if control is BaseButton:
				for name in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
					var native_box := control.get_theme_stylebox(StringName(name)).duplicate(true) as StyleBox
					_apply_padding(native_box, padding)
					control.add_theme_stylebox_override(StringName(name), native_box)
			elif not base_slot.is_empty():
				var native_box := control.get_theme_stylebox(base_slot).duplicate(true) as StyleBox
				_apply_padding(native_box, padding)
				control.add_theme_stylebox_override(base_slot, native_box)
	for name in style.colors:
		control.add_theme_color_override(StringName(name), style.colors[name])
	for name in style.font_sizes:
		control.add_theme_font_size_override(StringName(name), style.font_sizes[name])
	for name in style.fonts:
		control.add_theme_font_override(StringName(name), style.fonts[name])
	for name in style.sounds:
		control.add_theme_sound_override(StringName(name), style.sounds[name])


static func native_stylebox_slot(control: Control) -> StringName:
	if control is BaseButton or control is LineEdit or control is TextEdit or control is RichTextLabel:
		return &"normal"
	if control is PanelContainer or control is ScrollContainer or control is Tree \
			or control is ItemList or control is TabContainer:
		return &"panel"
	if control is ProgressBar:
		return &"background"
	if control is Slider:
		return &"slider"
	return &""


static func _state_padding(style: UIStyleDefinition, state_name: String, base: Vector4) -> Vector4:
	var state: Dictionary = style.states.get(state_name, {})
	if not UIStyleProperties.has_edges(state, "padding"):
		return base
	var override: Dictionary = {}
	for key in ["padding", "padding_left", "padding_top", "padding_right", "padding_bottom"]:
		if state.has(key):
			override[key] = state[key]
	return UIStyleProperties.edges(UIStyleProperties.merge_layer({"padding": base}, override), "padding")


static func _apply_padding(box: StyleBox, value: Variant) -> void:
	var edges := _edges(value)
	box.set_content_margin(SIDE_LEFT, edges.x)
	box.set_content_margin(SIDE_TOP, edges.y)
	box.set_content_margin(SIDE_RIGHT, edges.z)
	box.set_content_margin(SIDE_BOTTOM, edges.w)


static func _apply_layout(control: Control, layout: Dictionary) -> void:
	if control is Button:
		if layout.has("icon_max_width"):
			control.add_theme_constant_override(
				&"icon_max_width", layout["icon_max_width"]
			)
		if layout.has("icon_spacing"):
			control.add_theme_constant_override(
				&"h_separation", layout["icon_spacing"]
			)
	if layout.has("min_size"):
		control.custom_minimum_size = layout["min_size"]
	if layout.has("stretch_x"):
		control.size_flags_horizontal = size_flags(layout["stretch_x"])
	if layout.has("stretch_y"):
		control.size_flags_vertical = size_flags(layout["stretch_y"])
	if layout.has("stretch_ratio"):
		control.size_flags_stretch_ratio = layout["stretch_ratio"]
	if layout.has("opacity"):
		var opacity_color := control.modulate
		opacity_color.a = float(layout["opacity"])
		control.modulate = opacity_color
	var scale_mode: String = layout.get("scale_mode", "transform")
	if scale_mode == "visual_only":
		control.offset_transform_enabled = true
		control.offset_transform_visual_only = true
		control.offset_transform_pivot_ratio = layout.get(
			"pivot_ratio", Vector2(0.5, 0.5)
		)
		if layout.has("pivot_offset"):
			control.offset_transform_pivot = layout["pivot_offset"]
	else:
		if layout.has("pivot_ratio"):
			control.pivot_offset_ratio = layout["pivot_ratio"]
		if layout.has("pivot_offset"):
			control.pivot_offset = layout["pivot_offset"]
	if layout.has("scale"):
		if scale_mode == "visual_only":
			control.offset_transform_scale = layout["scale"]
		else:
			control.scale = layout["scale"]
	if control is BoxContainer:
		_apply_flex_layout(control as BoxContainer, layout)
	elif control.has_method("get_content_box"):
		var inner := control.call("get_content_box") as BoxContainer
		if inner != null:
			_apply_flex_layout(inner, layout)
	if control is GridContainer and layout.has("gap"):
		var grid := control as GridContainer
		grid.add_theme_constant_override(&"h_separation", layout["gap"])
		grid.add_theme_constant_override(&"v_separation", layout["gap"])
	if UIStyleProperties.has_edges(layout, "padding") and control.has_method("set_content_padding"):
		control.call("set_content_padding", UIStyleProperties.edges(layout, "padding"))
	if layout.has("gap") and control.has_method("set_content_gap"):
		control.call("set_content_gap", layout["gap"])


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


static func _wrap_translate(control: Control, layout: Dictionary) -> Control:
	var delta: Vector2 = layout.get("translate", Vector2.ZERO)
	if delta.is_zero_approx():
		return control
	var wrapper := UITranslateContainer.new()
	wrapper.name = "%s_Translate" % control.name
	wrapper.translate = delta
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.size_flags_horizontal = control.size_flags_horizontal
	wrapper.size_flags_vertical = control.size_flags_vertical
	wrapper.size_flags_stretch_ratio = control.size_flags_stretch_ratio
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.add_child(control)
	return wrapper


static func _wrap_margin(control: Control, layout: Dictionary) -> Control:
	var edges := UIStyleProperties.edges(layout, "margin")
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
	var box := parent.content_root as BoxContainer
	if box == null and parent.content_root != null and parent.content_root.has_method("get_content_box"):
		box = parent.content_root.call("get_content_box") as BoxContainer
	if box == null:
		return
	
	if not parent._style_layout.has("cross_alignment"):
		return
	
	var alignment: String = parent._style_layout["cross_alignment"]
	var flags := size_flags(alignment)
	if box.vertical:
		if not child._style_layout.has("stretch_x"):
			child.root.size_flags_horizontal = flags
	else:
		if not child._style_layout.has("stretch_y"):
			child.root.size_flags_vertical = flags
