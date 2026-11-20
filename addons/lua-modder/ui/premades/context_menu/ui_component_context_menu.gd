class_name UIComponentContextMenu extends PanelContainer

signal item_selected(index: int)
signal close_requested

var _entries: Array = []
var _close_on_select := true
var _buttons: Array[Button] = []
var _anchor: Control
var _placement := "bottom"
var _alignment := "start"
var _offset := Vector2(0, 8)
var _flip := true
var _track_anchor := true


func _ready() -> void:
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _process(_delta: float) -> void:
	if visible and _anchor != null:
		if not is_instance_valid(_anchor) or not _anchor.is_inside_tree():
			close()
		elif _track_anchor:
			UIAnchorPositioner.place(self, _anchor.get_global_rect(), _placement, _alignment, _offset, _flip)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
	elif event is InputEventMouseButton and event.pressed and not get_global_rect().has_point(get_global_mouse_position()):
		close()



func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(UIBuiltinIds.CONTEXT_MENU, {
		UIKeys.PROP_OPTIONS: UIPremadeContract.property(TYPE_ARRAY, []),
		"close_on_select": UIPremadeContract.property(TYPE_BOOL, true),
		"placement": UIPremadeContract.property(TYPE_STRING, "bottom"),
		"alignment": UIPremadeContract.property(TYPE_STRING, "start"),
		"offset": UIPremadeContract.property(TYPE_VECTOR2, Vector2(0, 8)),
		"flip": UIPremadeContract.property(TYPE_BOOL, true),
		"track_anchor": UIPremadeContract.property(TYPE_BOOL, true)
	}, "", [
		&"item_selected", &"close_requested", UIKeys.EVENT_MOUSE_ENTERED, UIKeys.EVENT_MOUSE_EXITED
	], {"default": NodePath("Content")})


func apply_premade_properties(values: Dictionary) -> void:
	if values.has("close_on_select"):
		_close_on_select = values["close_on_select"]
	if values.has("placement"):
		_placement = values["placement"]
	if values.has("alignment"):
		_alignment = values["alignment"]
	if values.has("offset"):
		_offset = values["offset"]
	if values.has("flip"):
		_flip = values["flip"]
	if values.has("track_anchor"):
		_track_anchor = values["track_anchor"]
	if values.has(UIKeys.PROP_OPTIONS):
		_entries = values[UIKeys.PROP_OPTIONS].duplicate(true)
		_rebuild()
	UIPremadeContract.apply_common(self, values)


func _rebuild() -> void:
	var content := get_node("Content") as VBoxContainer
	for button in _buttons:
		content.remove_child(button)
		button.queue_free()
	_buttons.clear()
	for index in range(_entries.size()):
		var entry: Variant = _entries[index]
		var button := Button.new()
		if entry is Dictionary:
			button.text = str(entry.get("label", ""))
			button.disabled = bool(entry.get("disabled", false))
		else:
			button.text = str(entry)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_selected.bind(index))
		content.add_child(button)
		_buttons.append(button)


func _on_selected(index: int) -> void:
	item_selected.emit(index)
	if _close_on_select:
		close()


func open_anchored(anchor: Control, placement: String = "bottom", alignment: String = "start", offset: Vector2 = Vector2(0, 8), flip: bool = true) -> void:
	if anchor == null or not anchor.is_inside_tree():
		return
	_anchor = anchor
	_placement = placement
	_alignment = alignment
	_offset = offset
	_flip = flip
	_mount_overlay(anchor)
	visible = true
	set_process(true)
	UIAnchorPositioner.place(self, anchor.get_global_rect(), _placement, _alignment, _offset, _flip)


func open_at(position_global: Vector2) -> void:
	_anchor = null
	_mount_overlay(self)
	visible = true
	set_process(true)
	UIAnchorPositioner.place(self, Rect2(position_global, Vector2.ZERO), "bottom", "start", Vector2.ZERO, true)


func open_at_mouse() -> void:
	open_at(get_global_mouse_position())


func _mount_overlay(origin: Node) -> void:
	var host := UIRootHost.find_from(origin)
	if host == null:
		host = UIRootHost.find_from(self)
	if host == null:
		return
	var layer := host.overlay_root
	if layer == null or get_parent() == layer:
		return
	if get_parent() != null:
		reparent(layer, true)
	else:
		layer.add_child(self)


func close() -> void:
	visible = false
	set_process(false)
	_anchor = null
	close_requested.emit()
