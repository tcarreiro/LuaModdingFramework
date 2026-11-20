class_name UITranslateContainer extends Container

var translate := Vector2.ZERO:
	set(value):
		translate = value
		queue_sort()


func _get_minimum_size() -> Vector2:
	for node in get_children():
		if node is Control:
			return (node as Control).get_combined_minimum_size()
	return Vector2.ZERO


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	for node in get_children():
		if node is Control:
			fit_child_in_rect(node as Control, Rect2(translate, size))
