extends GutTest

var styles: UIStyleRegistry
var components: UIComponentRegistry
var catalog: UIPremadeCatalog


func before_each() -> void:
	styles = UIStyleRegistry.new()
	components = UIComponentRegistry.new()
	components.style_registry = styles
	catalog = UIPremadeCatalog.new()
	assert_true(catalog.install(components, styles), str(catalog.errors))
	assert_true(styles.finalize(), str(styles.errors))
	assert_true(components.finalize(), str(components.errors))


func _make(id: String, props: Dictionary = {}) -> UIComponentInstance:
	var instance := components.instantiate_component(id, props)
	assert_not_null(instance, str(components.errors))
	return instance


func _free_component(instance: UIComponentInstance) -> void:
	if instance != null and is_instance_valid(instance.root):
		instance.root.free()


func test_label_without_visual_style_has_no_extra_wrapper() -> void:
	var instance := _make(UIBuiltinIds.LABEL, {"text": "Simple"})
	if instance == null:
		return
	assert_same(instance.root, instance.content_root)
	_free_component(instance)


func test_label_inline_background_and_padding_create_visual_panel() -> void:
	var instance := _make(UIBuiltinIds.LABEL, {
		"text": "CSS inline",
		"padding": 12,
		"padding_right": 30,
		"background_color": "#112233",
		"border_radius": 5,
		"border_top_left_radius": 14
	})
	if instance == null:
		return
	assert_true(instance.root is PanelContainer)
	assert_true(instance.content_root is Label)
	var box := (instance.root as PanelContainer).get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_not_null(box)
	if box != null:
		assert_eq(box.bg_color, Color("#112233"))
		assert_eq(box.get_content_margin(SIDE_LEFT), 12.0)
		assert_eq(box.get_content_margin(SIDE_RIGHT), 30.0)
		assert_eq(box.corner_radius_top_left, 14)
		assert_eq(box.corner_radius_bottom_right, 5)
	_free_component(instance)


func test_label_padding_without_paint_is_transparent() -> void:
	var instance := _make(UIBuiltinIds.LABEL, {"padding_top": 8})
	if instance == null:
		return
	assert_true(instance.root is PanelContainer)
	var box := (instance.root as PanelContainer).get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_not_null(box)
	if box != null:
		assert_eq(box.bg_color.a, 0.0)
		assert_eq(box.get_content_margin(SIDE_TOP), 8.0)
	_free_component(instance)


func test_inline_props_are_listed_in_component_schema() -> void:
	var recognized := components.describe_recognized_properties(UIBuiltinIds.LABEL)
	for name in ["background_color", "padding", "padding_left", "padding_right", "margin_top", "corner_radius", "border_bottom_right_radius"]:
		assert_true(recognized.has(name), name)


func test_inline_invalid_property_rejected() -> void:
	var instance := components.instantiate_component(UIBuiltinIds.LABEL, {"padding_right": "banana"})
	assert_null(instance)
	if instance != null:
		_free_component(instance)


func test_drag_preview_layer_uses_consumer_customizer() -> void:
	var layer := UIDragPreviewLayer.new()
	var source := Control.new()
	add_child(layer)
	add_child(source)
	var observed: Array = []
	layer.set_preview_customizer(func(from: Control, preview: Control, payload: Dictionary) -> Variant:
		observed.append(payload.get("id"))
		preview.modulate = Color.RED
		preview.position = Vector2(-15, -15)
		return null
	)
	var preview := Control.new()
	assert_true(layer.begin_drag(source, preview, {"id": "bronze"}))
	assert_eq(observed, ["bronze"])
	assert_eq(preview.modulate, Color.RED)
	assert_true(layer.has_active_preview())
	layer.end_drag(source)
	layer.free()
	source.free()
