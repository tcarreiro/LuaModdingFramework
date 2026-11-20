extends GutTest

var styles: UIStyleRegistry
var components: UIComponentRegistry


func before_each() -> void:
	styles = UIStyleRegistry.new()
	components = UIComponentRegistry.new()
	components.style_registry = styles


func _install_from_local_catalog() -> void:
	var catalog := UIPremadeCatalog.new()
	assert_true(catalog.install(components, styles), str(catalog.errors))


func _release(instance: UIComponentInstance) -> void:
	if instance == null:
		return
	instance.clear_callbacks()
	if is_instance_valid(instance.root):
		instance.root.free()


func test_premade_applier_survives_catalog_scope() -> void:
	_install_from_local_catalog()
	assert_true(styles.finalize(), str(styles.errors))
	assert_true(components.finalize(), str(components.errors))
	var instance := components.instantiate_component(UIBuiltinIds.TEXT_AREA, {"text": "Antes"})
	assert_not_null(instance, str(components.errors))
	if instance == null:
		return
	assert_eq((instance.content_root as UIComponentTextArea).text, "Antes")
	assert_true(instance.update({"text": "Depois"}), str(components.errors))
	assert_eq((instance.content_root as UIComponentTextArea).text, "Depois")
	_release(instance)


func test_button_background_transition_preserves_padding_on_every_state() -> void:
	_install_from_local_catalog()
	var custom := UIStyleDefinition.new()
	custom.id = "test:hover-padding"
	custom.layout = {"padding": Vector4(11, 18, 23, 18)}
	custom.visual = {"background_color": Color("#273751"), "border_radius": 8}
	custom.states = {
		"hover": {"background_color": Color("#364C6C")},
		"pressed": {"background_color": Color("#1F2C44")}
	}
	custom.transition = {"properties": ["background_color"], "duration": 0.16}
	assert_true(styles.register_style(custom), str(styles.errors))
	assert_true(styles.finalize(), str(styles.errors))
	assert_true(components.finalize(), str(components.errors))
	var instance := components.instantiate_component(UIBuiltinIds.BUTTON, {"style": custom.id})
	assert_not_null(instance, str(components.errors))
	if instance == null:
		return
	var button := instance.content_root as Button
	for state in ["normal", "hover", "pressed"]:
		var box := button.get_theme_stylebox(StringName(state))
		assert_eq(box.get_content_margin(SIDE_LEFT), 11.0, state)
		assert_eq(box.get_content_margin(SIDE_TOP), 18.0, state)
		assert_eq(box.get_content_margin(SIDE_RIGHT), 23.0, state)
		assert_eq(box.get_content_margin(SIDE_BOTTOM), 18.0, state)
	_release(instance)


func test_builtin_button_background_transition_retains_its_original_padding() -> void:
	_install_from_local_catalog()
	assert_true(styles.finalize(), str(styles.errors))
	assert_true(components.finalize(), str(components.errors))
	var instance := components.instantiate_component(UIBuiltinIds.BUTTON)
	assert_not_null(instance, str(components.errors))
	if instance == null:
		return
	var button := instance.content_root as Button
	for state in ["normal", "hover", "pressed"]:
		var box := button.get_theme_stylebox(StringName(state))
		assert_eq(box.get_content_margin(SIDE_TOP), 10.0, state)
		assert_eq(box.get_content_margin(SIDE_BOTTOM), 10.0, state)
	_release(instance)


func test_hover_exit_does_not_temporarily_change_button_minimum_height() -> void:
	_install_from_local_catalog()
	assert_true(styles.finalize(), str(styles.errors))
	assert_true(components.finalize(), str(components.errors))
	var instance := components.instantiate_component(UIBuiltinIds.BUTTON, {"label": "Continue"})
	assert_not_null(instance, str(components.errors))
	if instance == null:
		return
	var host := Control.new()
	add_child(host)
	host.add_child(instance.root)
	var button := instance.content_root as Button
	var expected_height := button.get_combined_minimum_size().y
	instance.transition.set_state("hover")
	assert_almost_eq(button.get_combined_minimum_size().y, expected_height, 0.01)
	instance.transition.set_state("normal")
	assert_almost_eq(button.get_combined_minimum_size().y, expected_height, 0.01)
	_release(instance)
	host.free()
