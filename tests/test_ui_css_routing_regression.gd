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


func _finish() -> void:
	assert_true(styles.finalize(), str(styles.errors))
	assert_true(components.finalize(), str(components.errors))


func _create(id: String, values: Dictionary = {}) -> UIComponentInstance:
	var instance := components.instantiate_component(id, values, true)
	assert_not_null(instance, str(components.errors))
	return instance


func _release(instance: UIComponentInstance) -> void:
	if instance != null and is_instance_valid(instance.root):
		instance.clear_callbacks()
		instance.root.free()


func test_builtin_button_visual_hover_does_not_send_scale_to_stylebox() -> void:
	_finish()
	var button := _create(UIBuiltinIds.BUTTON)
	if button == null:
		return
	assert_eq(button.content_root.scale, Vector2.ONE)
	assert_eq(button.content_root.offset_transform_scale, Vector2.ONE)
	assert_true(button.transition != null)
	button.transition.set_state("hover")
	assert_eq(button.content_root.offset_transform_scale, Vector2.ONE)
	_release(button)


func test_native_direction_does_not_turn_separator_or_scroll_into_flex() -> void:
	_finish()
	var separator := _create(UIBuiltinIds.SEPARATOR)
	var scroll := _create(UIBuiltinIds.SCROLL)
	assert_not_null(separator)
	assert_not_null(scroll)
	_release(separator)
	_release(scroll)


func test_named_css_direction_is_applied_to_scroll_content() -> void:
	var style := UIStyleDefinition.new()
	style.id = "test:horizontal-scroll"
	style.layout = {"direction": "horizontal", "gap": 9}
	assert_true(styles.register_style(style))
	_finish()
	var instance := _create(UIBuiltinIds.SCROLL, {"style": style.id})
	if instance == null:
		return
	var box := (instance.content_root as UIComponentScroll).get_content_box()
	assert_false(box.vertical)
	assert_eq(box.get_theme_constant(&"separation"), 9)
	_release(instance)


func test_explicit_native_direction_overrides_the_named_style() -> void:
	var style := UIStyleDefinition.new()
	style.id = "test:horizontal-scroll"
	style.layout = {"direction": "horizontal"}
	assert_true(styles.register_style(style))
	_finish()
	var instance := _create(UIBuiltinIds.SCROLL, {"style": style.id, "direction": "vertical"})
	if instance == null:
		return
	assert_true((instance.content_root as UIComponentScroll).get_content_box().vertical)
	_release(instance)


func test_modal_content_box_receives_css_gap() -> void:
	var style := UIStyleDefinition.new()
	style.id = "test:modal-gap"
	style.layout = {"gap": 14, "alignment": "center"}
	assert_true(styles.register_style(style))
	_finish()
	var instance := _create(UIBuiltinIds.MODAL, {"style": style.id})
	if instance == null:
		return
	var box := (instance.content_root as UIComponentModal).get_content_box()
	assert_eq(box.get_theme_constant(&"separation"), 14)
	assert_eq(box.alignment, BoxContainer.ALIGNMENT_CENTER)
	_release(instance)


func test_native_button_padding_longhand_preserves_inherited_sides() -> void:
	_finish()
	var instance := _create(UIBuiltinIds.BUTTON, {"padding_right": 24})
	if instance == null:
		return
	var box := (instance.content_root as Button).get_theme_stylebox(&"normal")
	assert_eq(box.get_content_margin(SIDE_LEFT), 10.0)
	assert_eq(box.get_content_margin(SIDE_TOP), 10.0)
	assert_eq(box.get_content_margin(SIDE_RIGHT), 24.0)
	assert_eq(box.get_content_margin(SIDE_BOTTOM), 10.0)
	_release(instance)


func test_inline_label_background_margin_and_padding() -> void:
	_finish()
	var instance := _create(UIBuiltinIds.LABEL, {
		"text": "Teste",
		"background_color": "#263550",
		"padding": 10,
		"padding_right": 24,
		"margin_top": 5,
		"border_radius": 8
	})
	if instance == null:
		return
	assert_true(instance.root is MarginContainer)
	var panel := instance.content_root.get_parent() as PanelContainer
	assert_not_null(panel)
	if panel != null:
		var box := panel.get_theme_stylebox(&"panel") as StyleBoxFlat
		assert_eq(box.bg_color, Color("#263550"))
		assert_eq(box.get_content_margin(SIDE_LEFT), 10.0)
		assert_eq(box.get_content_margin(SIDE_RIGHT), 24.0)
	_release(instance)


func test_native_line_edit_uses_its_own_background_theme_slot() -> void:
	_finish()
	var instance := _create(UIBuiltinIds.TEXT_INPUT, {"background_color": "#112233", "padding_left": 14})
	if instance == null:
		return
	assert_same(instance.root, instance.content_root)
	var box := (instance.content_root as LineEdit).get_theme_stylebox(&"normal") as StyleBoxFlat
	assert_not_null(box)
	if box != null:
		assert_eq(box.bg_color, Color("#112233"))
		assert_eq(box.get_content_margin(SIDE_LEFT), 14.0)
	_release(instance)


func test_root_scale_and_opacity_are_style_properties() -> void:
	_finish()
	var instance := _create(UIBuiltinIds.LABEL, {"opacity": 0.7, "scale": {"x": 1.04, "y": 1.04}})
	if instance == null:
		return
	assert_almost_eq(instance.content_root.modulate.a, 0.7, 0.00001)
	assert_eq(instance.content_root.scale, Vector2(1.04, 1.04))
	_release(instance)


func test_visual_state_scale_and_font_color_are_not_stylebox_properties() -> void:
	var style := UIStyleDefinition.new()
	style.id = "test:states"
	style.visual = {"background_color": Color("#112233")}
	style.states = {"hover": {
		"background_color": Color("#334455"),
		"font_color": Color("#FFFFFF"),
		"scale": Vector2(1.05, 1.05),
		"opacity": 0.9
	}}
	assert_true(styles.register_style(style))
	_finish()
	var instance := _create(UIBuiltinIds.BUTTON, {"style": style.id})
	if instance == null:
		return
	instance.transition.set_state("hover")
	assert_eq(instance.content_root.scale, Vector2(1.05, 1.05))
	_release(instance)


func test_reject_invalid_visual_dimensions_early() -> void:
	var bad := UIStyleDefinition.new()
	bad.id = "test:invalid-width"
	bad.visual = {"border_width": -10}
	assert_false(styles.register_style(bad))
	assert_false(styles.errors.is_empty())


func test_reject_unsupported_layout_handler_explicitly() -> void:
	_finish()
	var instance := components.instantiate_component(UIBuiltinIds.LABEL, {"direction": "horizontal"}, true)
	assert_null(instance)
	assert_false(components.errors.is_empty())


func test_native_style_override_not_discarded_by_inline_visual() -> void:
	_finish()
	var box := StyleBoxFlat.new()
	box.bg_color = Color.YELLOW
	var prepared := styles.prepare_inline(UIBuiltinIds.STYLE_BUTTON, {
		"background_color": "#123456"
	}, true, {"styleboxes": {"normal": box}})
	assert_not_null(prepared)
	if prepared != null:
		assert_eq((prepared.styleboxes["normal"] as StyleBoxFlat).bg_color, Color.YELLOW)


func test_consumer_confirmation_modal_instantiates_with_real_lua_pages() -> void:
	var demo := load("res://example/consumer/consumer_catalog.gd").new() as ConsumerCatalog
	assert_true(demo.initialize(), str(demo.errors))
	if not demo.errors.is_empty():
		return
	var instance := demo.components.instantiate_component("core:confirm-modal", {
		"title": "Sair?", "description": "Confirma a saída?"
	}, true)
	assert_not_null(instance, str(demo.components.errors))
	_release(instance)
