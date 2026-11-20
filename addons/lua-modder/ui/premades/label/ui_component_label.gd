class_name UIComponentLabel extends Label


func get_premade_default_size_flags() -> Vector2i:
	return Vector2i(Control.SIZE_EXPAND_FILL, Control.SIZE_SHRINK_BEGIN)

func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(
		UIBuiltinIds.LABEL,
		{
			UIKeys.PROP_TEXT: UIPremadeContract.property(TYPE_STRING, ""),
			UIKeys.PROP_ALIGN: UIPremadeContract.property(TYPE_STRING, "left"),
			UIKeys.PROP_VALIGN: UIPremadeContract.property(TYPE_STRING, "top"),
			UIKeys.PROP_AUTOWRAP: UIPremadeContract.property(TYPE_BOOL, false)
		},
		UIBuiltinIds.STYLE_LABEL,
		[
			UIKeys.EVENT_MOUSE_ENTERED,
			UIKeys.EVENT_MOUSE_EXITED
		]
	)


func get_premade_styles() -> Array[UIStyleDefinition]:
	var style := UIStyleDefinition.new()
	style.id = UIBuiltinIds.STYLE_LABEL
	style.colors = {
		UIKeys.PROP_FONT_COLOR: Color.WHITE
	}
	return [style]


func apply_premade_properties(values: Dictionary) -> void:
	if values.has(UIKeys.PROP_TEXT):
		text = values[UIKeys.PROP_TEXT]
	if values.has(UIKeys.PROP_ALIGN):
		match values[UIKeys.PROP_ALIGN]:
			"center":
				horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			"right":
				horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_:
				horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if values.has(UIKeys.PROP_VALIGN):
		match values[UIKeys.PROP_VALIGN]:
			"center":
				vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			"bottom":
				vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			_:
				vertical_alignment = VERTICAL_ALIGNMENT_TOP
	
	if values.has(UIKeys.PROP_AUTOWRAP):
		autowrap_mode = TextServer.AUTOWRAP_WORD_SMART \
			if values[UIKeys.PROP_AUTOWRAP] \
			else TextServer.AUTOWRAP_OFF
	
	UIPremadeContract.apply_common(self, values)
