class_name UIRootHost extends Node

const ROOT_META := &"_lua_modder_ui_root"
const FLOATING_AREA_META := &"_lua_modder_floating_area"

const SCREEN := &"screen"
const OVERLAY := &"overlay"
const MODAL := &"modal"
const DRAG_PREVIEW := &"drag_preview"

const DEFAULT_SCREEN_INDEX := 1
const DEFAULT_OVERLAY_INDEX := 10
const DEFAULT_MODAL_INDEX := 20
const DEFAULT_DRAG_INDEX := 1024

var errors: Array[String] = []

var _layers: Dictionary = {}
var _drag_preview: UIDragPreviewLayer

var screen_root: Control:
	get:
		return get_mount(SCREEN)

var overlay_root: Control:
	get:
		return get_mount(OVERLAY)

var modal_root: Control:
	get:
		return get_mount(MODAL)

var drag_preview_layer: UIDragPreviewLayer:
	get:
		return _drag_preview


func _ready() -> void:
	_create_managed_layer(SCREEN, DEFAULT_SCREEN_INDEX, true)
	_create_managed_layer(OVERLAY, DEFAULT_OVERLAY_INDEX, true)
	_create_managed_layer(MODAL, DEFAULT_MODAL_INDEX, true)
	_create_drag_preview_layer()


func set_drag_preview_customizer(handler: Callable) -> void:
	if _drag_preview != null:
		_drag_preview.set_preview_customizer(handler)


func _create_drag_preview_layer() -> void:
	_drag_preview = UIDragPreviewLayer.new()
	_drag_preview.name = "DragPreviewLayer"
	_drag_preview.layer = DEFAULT_DRAG_INDEX
	add_child(_drag_preview)
	_layers[DRAG_PREVIEW] = {
		"canvas": _drag_preview,
		"root": null,
		"managed": true,
		"exposed_to_mods": false
	}
	_ensure_drag_preview_on_top()

#region Registration
func create_layer(id: StringName, layer_index: int, exposed_to_mods: bool = false) -> bool:
	errors.clear()
	if not _validate_registration(id, layer_index):
		return false
	_create_managed_layer(id, layer_index, exposed_to_mods)
	_ensure_drag_preview_on_top()
	return true


func register_layer(id: StringName, canvas: CanvasLayer, mount: Control, exposed_to_mods: bool = false) -> bool:
	errors.clear()
	if canvas == null or not is_instance_valid(canvas):
		return _error("Cannot register an invalid CanvasLayer.")
	
	if mount == null or not is_instance_valid(mount):
		return _error("Cannot register an invalid UI mount.")
	
	if not _validate_registration(id, canvas.layer):
		return false
	
	if not canvas.is_inside_tree() or not mount.is_inside_tree():
		return _error("External UI layers must be inside the SceneTree.")
	
	if canvas.get_viewport() != get_viewport():
		return _error("External CanvasLayer belongs to another Viewport.")
	
	if not canvas.is_ancestor_of(mount):
		return _error("UI mount must be a descendant of its CanvasLayer.")
	
	for entry in _layers.values():
		if entry["canvas"] == canvas or entry["root"] == mount:
			return _error("CanvasLayer or UI mount is already registered.")
	
	if mount.has_meta(ROOT_META):
		return _error("External UI mount is already associated with a UI host.")
	
	_layers[id] = {
		"canvas": canvas,
		"root": mount,
		"managed": false,
		"exposed_to_mods": exposed_to_mods
	}
	mount.set_meta(ROOT_META, weakref(self))
	_ensure_drag_preview_on_top()
	return true


func _create_managed_layer(id: StringName, layer_index: int, exposed_to_mods: bool) -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "%sLayer" % String(id).capitalize().replace(" ", "")
	canvas.layer = layer_index
	add_child(canvas)
	
	var mount := Control.new()
	mount.name = "%sRoot" % String(id).capitalize().replace(" ", "")
	mount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(mount)
	mount.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	_layers[id] = {
		"canvas": canvas,
		"root": mount,
		"managed": true,
		"exposed_to_mods": exposed_to_mods
	}


func _validate_registration(id: StringName, layer_index: int) -> bool:
	if not is_inside_tree() or not is_node_ready():
		return _error("UIRootHost must be ready before registering layers.")
	
	if String(id).strip_edges().is_empty():
		return _error("UI layer ID cannot be empty.")
	
	if _layers.has(id):
		return _error("UI layer '%s' already exists." % id)
	
	if not _is_index_available(layer_index):
		return _error("UI layer index %d is already in use." % layer_index)
	
	return true
#endregion


#region Layer configuration
func set_layer_index(id: StringName, layer_index: int) -> bool:
	errors.clear()
	if not _layers.has(id):
		return _error("Unknown UI layer '%s'." % id)
	
	if id == DRAG_PREVIEW:
		if layer_index <= _highest_content_layer_index():
			return _error("Drag preview must remain above all UI layers.")
		_drag_preview.layer = layer_index
		return true
	
	if not _is_index_available(layer_index, id):
		return _error("UI layer index %d is already in use." % layer_index)
	var canvas := get_layer(id)
	if canvas == null:
		return _error("UI layer '%s' is unavailable." % id)
	
	canvas.layer = layer_index
	_ensure_drag_preview_on_top()
	return true


func set_layer_exposed_to_mods(id: StringName, exposed: bool) -> bool:
	errors.clear()
	if not _layers.has(id):
		return _error("Unknown UI layer '%s'." % id)
	
	if id == DRAG_PREVIEW and exposed:
		return _error("Drag preview cannot be exposed as a UI mount.")
	
	_layers[id]["exposed_to_mods"] = exposed
	return true


func is_layer_exposed_to_mods(id: StringName) -> bool:
	if id == DRAG_PREVIEW or not _layers.has(id):
		return false
	return _layers[id]["exposed_to_mods"]


func _is_index_available(layer_index: int, except_id: StringName = &"") -> bool:
	for id in _layers:
		if id == except_id or id == DRAG_PREVIEW:
			continue
		var canvas := _layers[id]["canvas"] as CanvasLayer
		if is_instance_valid(canvas) and canvas.layer == layer_index:
			return false
	return true


func _highest_content_layer_index() -> int:
	var highest := -2147483648
	for id in _layers:
		if id == DRAG_PREVIEW:
			continue
		var canvas := _layers[id]["canvas"] as CanvasLayer
		if is_instance_valid(canvas):
			highest = maxi(highest, canvas.layer)
	return highest


func _ensure_drag_preview_on_top() -> void:
	if _drag_preview == null or not is_instance_valid(_drag_preview):
		return
	var highest := _highest_content_layer_index()
	if _drag_preview.layer <= highest:
		_drag_preview.layer = highest + 1
#endregion


#region Queries
func has_layer(id: StringName) -> bool:
	return _layers.has(id)


func get_layer(id: StringName) -> CanvasLayer:
	if not _layers.has(id):
		return null
	var canvas: CanvasLayer = _layers[id]["canvas"]
	return canvas if is_instance_valid(canvas) else null


func get_mount(id: StringName) -> Control:
	if id == DRAG_PREVIEW or not _layers.has(id):
		return null
	var mount: Control = _layers[id]["root"]
	return mount if is_instance_valid(mount) else null


func get_layer_index(id: StringName) -> Variant:
	var canvas := get_layer(id)
	return canvas.layer if canvas != null else null


func is_layer_managed(id: StringName) -> bool:
	return _layers.has(id) and _layers[id]["managed"]


func get_layer_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for id in _layers:
		result.append(id)
	return result
#endregion


#region Component mounting
func mount_component(content: Control, placement: String, backdrop_enabled: bool = false,
	backdrop_style: StyleBox = null, backdrop_mouse_filter: int = Control.MOUSE_FILTER_STOP,
	initial_position: Variant = null) -> Control:
	if content == null or not is_instance_valid(content):
		return null
	
	if content.get_parent() != null:
		return null
	
	var target := get_mount(StringName(placement))
	if target == null:
		return null
		
	var area := target
	var visual_root: Control = content
	if backdrop_enabled:
		visual_root = _create_backdrop_wrapper(target, backdrop_style, backdrop_mouse_filter)
		area = visual_root
	area.add_child(content)
	if placement == "screen":
		return visual_root
	
	content.set_meta(FLOATING_AREA_META, weakref(area))
	content.set_anchors_preset(Control.PRESET_TOP_LEFT)
	content.hide()
	_place_floating_content.call_deferred(content, area, initial_position)
	return visual_root


func _create_backdrop_wrapper(target: Control, backdrop_style: StyleBox, backdrop_mouse_filter: int) -> Control:
	var wrapper := Control.new()
	wrapper.name = "WindowHost"
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_child(wrapper)
	wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := PanelContainer.new()
	backdrop.name = "Backdrop"
	backdrop.mouse_filter = backdrop_mouse_filter
	wrapper.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box: StyleBox = backdrop_style
	if box == null:
		var fallback := StyleBoxFlat.new()
		fallback.bg_color = Color(0, 0, 0, 0.55)
		box = fallback
	backdrop.add_theme_stylebox_override("panel", box.duplicate(true))
	return wrapper


func _place_floating_content(content: Control, area: Control, initial_position: Variant) -> void:
	if not is_instance_valid(content) or not content.is_inside_tree():
		return
	
	if not is_instance_valid(area) or not area.is_inside_tree():
		return
	
	content.reset_size()
	var desired: Vector2
	if initial_position is Vector2:
		desired = initial_position
	else:
		desired = (area.size - content.size) * 0.5
	var limits := Vector2(
		maxf(0.0, area.size.x - content.size.x),
		maxf(0.0, area.size.y - content.size.y)
	)
	content.position = Vector2(
		clampf(desired.x, 0.0, limits.x),
		clampf(desired.y, 0.0, limits.y)
	)
	content.show()
#endregion


#region Lifecycle
func _exit_tree() -> void:
	for id in _layers:
		var entry: Dictionary = _layers[id]
		if entry["managed"]:
			continue
		var mount := entry["root"] as Control
		if mount == null or not is_instance_valid(mount):
			continue
		if not mount.has_meta(ROOT_META):
			continue
		var reference: Variant = mount.get_meta(ROOT_META)
		if reference is WeakRef and reference.get_ref() == self:
			mount.remove_meta(ROOT_META)
	_layers.clear()


static func find_from(node: Node) -> UIRootHost:
	var current := node
	while current != null:
		if current is UIRootHost:
			return current as UIRootHost
		if current.has_meta(ROOT_META):
			var reference: Variant = current.get_meta(ROOT_META)
			if reference is WeakRef:
				var owner: Variant = reference.get_ref()
				if owner is UIRootHost and is_instance_valid(owner):
					return owner as UIRootHost
		current = current.get_parent()
	return null


func _error(message: String) -> bool:
	errors.append(message)
	return false
#endregion
