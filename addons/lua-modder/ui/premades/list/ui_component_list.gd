class_name UIComponentList extends ItemList


func get_premade_default_size_flags() -> Vector2i:
	return Vector2i(Control.SIZE_EXPAND_FILL, Control.SIZE_SHRINK_BEGIN)


func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(UIBuiltinIds.LIST, {
		UIKeys.PROP_OPTIONS: UIPremadeContract.property(TYPE_ARRAY, []),
		UIKeys.PROP_SELECTED: UIPremadeContract.property(TYPE_INT, -1),
		"multi_select": UIPremadeContract.property(TYPE_BOOL, false),
		UIKeys.PROP_COLUMNS: UIPremadeContract.property(TYPE_INT, 1),
		UIKeys.PROP_DISABLED: UIPremadeContract.property(TYPE_BOOL, false)
	}, "", [
		&"item_selected", &"multi_selected", &"item_activated", &"empty_clicked",
		UIKeys.EVENT_MOUSE_ENTERED, UIKeys.EVENT_MOUSE_EXITED
	])


func apply_premade_properties(values: Dictionary) -> void:
	if values.has("multi_select"):
		select_mode = ItemList.SELECT_MULTI if values["multi_select"] else ItemList.SELECT_SINGLE
	if values.has(UIKeys.PROP_COLUMNS):
		max_columns = maxi(1, values[UIKeys.PROP_COLUMNS])
	if values.has(UIKeys.PROP_OPTIONS):
		clear()
		for option in values[UIKeys.PROP_OPTIONS]:
			add_item(str(option))
	if values.has(UIKeys.PROP_SELECTED):
		var index: int = values[UIKeys.PROP_SELECTED]
		deselect_all()
		if index >= 0 and index < item_count:
			select(index)
	if values.has(UIKeys.PROP_DISABLED):
		mouse_filter = Control.MOUSE_FILTER_IGNORE if values[UIKeys.PROP_DISABLED] else Control.MOUSE_FILTER_STOP
	UIPremadeContract.apply_common(self, values)
