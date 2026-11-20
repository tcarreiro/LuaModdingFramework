class_name UIComponentSpinBox extends SpinBox


func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(UIBuiltinIds.SPIN_BOX, {
		UIKeys.PROP_MIN: UIPremadeContract.property(TYPE_FLOAT, 0.0),
		UIKeys.PROP_MAX: UIPremadeContract.property(TYPE_FLOAT, 100.0),
		UIKeys.PROP_STEP: UIPremadeContract.property(TYPE_FLOAT, 1.0),
		UIKeys.PROP_VALUE: UIPremadeContract.property(TYPE_FLOAT, 0.0),
		UIKeys.PROP_EDITABLE: UIPremadeContract.property(TYPE_BOOL, true),
		"prefix": UIPremadeContract.property(TYPE_STRING, ""),
		"suffix": UIPremadeContract.property(TYPE_STRING, "")
	}, "", [UIKeys.EVENT_VALUE_CHANGED, UIKeys.EVENT_CHANGED, UIKeys.EVENT_FOCUS_ENTERED, UIKeys.EVENT_FOCUS_EXITED])


func apply_premade_properties(values: Dictionary) -> void:
	if values.has(UIKeys.PROP_MIN):
		min_value = values[UIKeys.PROP_MIN]
	if values.has(UIKeys.PROP_MAX):
		max_value = values[UIKeys.PROP_MAX]
	if values.has(UIKeys.PROP_STEP):
		step = maxf(0.0, values[UIKeys.PROP_STEP])
	if values.has(UIKeys.PROP_VALUE):
		set_value_no_signal(values[UIKeys.PROP_VALUE])
	if values.has(UIKeys.PROP_EDITABLE):
		editable = values[UIKeys.PROP_EDITABLE]
	if values.has("prefix"):
		prefix = values["prefix"]
	if values.has("suffix"):
		suffix = values["suffix"]
	UIPremadeContract.apply_common(self, values)
