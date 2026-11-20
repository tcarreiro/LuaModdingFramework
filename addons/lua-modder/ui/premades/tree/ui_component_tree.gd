class_name UIComponentTree extends Tree

var _entries: Array = []


func get_premade_default_size_flags() -> Vector2i:
	return Vector2i(Control.SIZE_EXPAND_FILL, Control.SIZE_SHRINK_BEGIN)


func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(UIBuiltinIds.TREE, {
		"items": UIPremadeContract.property(TYPE_ARRAY, []),
		"hide_root": UIPremadeContract.property(TYPE_BOOL, true),
		"columns": UIPremadeContract.property(TYPE_INT, 1),
		"select_mode": UIPremadeContract.property(TYPE_STRING, "single")
	}, "", [&"item_selected", &"item_activated", &"nothing_selected", &"cell_selected", UIKeys.EVENT_MOUSE_ENTERED, UIKeys.EVENT_MOUSE_EXITED])


func apply_premade_properties(values: Dictionary) -> void:
	if values.has("hide_root"):
		hide_root = values["hide_root"]
	if values.has("columns"):
		columns = maxi(1, values["columns"])
	if values.has("select_mode"):
		select_mode = Tree.SELECT_MULTI if values["select_mode"] == "multi" else Tree.SELECT_SINGLE
	if values.has("items"):
		_entries = values["items"].duplicate(true)
		_rebuild()
	UIPremadeContract.apply_common(self, values)


func _rebuild() -> void:
	clear()
	var root := create_item()
	for entry in _entries:
		_append(root, entry, 0)


func _append(parent: TreeItem, entry: Variant, depth: int) -> void:
	if depth >= 32:
		return
	var item := create_item(parent)
	if entry is Dictionary:
		item.set_text(0, str(entry.get("label", "")))
		item.set_metadata(0, entry.get("id", ""))
		for child in entry.get("children", []):
			_append(item, child, depth + 1)
	else:
		item.set_text(0, str(entry))
