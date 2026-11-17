@tool
class_name Registry extends RefCounted

var errors: Array[String] = []
var warnings: Array[String] = []

func clear() -> void:
	push_error("Registry not implemented")
