class_name UIComponentSlider extends HSlider


func get_premade_default_size_flags() -> Vector2i:
	return Vector2i(Control.SIZE_EXPAND_FILL, Control.SIZE_SHRINK_BEGIN)


func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(UIBuiltinIds.SLIDER, {
		UIKeys.PROP_MIN: UIPremadeContract.property(TYPE_FLOAT, 0.0),
		UIKeys.PROP_MAX: UIPremadeContract.property(TYPE_FLOAT, 100.0),
		UIKeys.PROP_STEP: UIPremadeContract.property(TYPE_FLOAT, 1.0),
		UIKeys.PROP_VALUE: UIPremadeContract.property(TYPE_FLOAT, 0.0),
		UIKeys.PROP_TICKS: UIPremadeContract.property(TYPE_INT, 0),
		UIKeys.PROP_EDITABLE: UIPremadeContract.property(TYPE_BOOL, true)
	}, "", [
		UIKeys.EVENT_VALUE_CHANGED, UIKeys.EVENT_CHANGED,
		UIKeys.EVENT_DRAG_STARTED, UIKeys.EVENT_DRAG_ENDED,
		UIKeys.EVENT_MOUSE_ENTERED, UIKeys.EVENT_MOUSE_EXITED,
		UIKeys.EVENT_FOCUS_ENTERED, UIKeys.EVENT_FOCUS_EXITED
	])


func apply_premade_properties(values: Dictionary) -> void:
	if values.has(UIKeys.PROP_MIN):
		min_value = values[UIKeys.PROP_MIN]
	if values.has(UIKeys.PROP_MAX):
		max_value = values[UIKeys.PROP_MAX]
	if values.has(UIKeys.PROP_STEP):
		step = maxf(0.0, values[UIKeys.PROP_STEP])
	if values.has(UIKeys.PROP_VALUE):
		set_value_no_signal(values[UIKeys.PROP_VALUE])
	if values.has(UIKeys.PROP_TICKS):
		tick_count = maxi(0, values[UIKeys.PROP_TICKS])
	if values.has(UIKeys.PROP_EDITABLE):
		editable = values[UIKeys.PROP_EDITABLE]
	UIPremadeContract.apply_common(self, values)
