class_name UIComponentDiv extends PanelContainer

func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(
		UIBuiltinIds.DIV,
		{
			UIKeys.PROP_DIRECTION: UIPremadeContract.property(TYPE_STRING, UIKeys.VAL_VERTICAL)
		},
		UIBuiltinIds.STYLE_DIV,
		[
			UIKeys.EVENT_MOUSE_ENTERED,
			UIKeys.EVENT_MOUSE_EXITED
		],
		{
			"default": NodePath("Content")
		}
	)


func get_premade_styles() -> Array[UIStyleDefinition]:
	var style := UIStyleDefinition.new()
	style.id = UIBuiltinIds.STYLE_DIV
	style.visual = {
		UIKeys.PROP_BACKGROUND_COLOR: Color.TRANSPARENT
	}
	return [style]


func apply_premade_properties(values: Dictionary) -> void:
	if values.has(UIKeys.PROP_DIRECTION):
		var content := get_node("Content") as BoxContainer
		content.vertical = values[UIKeys.PROP_DIRECTION] == UIKeys.VAL_VERTICAL
	UIPremadeContract.apply_common(self, values)


func set_content_gap(value: int) -> void:
	var content := get_node("Content") as BoxContainer
	content.add_theme_constant_override(&"separation", maxi(0, value))


func get_content_box() -> BoxContainer:
	return get_node("Content") as BoxContainer
