class_name UIComponentButton extends Button

var _assets: ModAssetRegistry

func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(
		UIBuiltinIds.BUTTON,
		{
			UIKeys.PROP_LABEL: UIPremadeContract.property(TYPE_STRING, ""),
			UIKeys.PROP_DISABLED: UIPremadeContract.property(TYPE_BOOL, false),
			UIKeys.PROP_ICON: UIPremadeContract.property(TYPE_STRING, ""),
			UIKeys.PROP_ICON_ALIGNMENT: UIPremadeContract.property(TYPE_STRING, "left"),
			UIKeys.PROP_ICON_VERTICAL_ALIGNMENT: UIPremadeContract.property(TYPE_STRING, "center"),
			UIKeys.PROP_EXPAND_ICON: UIPremadeContract.property(TYPE_BOOL, false)
		},
		UIBuiltinIds.STYLE_BUTTON,
		[
			UIKeys.EVENT_PRESSED,
			UIKeys.EVENT_BUTTON_DOWN,
			UIKeys.EVENT_BUTTON_UP,
			UIKeys.EVENT_MOUSE_ENTERED,
			UIKeys.EVENT_MOUSE_EXITED,
			UIKeys.EVENT_FOCUS_ENTERED,
			UIKeys.EVENT_FOCUS_EXITED
		]
	)


func get_premade_styles() -> Array[UIStyleDefinition]:
	var style := UIStyleDefinition.new()
	style.id = UIBuiltinIds.STYLE_BUTTON
	style.visual = {
		UIKeys.PROP_BACKGROUND_COLOR: Color("#27354A"),
		UIKeys.PROP_BORDER_COLOR: Color("#506684"),
		UIKeys.PROP_BORDER_WIDTH: 1,
		UIKeys.PROP_BORDER_RADIUS: 8,
		UIKeys.PROP_PADDING: 10
	}
	style.layout = {
		"scale_mode": "visual_only",
		"pivot_ratio": Vector2(0.5, 0.5)
	}
	style.states = {
		UIKeys.STATE_HOVER: {
			UIKeys.PROP_BACKGROUND_COLOR: Color("#354963")
		},
		UIKeys.STATE_PRESSED: {
			UIKeys.PROP_BACKGROUND_COLOR: Color("#1C3249")
		}
	}
	style.transition = {
		"properties": [UIKeys.PROP_BACKGROUND_COLOR],
		"duration": 0.12
	}
	return [style]


func set_asset_registry(registry: ModAssetRegistry) -> void:
	_assets = registry


func apply_premade_properties(values: Dictionary) -> void:
	if values.has(UIKeys.PROP_LABEL):
		text = values[UIKeys.PROP_LABEL]
	
	if values.has(UIKeys.PROP_DISABLED):
		disabled = values[UIKeys.PROP_DISABLED]
	
	if values.has(UIKeys.PROP_ICON):
		var id: String = values[UIKeys.PROP_ICON]
		if id.is_empty():
			icon = null
		elif _assets != null:
			icon = _assets.get_texture(id)
	
	if values.has(UIKeys.PROP_ICON_ALIGNMENT):
		match values[UIKeys.PROP_ICON_ALIGNMENT]:
			UIKeys.VAL_CENTER:
				icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			UIKeys.VAL_RIGHT:
				icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_:
				icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	if values.has(UIKeys.PROP_ICON_VERTICAL_ALIGNMENT):
		match values[UIKeys.PROP_ICON_VERTICAL_ALIGNMENT]:
			UIKeys.VAL_TOP:
				vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			UIKeys.VAL_BOTTOM:
				vertical_icon_alignment = VERTICAL_ALIGNMENT_BOTTOM
			_:
				vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	
	if values.has(UIKeys.PROP_EXPAND_ICON):
		expand_icon = values[UIKeys.PROP_EXPAND_ICON]
	
	UIPremadeContract.apply_common(self, values)
