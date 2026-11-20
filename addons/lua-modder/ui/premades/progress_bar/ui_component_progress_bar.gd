class_name UIComponentProgressBar extends ProgressBar


func get_premade_default_size_flags() -> Vector2i:
	return Vector2i(Control.SIZE_EXPAND_FILL, Control.SIZE_SHRINK_BEGIN)


func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(UIBuiltinIds.PROGRESS_BAR, {
		UIKeys.PROP_MIN: UIPremadeContract.property(TYPE_FLOAT, 0.0),
		UIKeys.PROP_MAX: UIPremadeContract.property(TYPE_FLOAT, 100.0),
		UIKeys.PROP_VALUE: UIPremadeContract.property(TYPE_FLOAT, 0.0),
		UIKeys.PROP_SHOW_PERCENTAGE: UIPremadeContract.property(TYPE_BOOL, true),
		UIKeys.PROP_INDETERMINATE: UIPremadeContract.property(TYPE_BOOL, false)
	}, "", [
		UIKeys.EVENT_VALUE_CHANGED, UIKeys.EVENT_CHANGED,
		UIKeys.EVENT_MOUSE_ENTERED, UIKeys.EVENT_MOUSE_EXITED
	])


func apply_premade_properties(values: Dictionary) -> void:
	if values.has(UIKeys.PROP_MIN):
		min_value = values[UIKeys.PROP_MIN]
	if values.has(UIKeys.PROP_MAX):
		max_value = values[UIKeys.PROP_MAX]
	if values.has(UIKeys.PROP_VALUE):
		set_value_no_signal(values[UIKeys.PROP_VALUE])
	if values.has(UIKeys.PROP_SHOW_PERCENTAGE):
		show_percentage = values[UIKeys.PROP_SHOW_PERCENTAGE]
	if values.has(UIKeys.PROP_INDETERMINATE):
		indeterminate = values[UIKeys.PROP_INDETERMINATE]
	UIPremadeContract.apply_common(self, values)
