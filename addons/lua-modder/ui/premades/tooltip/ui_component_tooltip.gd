class_name UIComponentTooltip extends MarginContainer

var _hint := ""


func _ready() -> void:
	_watch_node(self)


func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(UIBuiltinIds.TOOLTIP, {
		UIKeys.PROP_TEXT: UIPremadeContract.property(TYPE_STRING, "")
	}, "", [
		UIKeys.EVENT_MOUSE_ENTERED, UIKeys.EVENT_MOUSE_EXITED
	], {"default": NodePath("Content")})


func apply_premade_properties(values: Dictionary) -> void:
	if values.has(UIKeys.PROP_TEXT):
		_hint = values[UIKeys.PROP_TEXT]
		_apply_hint(self)
	UIPremadeContract.apply_common(self, values)


func _on_child_entered(child: Node) -> void:
	if child is Control:
		_watch_node(child as Control)


func _watch_node(control: Control) -> void:
	_apply_hint(control)
	if not control.child_entered_tree.is_connected(_on_child_entered):
		control.child_entered_tree.connect(_on_child_entered)
	for child in control.get_children():
		if child is Control:
			_watch_node(child as Control)


func _apply_hint(control: Control) -> void:
	control.tooltip_text = _hint
	for child in control.get_children():
		if child is Control:
			_apply_hint(child)
