class_name UIComponentDragContainer extends PanelContainer

signal drag_started(payload: Variant)
signal drag_completed(success: bool)
signal item_dropped(payload: Variant)

var _payload: Dictionary = {}
var _can_receive := true
var _can_drag := true
var _drag_active := false
var _preview_layer: UIDragPreviewLayer
var _watching: Dictionary = {}


func _ready() -> void:
	_watch_children(self)


func _watch_children(node: Node) -> void:
	if _watching.has(node.get_instance_id()):
		return
	_watching[node.get_instance_id()] = true
	node.child_entered_tree.connect(_on_child_entered)
	for child in node.get_children():
		_on_child_entered(child)


func _on_child_entered(node: Node) -> void:
	if node is Control and node != self:
		(node as Control).set_drag_forwarding(_get_drag_data, _can_drop_data, _drop_data)
	_watch_children(node)


func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(UIBuiltinIds.DRAG_CONTAINER, {
		"payload": UIPremadeContract.property(TYPE_DICTIONARY, {}),
		"can_drag": UIPremadeContract.property(TYPE_BOOL, true),
		"can_receive": UIPremadeContract.property(TYPE_BOOL, true)
	}, "", [
		&"drag_started", &"drag_completed", &"item_dropped", &"gui_input",
		UIKeys.EVENT_MOUSE_ENTERED, UIKeys.EVENT_MOUSE_EXITED
	], {"default": NodePath("Content")})


func apply_premade_properties(values: Dictionary) -> void:
	if values.has("payload"):
		_payload = values["payload"]
	if values.has("can_drag"):
		_can_drag = values["can_drag"]
	if values.has("can_receive"):
		_can_receive = values["can_receive"]
	UIPremadeContract.apply_common(self, values)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not _can_drag or _payload.is_empty():
		return null
	var host := UIRootHost.find_from(self)
	if host == null or host.drag_preview_layer == null:
		push_warning("Drag preview requires UIRootHost; drag continues without a preview.")
	else:
		var preview := _create_preview()
		if preview != null:
			_preview_layer = host.drag_preview_layer
			if not _preview_layer.begin_drag(self, preview, _payload):
				preview.queue_free()
				_preview_layer = null
	_drag_active = true
	drag_started.emit(_payload)
	return {"source": get_instance_id(), "payload": _payload}



func _create_preview() -> Control:
	var content := get_node_or_null("Content") as Control
	if content == null or content.get_child_count() == 0:
		return null
	var source := content.get_child(0) as Control
	if source == null:
		return null
	var preview_size := source.size
	var visual := source.duplicate(Node.DUPLICATE_SCRIPTS) as Control
	if visual == null:
		return null
	var preview := Control.new()
	preview.name = "DragSlotPreview"
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.custom_minimum_size = preview_size
	preview.size = preview_size
	preview.position = -preview_size * 0.5
	preview.add_child(visual)
	visual.custom_minimum_size = preview_size
	visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ignore_preview_input(preview)
	return preview



func _ignore_preview_input(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(node as Control).focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_ignore_preview_input(child)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return _can_receive and data is Dictionary and data.has("payload") and data.has("source")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_dropped.emit(data["payload"])


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _drag_active:
		if _preview_layer != null and is_instance_valid(_preview_layer):
			_preview_layer.end_drag(self)
		_preview_layer = null
		_drag_active = false
		drag_completed.emit(is_drag_successful())
	elif what == NOTIFICATION_EXIT_TREE:
		if _preview_layer != null and is_instance_valid(_preview_layer):
			_preview_layer.end_drag(self)
		_preview_layer = null
