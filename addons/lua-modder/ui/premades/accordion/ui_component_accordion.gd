class_name UIComponentAccordion extends PanelContainer

signal toggled(expanded: bool)

var _expanded := true


func _ready() -> void:
	var header := get_node("Layout/Header") as Button
	header.pressed.connect(_on_header_pressed)
	_refresh()


func get_premade_default_size_flags() -> Vector2i:
	return Vector2i(Control.SIZE_EXPAND_FILL, Control.SIZE_SHRINK_BEGIN)


func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(UIBuiltinIds.ACCORDION, {
		"title": UIPremadeContract.property(TYPE_STRING, ""),
		"expanded": UIPremadeContract.property(TYPE_BOOL, true),
		"disabled": UIPremadeContract.property(TYPE_BOOL, false)
	}, "", [&"toggled", &"mouse_entered", &"mouse_exited"], {"default": NodePath("Layout/Content")})


func apply_premade_properties(values: Dictionary) -> void:
	if values.has("title"):
		(get_node("Layout/Header") as Button).text = values["title"]
	if values.has("expanded"):
		_expanded = values["expanded"]
	if values.has("disabled"):
		(get_node("Layout/Header") as Button).disabled = values["disabled"]
	_refresh()
	UIPremadeContract.apply_common(self, values)


func set_expanded(expanded: bool) -> void:
	if _expanded == expanded:
		return
	_expanded = expanded
	_refresh()
	toggled.emit(_expanded)


func _on_header_pressed() -> void:
	set_expanded(not _expanded)


func _refresh() -> void:
	(get_node("Layout/Content") as Control).visible = _expanded
	var header := get_node("Layout/Header") as Button
	header.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
