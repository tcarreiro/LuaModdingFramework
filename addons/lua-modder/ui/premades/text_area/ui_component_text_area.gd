class_name UIComponentTextArea extends TextEdit


func get_premade_default_size_flags() -> Vector2i:
	return Vector2i(Control.SIZE_EXPAND_FILL, Control.SIZE_SHRINK_BEGIN)


func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(UIBuiltinIds.TEXT_AREA, {
		"text": UIPremadeContract.property(TYPE_STRING, ""),
		"placeholder": UIPremadeContract.property(TYPE_STRING, ""),
		"editable": UIPremadeContract.property(TYPE_BOOL, true),
		"wrap": UIPremadeContract.property(TYPE_BOOL, true)
	}, "", [&"text_changed", &"caret_changed", &"lines_edited_from", &"focus_entered", &"focus_exited", &"mouse_entered", &"mouse_exited"])


func apply_premade_properties(values: Dictionary) -> void:
	if values.has("text"):
		text = values["text"]
	if values.has("placeholder"):
		placeholder_text = values["placeholder"]
	if values.has("editable"):
		editable = values["editable"]
	if values.has("wrap"):
		wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY if values["wrap"] else TextEdit.LINE_WRAPPING_NONE
	UIPremadeContract.apply_common(self, values)
