extends GutTest

var styles: UIStyleRegistry
var components: UIComponentRegistry
var premades: UIPremadeCatalog


func before_each() -> void:
	styles = UIStyleRegistry.new()
	components = UIComponentRegistry.new()
	components.style_registry = styles
	premades = UIPremadeCatalog.new()
	assert_true(premades.install(components, styles), str(premades.errors))
	assert_true(styles.finalize(), str(styles.errors))
	assert_true(components.finalize(), str(components.errors))


func _make(id: String, properties: Dictionary = {}) -> UIComponentInstance:
	var instance := components.instantiate_component(id, properties)
	assert_not_null(instance, str(components.errors))
	return instance


func _release(instance: UIComponentInstance) -> void:
	if instance != null:
		instance.clear_callbacks()
		if is_instance_valid(instance.root):
			instance.root.free()


func test_six_native_components_discovered() -> void:
	for id in [UIBuiltinIds.LIST, UIBuiltinIds.DRAG_CONTAINER, UIBuiltinIds.CONTEXT_MENU, UIBuiltinIds.COLOR_PICKER, UIBuiltinIds.SPIN_BOX, UIBuiltinIds.TREE]:
		assert_true(components.has_component(id), id)


func test_list() -> void:
	var instance := _make(UIBuiltinIds.LIST, {"options": ["A", "B", "C"], "selected": 1})
	if instance == null:
		return
	var control := instance.content_root as UIComponentList
	assert_eq(control.item_count, 3)
	assert_eq(Array(control.get_selected_items()), [1])
	assert_true(instance.update({"options": ["D"]}))
	assert_eq(control.item_count, 1)
	_release(instance)


func test_drag_container_exposes_payload() -> void:
	var instance := _make(UIBuiltinIds.DRAG_CONTAINER, {"payload": {"id": "test"}})
	if instance == null:
		return
	var host := UIRootHost.new()
	add_child(host)
	host.screen_root.add_child(instance.root)
	var control := instance.content_root as UIComponentDragContainer
	var payload: Variant = control._get_drag_data(Vector2.ZERO)
	assert_eq(payload["payload"], {"id": "test"})
	assert_true(control._can_drop_data(Vector2.ZERO, payload))
	_release(instance)
	host.free()


func test_context_menu_options_and_event() -> void:
	var instance := _make(UIBuiltinIds.CONTEXT_MENU, {"options": ["Edit", "Delete"], "close_on_select": false})
	if instance == null:
		return
	var control := instance.content_root as UIComponentContextMenu
	assert_eq(control.get_node("Content").get_child_count(), 2)
	var received: Array = []
	instance.on_event(&"item_selected", func(event: Dictionary) -> void:
		received.append(event["arguments"][0])
	)
	control._on_selected(1)
	assert_eq(received, [1])
	_release(instance)


func test_color_picker() -> void:
	var instance := _make(UIBuiltinIds.COLOR_PICKER, {"color": Color.RED})
	if instance == null:
		return
	assert_eq((instance.content_root as UIComponentColorPicker).color, Color.RED)
	_release(instance)


func test_spin_box() -> void:
	var instance := _make(UIBuiltinIds.SPIN_BOX, {"min": 0.0, "max": 20.0, "value": 10.0, "step": 2.0})
	if instance == null:
		return
	assert_eq((instance.content_root as UIComponentSpinBox).value, 10.0)
	_release(instance)


func test_tree_nested_structure() -> void:
	var instance := _make(UIBuiltinIds.TREE, {"items": [{"label": "Parent", "children": ["Child"]}]})
	if instance == null:
		return
	var root := (instance.content_root as UIComponentTree).get_root()
	assert_not_null(root)
	assert_eq(root.get_first_child().get_text(0), "Parent")
	assert_eq(root.get_first_child().get_first_child().get_text(0), "Child")
	_release(instance)


func test_inline_components_fit_content_by_default() -> void:
	for id in [UIBuiltinIds.BUTTON, UIBuiltinIds.COLOR_PICKER, UIBuiltinIds.DRAG_CONTAINER, UIBuiltinIds.CONTEXT_MENU, UIBuiltinIds.SPIN_BOX]:
		var instance := _make(id)
		if instance == null:
			continue
		assert_eq(instance.root.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN, id)
		assert_eq(instance.root.size_flags_vertical, Control.SIZE_SHRINK_BEGIN, id)
		_release(instance)


func test_context_menu_anchor_properties() -> void:
	var instance := _make(UIBuiltinIds.CONTEXT_MENU, {"placement": "right", "alignment": "end", "offset": Vector2(12, 3), "flip": false})
	if instance == null:
		return
	var menu := instance.content_root as UIComponentContextMenu
	assert_eq(menu._placement, "right")
	assert_eq(menu._alignment, "end")
	assert_eq(menu._offset, Vector2(12, 3))
	assert_false(menu._flip)
	_release(instance)
