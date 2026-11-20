class_name UIComponentModal extends PanelContainer

signal close_requested

var _draggable := true
var _dragging := false

var _drag_root: Control
var _drag_area: Control
var _mouse_start := Vector2.ZERO
var _window_start := Vector2.ZERO

@onready var _header: HBoxContainer = $Layout/Header
@onready var _title: Label = $Layout/Header/Title
@onready var _close_button: Button = $Layout/Header/Close


func _ready() -> void:
	_header.gui_input.connect(_on_header_input)
	_close_button.pressed.connect(_on_close_pressed)


func get_premade_definition() -> UIComponentDefinition:
	var definition := UIPremadeContract.create_definition(
		UIBuiltinIds.MODAL,
		{
			"title": UIPremadeContract.property(TYPE_STRING, ""),
			"draggable": UIPremadeContract.property(TYPE_BOOL, true),
			"closeable": UIPremadeContract.property(TYPE_BOOL, true)
		},
		UIBuiltinIds.STYLE_MODAL,
		[
			UIKeys.EVENT_CLOSE_REQUESTED,
			UIKeys.EVENT_MOUSE_ENTERED,
			UIKeys.EVENT_MOUSE_EXITED
		],
		{
			"default": NodePath("Layout/Content")
		}
	)
	definition.presentation = "overlay"
	definition.drag_target = NodePath(".")
	definition.drag_handle = NodePath("Layout/Header")
	return definition


func apply_premade_properties(values: Dictionary) -> void:
	configure(values)
	UIPremadeContract.apply_common(self, values)


func get_premade_styles() -> Array[UIStyleDefinition]:
	var style := UIStyleDefinition.new()
	style.id = UIBuiltinIds.STYLE_MODAL
	style.visual = {
		UIKeys.PROP_BACKGROUND_COLOR: Color("#182132"),
		UIKeys.PROP_BORDER_COLOR: Color("#52647C"),
		UIKeys.PROP_BORDER_WIDTH: 1,
		UIKeys.PROP_BORDER_RADIUS: 8,
		UIKeys.PROP_PADDING: 12
	}
	return [style]


func get_content_box() -> BoxContainer:
	return get_node("Layout/Content") as BoxContainer


func configure(values: Dictionary) -> void:
	if values.has("title"):
		$Layout/Header/Title.text = values["title"]
	if values.has("closeable"):
		$Layout/Header/Close.visible = values["closeable"]
	if values.has("draggable"):
		_draggable = values["draggable"]


func _on_close_pressed() -> void:
	close_requested.emit()


func _on_header_input(event: InputEvent) -> void:
	if not _draggable:
		return
	if not event is InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var floating := _find_floating_root()
	if floating == null:
		return
	var area_ref: Variant = floating.get_meta(
		UIRootHost.FLOATING_AREA_META, null
	)
	
	if not area_ref is WeakRef:
		return
	
	var area := area_ref.get_ref() as Control
	if area == null or not is_instance_valid(area):
		return
	
	_drag_root = floating
	_drag_area = area
	_mouse_start = area.get_local_mouse_position()
	_window_start = floating.position
	_dragging = true
	_bring_to_front(floating)
	_header.accept_event()


func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_stop_dragging()
		return
	
	if not event is InputEventMouseMotion:
		return
	
	if not is_instance_valid(_drag_root) or not is_instance_valid(_drag_area):
		_stop_dragging()
		return
	
	var delta := _drag_area.get_local_mouse_position() - _mouse_start
	var desired := _window_start + delta
	var limits := Vector2(
		maxf(0.0, _drag_area.size.x - _drag_root.size.x),
		maxf(0.0, _drag_area.size.y - _drag_root.size.y)
	)
	_drag_root.position = Vector2(
		clampf(desired.x, 0.0, limits.x),
		clampf(desired.y, 0.0, limits.y)
	)


func _find_floating_root() -> Control:
	var candidate: Control = self
	while candidate != null:
		if candidate.has_meta(UIRootHost.FLOATING_AREA_META):
			return candidate
		var parent := candidate.get_parent() as Control
		if not parent is MarginContainer:
			break
		candidate = parent
	return null


func _bring_to_front(window: Control) -> void:
	var parent := window.get_parent()
	if parent is Control and parent.name == "WindowHost":
		parent.move_to_front()
	else:
		window.move_to_front()


func _stop_dragging() -> void:
	_dragging = false
	_drag_root = null
	_drag_area = null


func _exit_tree() -> void:
	_stop_dragging()
