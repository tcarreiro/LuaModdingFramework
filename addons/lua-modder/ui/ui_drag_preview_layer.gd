class_name UIDragPreviewLayer extends CanvasLayer

var _source: WeakRef
var _preview: Control
var _preview_offset := Vector2.ZERO
var _customizer: Callable


func set_preview_customizer(handler: Callable) -> void:
	_customizer = handler

func _ready() -> void:
	set_process(false)


func begin_drag(source: Control, preview: Control, payload: Dictionary = {}) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	
	if preview == null or not is_instance_valid(preview):
		return false
	
	if not is_inside_tree() or not source.is_inside_tree():
		return false
	
	if source.get_viewport() != get_viewport():
		return false
	
	if preview.get_parent() != null:
		return false
	if _customizer.is_valid():
		var replacement: Variant = _customizer.call(source, preview, payload.duplicate(true))
		if replacement is Control and replacement != preview:
			var next_preview := replacement as Control
			if is_instance_valid(next_preview) and next_preview.get_parent() == null:
				preview.free()
				preview = next_preview
			else:
				push_warning("Drag preview customizer returned a Control already mounted in the tree.")
	if preview == null or not is_instance_valid(preview):
		return false
	_clear_preview()
	_source = weakref(source)
	_preview = preview
	_preview_offset = preview.position
	_disable_input(_preview)
	add_child(_preview)
	_update_position()
	set_process(true)
	return true


func _disable_input(node: Node) -> void:
	if node is Control:
		var control := node as Control
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_disable_input(child)


func end_drag(source: Control) -> void:
	if _source == null:
		return
	if _source.get_ref() != source:
		return
	_clear_preview()


func has_active_preview() -> bool:
	return _preview != null and is_instance_valid(_preview)


func _process(_delta: float) -> void:
	if _source == null:
		_clear_preview()
		return
	
	var source := _source.get_ref() as Control
	if source == null or not source.is_inside_tree():
		_clear_preview()
		return
	_update_position()


func _update_position() -> void:
	if not has_active_preview():
		return
	_preview.position = get_viewport().get_mouse_position() + _preview_offset


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_preview()


func _exit_tree() -> void:
	_clear_preview()


func _clear_preview() -> void:
	set_process(false)
	var previous := _preview
	_preview = null
	_source = null
	_preview_offset = Vector2.ZERO
	if previous != null and is_instance_valid(previous):
		previous.hide()
		previous.queue_free()
