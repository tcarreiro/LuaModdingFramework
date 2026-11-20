class_name UIStackLayerLayout extends Container

func _get_minimum_size() -> Vector2:
	for node in get_children():
		if node is Control and not node.is_set_as_top_level():
			return (node as Control).get_combined_minimum_size()
	return Vector2.ZERO


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_layout_layers()


func _layout_layers() -> void:
	var anchor_rect := Rect2(Vector2.ZERO, size)
	for node in get_children():
		if not node is Control or node.is_set_as_top_level():
			continue
		var control := node as Control
		if not control.visible:
			continue
		var horizontal: String = control.get_meta(&"ui_justify_self", "stretch")
		var vertical: String = control.get_meta(&"ui_align_self", "stretch")
		var minimum := control.get_combined_minimum_size()
		var target_size := minimum
		if horizontal == "stretch" and control.custom_minimum_size.x <= 0:
			target_size.x = maxf(minimum.x, anchor_rect.size.x)
		if vertical == "stretch" and control.custom_minimum_size.y <= 0:
			target_size.y = maxf(minimum.y, anchor_rect.size.y)
	
		var target_position := anchor_rect.position
		match horizontal:
			"center":
				target_position.x += (anchor_rect.size.x - target_size.x) * 0.5
			"end":
				target_position.x += anchor_rect.size.x - target_size.x
		match vertical:
			"center":
				target_position.y += (anchor_rect.size.y - target_size.y) * 0.5
			"end":
				target_position.y += anchor_rect.size.y - target_size.y
	
		var layer_rect := Rect2(target_position, target_size)
		fit_child_in_rect(control, layer_rect)
		anchor_rect = layer_rect
