class_name UIComponentItemSlot extends PanelContainer

signal activated(button: int)

func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(UIBuiltinIds.ITEM_SLOT, {
		UIKeys.PROP_DISABLED: UIPremadeContract.property(TYPE_BOOL, false),
		"selected": UIPremadeContract.property(TYPE_BOOL, false),
		"slot_id": UIPremadeContract.property(TYPE_STRING, "")
	}, "", [
		&"activated", &"gui_input", UIKeys.EVENT_MOUSE_ENTERED, UIKeys.EVENT_MOUSE_EXITED
	], {"default": NodePath("Content")})


func apply_premade_properties(values: Dictionary) -> void:
	if values.has("slot_id"):
		set_meta(&"slot_id", values["slot_id"])
	if values.has("selected"):
		set_meta(&"selected", values["selected"])
	if values.has(UIKeys.PROP_DISABLED):
		set_meta(&"disabled", values[UIKeys.PROP_DISABLED])
	UIPremadeContract.apply_common(self, values)


func _gui_input(event: InputEvent) -> void:
	if get_meta(&"disabled", false):
		return
	if event is InputEventMouseButton and event.pressed:
		activated.emit(event.button_index)
