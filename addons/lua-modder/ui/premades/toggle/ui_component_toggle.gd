class_name UIComponentToggle extends CheckButton


func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(UIBuiltinIds.TOGGLE, {
		UIKeys.PROP_LABEL: UIPremadeContract.property(TYPE_STRING, ""),
		UIKeys.PROP_CHECKED: UIPremadeContract.property(TYPE_BOOL, false),
		UIKeys.PROP_DISABLED: UIPremadeContract.property(TYPE_BOOL, false)
	}, "", [
		UIKeys.EVENT_TOGGLED, UIKeys.EVENT_PRESSED,
		UIKeys.EVENT_MOUSE_ENTERED, UIKeys.EVENT_MOUSE_EXITED,
		UIKeys.EVENT_FOCUS_ENTERED, UIKeys.EVENT_FOCUS_EXITED
	])


func apply_premade_properties(values: Dictionary) -> void:
	if values.has(UIKeys.PROP_LABEL):
		text = values[UIKeys.PROP_LABEL]
	if values.has(UIKeys.PROP_CHECKED):
		set_pressed_no_signal(values[UIKeys.PROP_CHECKED])
	if values.has(UIKeys.PROP_DISABLED):
		disabled = values[UIKeys.PROP_DISABLED]
	UIPremadeContract.apply_common(self, values)
