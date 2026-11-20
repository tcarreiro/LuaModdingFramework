class_name UIAnchorPositioner extends RefCounted


static func place(popup: Control, anchor_rect: Rect2, placement: String = "bottom", alignment: String = "start", offset: Vector2 = Vector2(0, 8), flip: bool = true) -> void:
	popup.reset_size()
	var size := popup.get_combined_minimum_size().max(popup.size)
	var bounds := popup.get_viewport_rect()
	var direction := placement
	if flip:
		if direction == "bottom" and anchor_rect.end.y + offset.y + size.y > bounds.end.y:
			direction = "top"
		elif direction == "top" and anchor_rect.position.y - offset.y - size.y < bounds.position.y:
			direction = "bottom"
		elif direction == "right" and anchor_rect.end.x + offset.x + size.x > bounds.end.x:
			direction = "left"
		elif direction == "left" and anchor_rect.position.x - offset.x - size.x < bounds.position.x:
			direction = "right"
	var position := anchor_rect.position
	if direction in ["bottom", "top"]:
		match alignment:
			"center": position.x += (anchor_rect.size.x - size.x) * 0.5
			"end": position.x += anchor_rect.size.x - size.x
		position.y = anchor_rect.end.y + offset.y if direction == "bottom" else anchor_rect.position.y - size.y - offset.y
		position.x += offset.x
	else:
		match alignment:
			"center": position.y += (anchor_rect.size.y - size.y) * 0.5
			"end": position.y += anchor_rect.size.y - size.y
		position.x = anchor_rect.end.x + offset.x if direction == "right" else anchor_rect.position.x - size.x - offset.x
		position.y += offset.y
	popup.global_position = Vector2(clampf(position.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - size.x)), clampf(position.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - size.y)))
