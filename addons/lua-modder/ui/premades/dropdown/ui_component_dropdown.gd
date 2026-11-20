class_name UIComponentDropdown extends OptionButton

func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(
		UIBuiltinIds.DROPDOWN,
		{
			UIKeys.PROP_OPTIONS: {
				"type": TYPE_ARRAY,
				"item_type": TYPE_STRING,
				"default": [],
				"mod_editable": true
			},
			UIKeys.PROP_SELECTED: UIPremadeContract.property(TYPE_INT, -1),
			UIKeys.PROP_DISABLED: UIPremadeContract.property(TYPE_BOOL, false)
		},
		"",
		[
			UIKeys.EVENT_ITEM_SELECTED,
			UIKeys.EVENT_ITEM_FOCUSED,
			UIKeys.EVENT_MOUSE_ENTERED,
			UIKeys.EVENT_MOUSE_EXITED,
			UIKeys.EVENT_FOCUS_ENTERED,
			UIKeys.EVENT_FOCUS_EXITED
		]
	)


func apply_premade_properties(values: Dictionary) -> void:
	if values.has(UIKeys.PROP_OPTIONS):
		var previous_selection := selected
		var options: Array = values[UIKeys.PROP_OPTIONS]
		clear()
		for option in options:
			add_item(option)
		select(previous_selection if previous_selection < item_count else -1)
	
	if values.has(UIKeys.PROP_SELECTED):
		var index: int = values[UIKeys.PROP_SELECTED]
		select(index if index >= 0 and index < item_count else -1)
	
	if values.has(UIKeys.PROP_DISABLED):
		disabled = values[UIKeys.PROP_DISABLED]
	
	UIPremadeContract.apply_common(self, values)
