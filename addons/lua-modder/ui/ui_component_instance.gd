@tool
class_name UIComponentInstance extends RefCounted

var root: Control
var content_root: Control
var component_id: String
var values: Dictionary = {}
var transition: UIStyleTransition
var animation: UIAnimationPlayer
var interaction: UIComponentInteraction

var _registry: UIComponentRegistry
var _trusted: bool = false
var _root_component: UIComponentInstance
var _children: Array[UIComponentInstance] = []
var _bindings: Dictionary = {}
var _style_layout: Dictionary = {}
var _named_children: Dictionary[String, UIComponentInstance] = {}
var _event_forwarders: Array[Dictionary] = []

func get_recognized_properties() -> Dictionary:
	if _registry == null:
		return {}
	return _registry.get_recognized_properties(component_id, _trusted)


func update(changes: Dictionary) -> bool:
	return _registry != null and _registry.update_component(self, changes)


func get_slot(slot_name: String = "default") -> Control:
	return _registry.get_slot(self, slot_name) if _registry != null else null


func get_drag_target() -> Control:
	return _registry.get_drag_target(self) if _registry != null else null


func get_drag_handle() -> Control:
	return _registry.get_drag_handle(self) if _registry != null else null


func play_animation(animation_id: String) -> bool:
	return _registry != null and _registry.play_animation(self, animation_id)


func stop_animation() -> void:
	if animation != null:
		animation.stop()


func on_event(event_name: StringName, handler: Callable) -> bool:
	var controller := _registry.ensure_interaction(self)
	return controller != null and controller.on_event(event_name, handler)


func off_event(event_name: StringName, handler: Callable) -> bool:
	if interaction == null:
		return false
	return interaction.off_event(event_name, handler)


func emit_event(event_name: StringName, arguments: Array = []) -> bool:
	var controller := _registry.ensure_interaction(self)
	return controller != null and controller.emit_event(event_name, arguments)


func set_hook(hook_name: StringName, handler: Callable) -> bool:
	var controller := _registry.ensure_interaction(self)
	return controller != null and controller.set_hook(hook_name, handler)


func remove_hook(hook_name: StringName) -> void:
	if interaction != null:
		interaction.remove_hook(hook_name)


func call_hook(hook_name: StringName, arguments: Array = []) -> Variant:
	var controller := _registry.ensure_interaction(self)
	if controller == null:
		return null
	return controller.call_hook(hook_name, arguments)



func clear_callbacks() -> void:
	for entry in _event_forwarders:
		var child: UIComponentInstance = entry["child"]
		child.off_event(entry["event"], entry["listener"])
	_event_forwarders.clear()
	
	if interaction != null:
		interaction.clear()
		interaction = null
	
	if _root_component != null:
		_root_component.clear_callbacks()
	
	for child in _children:
		child.clear_callbacks()
