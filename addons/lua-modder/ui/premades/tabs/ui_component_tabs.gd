class_name UIComponentTabs extends TabContainer

var _tab_titles: Array = []


func _ready() -> void:
	child_entered_tree.connect(_on_child_entered)
	_refresh_titles.call_deferred()


func get_premade_default_size_flags() -> Vector2i:
	return Vector2i(Control.SIZE_EXPAND_FILL, Control.SIZE_SHRINK_BEGIN)


func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(UIBuiltinIds.TABS, {
		UIKeys.PROP_TABS: {"type": TYPE_ARRAY, "item_type": TYPE_STRING, "default": [], "mod_editable": true},
		UIKeys.PROP_SELECTED_TAB: UIPremadeContract.property(TYPE_INT, 0)
	}, "", [
		UIKeys.EVENT_TAB_CHANGED, UIKeys.EVENT_TAB_CLICKED,
		UIKeys.EVENT_MOUSE_ENTERED, UIKeys.EVENT_MOUSE_EXITED
	])


func apply_premade_properties(values: Dictionary) -> void:
	if values.has(UIKeys.PROP_TABS):
		_tab_titles = values[UIKeys.PROP_TABS].duplicate()
		_refresh_titles()
	if values.has(UIKeys.PROP_SELECTED_TAB):
		# A pending index is applied after children are attached to the slot.
		set_meta(&"requested_tab", values[UIKeys.PROP_SELECTED_TAB])
		_apply_selection()
	UIPremadeContract.apply_common(self, values)


func _on_child_entered(_child: Node) -> void:
	_refresh_titles.call_deferred()


func _refresh_titles() -> void:
	for index in range(mini(get_tab_count(), _tab_titles.size())):
		set_tab_title(index, _tab_titles[index])
	_apply_selection()


func _apply_selection() -> void:
	if get_tab_count() == 0:
		return
	var index: int = get_meta(&"requested_tab", 0)
	current_tab = clampi(index, 0, get_tab_count() - 1)
