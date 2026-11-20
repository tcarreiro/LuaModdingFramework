class_name UIComponentColorPicker extends ColorPickerButton

var _swatch: ColorRect


func _ready() -> void:
	custom_minimum_size = Vector2(62, 28)
	_swatch = ColorRect.new()
	_swatch.name = "ColorSwatch"
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_swatch)
	_swatch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_swatch.offset_left = 5
	_swatch.offset_top = 5
	_swatch.offset_right = -5
	_swatch.offset_bottom = -5
	color_changed.connect(_on_color_changed)
	_refresh_swatch()


func _on_color_changed(new_color: Color) -> void:
	color = new_color
	_refresh_swatch()


func _refresh_swatch() -> void:
	if _swatch != null:
		_swatch.color = color


func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(UIBuiltinIds.COLOR_PICKER, {
		UIKeys.PROP_COLOR: UIPremadeContract.property(TYPE_COLOR, Color.WHITE),
		UIKeys.PROP_DISABLED: UIPremadeContract.property(TYPE_BOOL, false),
		UIKeys.PROP_EDITABLE: UIPremadeContract.property(TYPE_BOOL, true)
	}, "", [&"color_changed", &"popup_closed", &"picker_created", UIKeys.EVENT_MOUSE_ENTERED, UIKeys.EVENT_MOUSE_EXITED])


func apply_premade_properties(values: Dictionary) -> void:
	if values.has(UIKeys.PROP_COLOR):
		color = values[UIKeys.PROP_COLOR]
		_refresh_swatch()
	if values.has(UIKeys.PROP_DISABLED):
		disabled = values[UIKeys.PROP_DISABLED]
	if values.has(UIKeys.PROP_EDITABLE):
		edit_alpha = values[UIKeys.PROP_EDITABLE]
	UIPremadeContract.apply_common(self, values)
