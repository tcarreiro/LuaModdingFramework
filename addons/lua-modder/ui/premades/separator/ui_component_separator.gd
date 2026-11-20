class_name UIComponentSeparator extends ColorRect


func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(UIBuiltinIds.SEPARATOR, {
		UIKeys.PROP_DIRECTION: UIPremadeContract.property(TYPE_STRING, UIKeys.VAL_HORIZONTAL),
		UIKeys.PROP_COLOR: UIPremadeContract.property(TYPE_COLOR, Color("#536780")),
		UIKeys.PROP_THICKNESS: UIPremadeContract.property(TYPE_FLOAT, 1.0)
	}, "", [UIKeys.EVENT_MOUSE_ENTERED, UIKeys.EVENT_MOUSE_EXITED])


func apply_premade_properties(values: Dictionary) -> void:
	if values.has(UIKeys.PROP_COLOR):
		color = values[UIKeys.PROP_COLOR]
	var direction: String = values.get(UIKeys.PROP_DIRECTION, UIKeys.VAL_HORIZONTAL)
	var thickness := maxf(0.0, float(values.get(UIKeys.PROP_THICKNESS, 1.0)))
	if direction == UIKeys.VAL_VERTICAL:
		custom_minimum_size = Vector2(thickness, 0.0)
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		custom_minimum_size = Vector2(0.0, thickness)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	UIPremadeContract.apply_common(self, values)
