class_name UIComponentStack extends PanelContainer

func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(
		UIBuiltinIds.STACK,
		{},
		"",
		[UIKeys.EVENT_MOUSE_ENTERED, UIKeys.EVENT_MOUSE_EXITED],
		{"default": NodePath("Content")}
	)


func apply_premade_properties(values: Dictionary) -> void:
	UIPremadeContract.apply_common(self, values)
