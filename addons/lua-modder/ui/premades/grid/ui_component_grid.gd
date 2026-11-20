class_name UIComponentGrid extends GridContainer

func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(
		UIBuiltinIds.GRID,
		{
			UIKeys.PROP_COLUMNS: UIPremadeContract.property(TYPE_INT, 1)
		},
		"",
		[
			UIKeys.EVENT_MOUSE_ENTERED,
			UIKeys.EVENT_MOUSE_EXITED
		]
	)


func apply_premade_properties(values: Dictionary) -> void:
	if values.has(UIKeys.PROP_COLUMNS):
		columns = maxi(1, values[UIKeys.PROP_COLUMNS])
	UIPremadeContract.apply_common(self, values)
