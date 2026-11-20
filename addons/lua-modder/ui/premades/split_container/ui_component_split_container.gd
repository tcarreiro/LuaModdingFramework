class_name UIComponentSplitContainer extends HSplitContainer


func get_premade_default_size_flags() -> Vector2i:
	return Vector2i(Control.SIZE_EXPAND_FILL, Control.SIZE_EXPAND_FILL)


func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(UIBuiltinIds.SPLIT_CONTAINER, {
		"split_offset": UIPremadeContract.property(TYPE_INT, 0),
		"collapsed": UIPremadeContract.property(TYPE_BOOL, false),
		"dragger_visibility": UIPremadeContract.property(TYPE_STRING, "visible")
	}, "", [&"dragged", &"mouse_entered", &"mouse_exited"], {
		"first": NodePath("First"), "second": NodePath("Second")
	})


func apply_premade_properties(values: Dictionary) -> void:
	if values.has("split_offset"):
		split_offset = values["split_offset"]
	if values.has("collapsed"):
		collapsed = values["collapsed"]
	if values.has("dragger_visibility"):
		match values["dragger_visibility"]:
			"hidden": dragger_visibility = SplitContainer.DRAGGER_HIDDEN
			"hidden_collapsed": dragger_visibility = SplitContainer.DRAGGER_HIDDEN_COLLAPSED
			_: dragger_visibility = SplitContainer.DRAGGER_VISIBLE
	UIPremadeContract.apply_common(self, values)
