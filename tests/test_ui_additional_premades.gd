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
	if instance == null:
		return
	instance.clear_callbacks()
	if instance.root != null and is_instance_valid(instance.root):
		instance.root.free()


func test_seven_premades_are_discovered_without_catalog_registration() -> void:
	for id in [UIBuiltinIds.SLIDER, UIBuiltinIds.PROGRESS_BAR, UIBuiltinIds.TOGGLE, UIBuiltinIds.TABS, UIBuiltinIds.TOOLTIP, UIBuiltinIds.SEPARATOR, UIBuiltinIds.RADIO_BUTTON]:
		assert_true(components.has_component(id), id)


func test_slider_values_and_signal() -> void:
	var instance := _make(UIBuiltinIds.SLIDER, {
		"min": 0.0, "max": 20.0, "value": 10.0, "step": 2.0
	})
	if instance == null:
		return
	var control := instance.content_root as UIComponentSlider
	assert_eq(control.value, 10.0)
	assert_eq(control.step, 2.0)
	var received: Array = []
	assert_true(instance.on_event(UIKeys.EVENT_VALUE_CHANGED, func(event: Dictionary) -> void:
		received.append(event["arguments"][0])
	))
	control.value_changed.emit(12.0)
	assert_eq(received, [12.0])
	assert_true(instance.update({"value": 16.0}))
	assert_eq(control.value, 16.0)
	_release(instance)


func test_progress_bar_supports_updates_and_indeterminate() -> void:
	var instance := _make(UIBuiltinIds.PROGRESS_BAR, {
		"min": 0.0, "max": 200.0, "value": 25.0, "show_percentage": false
	})
	if instance == null:
		return
	var control := instance.content_root as UIComponentProgressBar
	assert_eq(control.value, 25.0)
	assert_false(control.show_percentage)
	assert_true(instance.update({"value": 100.0, "indeterminate": true}))
	assert_eq(control.value, 100.0)
	assert_true(control.indeterminate)
	_release(instance)


func test_toggle_uses_native_toggled_event() -> void:
	var instance := _make(UIBuiltinIds.TOGGLE, {"label": "Ativo", "checked": true})
	if instance == null:
		return
	var control := instance.content_root as UIComponentToggle
	assert_eq(control.text, "Ativo")
	assert_true(control.button_pressed)
	var received: Array = []
	assert_true(instance.on_event(UIKeys.EVENT_TOGGLED, func(event: Dictionary) -> void:
		received.append(event["arguments"][0])
	))
	control.toggled.emit(false)
	assert_eq(received, [false])
	_release(instance)


func test_separator_can_switch_direction() -> void:
	var instance := _make(UIBuiltinIds.SEPARATOR, {
		"direction": "horizontal", "thickness": 3.0, "color": Color.RED
	})
	if instance == null:
		return
	var control := instance.content_root as UIComponentSeparator
	assert_eq(control.custom_minimum_size, Vector2(0.0, 3.0))
	assert_eq(control.color, Color.RED)
	assert_true(instance.update({"direction": "vertical", "thickness": 4.0}))
	assert_eq(control.custom_minimum_size, Vector2(4.0, 0.0))
	_release(instance)


func test_tabs_expose_slot_and_select_added_children() -> void:
	var instance := _make(UIBuiltinIds.TABS, {"tabs": ["One", "Two"], "selected_tab": 1})
	if instance == null:
		return
	var control := instance.content_root as UIComponentTabs
	assert_same(instance.get_slot(), control)
	var first := Control.new()
	first.name = "First"
	control.add_child(first)
	var second := Control.new()
	second.name = "Second"
	control.add_child(second)
	assert_eq(control.get_tab_count(), 2)
	assert_true(instance.update({"selected_tab": 0}))
	assert_eq(control.current_tab, 0)
	_release(instance)


func test_tooltip_applies_text_to_nested_child() -> void:
	var instance := _make(UIBuiltinIds.TOOLTIP, {"text": "Item tooltip"})
	if instance == null:
		return
	var control := instance.content_root as UIComponentTooltip
	assert_eq(control.tooltip_text, "Item tooltip")
	var content := instance.get_slot()
	assert_not_null(content)
	assert_eq(content.tooltip_text, "Item tooltip")
	_release(instance)


func test_radio_buttons_share_group_only_with_siblings() -> void:
	var first := _make(UIBuiltinIds.RADIO_BUTTON, {"group": "quality", "label": "Low"})
	var second := _make(UIBuiltinIds.RADIO_BUTTON, {"group": "quality", "label": "High"})
	if first == null or second == null:
		return
	var parent := HBoxContainer.new()
	add_child_autofree(parent)
	parent.add_child(first.root)
	parent.add_child(second.root)
	var a := first.content_root as UIComponentRadioButton
	var b := second.content_root as UIComponentRadioButton
	assert_same(a.button_group, b.button_group)
	b.button_pressed = true
	assert_true(b.button_pressed)
	assert_false(a.button_pressed)
	first.clear_callbacks()
	second.clear_callbacks()
