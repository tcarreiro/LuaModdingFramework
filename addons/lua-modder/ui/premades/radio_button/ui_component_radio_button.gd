class_name UIComponentRadioButton extends CheckBox

var _group_name := "default"


func _ready() -> void:
	_join_group()


func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(UIBuiltinIds.RADIO_BUTTON, {
		UIKeys.PROP_LABEL: UIPremadeContract.property(TYPE_STRING, ""),
		UIKeys.PROP_CHECKED: UIPremadeContract.property(TYPE_BOOL, false),
		UIKeys.PROP_DISABLED: UIPremadeContract.property(TYPE_BOOL, false),
		UIKeys.PROP_GROUP: UIPremadeContract.property(TYPE_STRING, "default")
	}, "", [
		UIKeys.EVENT_TOGGLED, UIKeys.EVENT_PRESSED,
		UIKeys.EVENT_MOUSE_ENTERED, UIKeys.EVENT_MOUSE_EXITED,
		UIKeys.EVENT_FOCUS_ENTERED, UIKeys.EVENT_FOCUS_EXITED
	])


func apply_premade_properties(values: Dictionary) -> void:
	if values.has(UIKeys.PROP_LABEL):
		text = values[UIKeys.PROP_LABEL]
	if values.has(UIKeys.PROP_GROUP):
		_group_name = values[UIKeys.PROP_GROUP]
		if is_inside_tree():
			_join_group()
	if values.has(UIKeys.PROP_CHECKED):
		set_pressed_no_signal(values[UIKeys.PROP_CHECKED])
	if values.has(UIKeys.PROP_DISABLED):
		disabled = values[UIKeys.PROP_DISABLED]
	UIPremadeContract.apply_common(self, values)


func _join_group() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var group_resource: ButtonGroup = null
	for sibling in parent.get_children():
		if sibling == self or not sibling is UIComponentRadioButton:
			continue
		var radio := sibling as UIComponentRadioButton
		if radio._group_name == _group_name and radio.button_group != null:
			group_resource = radio.button_group
			break
	if group_resource == null:
		group_resource = ButtonGroup.new()
	group_resource.allow_unpress = false
	button_group = group_resource
