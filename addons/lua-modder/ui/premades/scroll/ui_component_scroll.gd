class_name UIComponentScroll extends ScrollContainer

func get_premade_default_size_flags() -> Vector2i:
	return Vector2i(Control.SIZE_EXPAND_FILL, Control.SIZE_SHRINK_BEGIN)


func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(
		UIBuiltinIds.SCROLL,
		{
			UIKeys.PROP_HORIZONTAL_SCROLL: UIPremadeContract.property(TYPE_STRING, "disabled"),
			UIKeys.PROP_VERTICAL_SCROLL: UIPremadeContract.property(TYPE_STRING, "auto"),
			UIKeys.PROP_FOLLOW_FOCUS: UIPremadeContract.property(TYPE_BOOL, true),
			UIKeys.PROP_DIRECTION: UIPremadeContract.property(TYPE_STRING, "vertical")
		},
		"",
		[
			UIKeys.EVENT_MOUSE_ENTERED,
			UIKeys.EVENT_MOUSE_EXITED,
			UIKeys.EVENT_SCROLL_STARTED,
			UIKeys.EVENT_SCROLL_ENDED
		],
		{
			"default": NodePath("ContentPadding/Content")
		}
	)

func apply_premade_properties(values: Dictionary) -> void:
	configure(values)
	UIPremadeContract.apply_common(self, values)

func configure(values: Dictionary) -> void:
	if values.has("horizontal_scroll"):
		horizontal_scroll_mode = _scroll_mode(values["horizontal_scroll"])
	
	if values.has("vertical_scroll"):
		vertical_scroll_mode = _scroll_mode(values["vertical_scroll"])
	
	if values.has("follow_focus"):
		follow_focus = values["follow_focus"]
	
	if values.has("direction"):
		var content := get_node("ContentPadding/Content") as BoxContainer
		content.vertical = values["direction"] == "vertical"


func set_content_padding(edges: Vector4) -> void:
	var padding := get_node("ContentPadding") as MarginContainer
	padding.add_theme_constant_override(&"margin_left", roundi(edges.x))
	padding.add_theme_constant_override(&"margin_top", roundi(edges.y))
	padding.add_theme_constant_override(&"margin_right", roundi(edges.z))
	padding.add_theme_constant_override(&"margin_bottom", roundi(edges.w))


func get_content_box() -> BoxContainer:
	return get_node("ContentPadding/Content") as BoxContainer


func set_content_gap(value: int) -> void:
	var content := get_node("ContentPadding/Content") as BoxContainer
	content.add_theme_constant_override(&"separation", value)


func _scroll_mode(mode: String) -> ScrollContainer.ScrollMode:
	match mode:
		"disabled":
			return ScrollContainer.SCROLL_MODE_DISABLED
		"always":
			return ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
		"reserve":
			return ScrollContainer.SCROLL_MODE_RESERVE
		_:
			return ScrollContainer.SCROLL_MODE_AUTO
