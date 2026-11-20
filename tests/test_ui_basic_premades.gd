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


func _finalize() -> void:
	assert_true(styles.finalize(), str(styles.errors))
	assert_true(components.finalize(), str(components.errors))


func _release(instance: UIComponentInstance) -> void:
	if instance == null:
		return

	instance.clear_callbacks()

	if instance.root != null and is_instance_valid(instance.root):
		instance.root.free()


func test_five_components_are_registered() -> void:
	for id in [
		"ui:checkbox",
		"ui:dropdown",
		"ui:grid",
		"ui:stack",
		"ui:scroll"
	]:
		assert_true(components.has_component(id), id)


func test_checkbox_uses_native_toggle_behavior() -> void:
	_finalize()

	var instance := components.instantiate_component("ui:checkbox", {
		"label": "Música",
		"checked": true
	})

	assert_not_null(instance)
	if instance == null:
		return

	var checkbox := instance.content_root as CheckBox

	assert_eq(checkbox.text, "Música")
	assert_true(checkbox.button_pressed)

	var received: Array = []

	assert_true(instance.on_event(&"toggled", func(event: Dictionary):
		received.append(event["arguments"][0])
	))

	checkbox.toggled.emit(false)

	assert_eq(received, [false])

	assert_true(instance.update({"checked": false}))
	assert_false(checkbox.button_pressed)

	_release(instance)


func test_dropdown_populates_options_and_changes_selection() -> void:
	_finalize()

	var instance := components.instantiate_component("ui:dropdown", {
		"options": ["Baixo", "Médio", "Alto"],
		"selected": 1
	})

	assert_not_null(instance)
	if instance == null:
		return

	var dropdown := instance.content_root as OptionButton

	assert_eq(dropdown.item_count, 3)
	assert_eq(dropdown.get_item_text(0), "Baixo")
	assert_eq(dropdown.get_item_text(1), "Médio")
	assert_eq(dropdown.selected, 1)

	assert_true(instance.update({"selected": 2}))
	assert_eq(dropdown.selected, 2)

	_release(instance)


func test_dropdown_rejects_invalid_option_types() -> void:
	_finalize()

	var instance := components.instantiate_component("ui:dropdown", {
		"options": ["Baixo", 15]
	})

	assert_null(instance)
	assert_false(components.errors.is_empty())


func test_grid_exposes_root_as_content_slot() -> void:
	_finalize()

	var instance := components.instantiate_component("ui:grid", {
		"columns": 7
	})

	assert_not_null(instance)
	if instance == null:
		return

	var grid := instance.content_root as GridContainer

	assert_eq(grid.columns, 7)
	assert_same(instance.get_slot(), grid)
	assert_eq(grid.custom_minimum_size, Vector2.ZERO)

	_release(instance)


func test_stack_layers_are_not_sequential_box_children() -> void:
	_finalize()

	var instance := components.instantiate_component("ui:stack")
	assert_not_null(instance)
	if instance == null:
		return

	assert_true(instance.content_root is UIComponentStack)
	assert_true(instance.get_slot() is UIStackLayerLayout)
	assert_false(instance.content_root is BoxContainer)
	_release(instance)


func test_scroll_exposes_internal_content() -> void:
	_finalize()

	var instance := components.instantiate_component("ui:scroll", {
		"horizontal_scroll": "disabled",
		"vertical_scroll": "auto"
	})

	assert_not_null(instance)
	if instance == null:
		return

	var scroll := instance.content_root as UIComponentScroll
	var content := instance.get_slot() as BoxContainer

	assert_not_null(scroll)
	assert_not_null(content)
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO)
	assert_true(scroll.clip_contents)

	_release(instance)


func test_scroll_padding_is_applied_inside_clipping() -> void:
	var style := UIStyleDefinition.new()
	style.id = "test:scroll-style"
	style.layout = {
		"padding": 12,
		"gap": 6
	}

	assert_true(styles.register_style(style))
	_finalize()

	var instance := components.instantiate_component("ui:scroll", {
		"style": "test:scroll-style"
	})

	assert_not_null(instance)
	if instance == null:
		return

	var scroll := instance.content_root as UIComponentScroll
	var padding := scroll.get_node("ContentPadding") as MarginContainer
	var content := instance.get_slot() as BoxContainer

	assert_eq(padding.get_theme_constant("margin_left"), 12)
	assert_eq(padding.get_theme_constant("margin_top"), 12)
	assert_eq(content.get_theme_constant("separation"), 6)

	_release(instance)


func test_grid_gap_is_controlled_by_style() -> void:
	var style := UIStyleDefinition.new()
	style.id = "test:grid-style"
	style.layout = {
		"gap": 8
	}

	assert_true(styles.register_style(style))
	_finalize()

	var instance := components.instantiate_component("ui:grid", {
		"columns": 4,
		"style": "test:grid-style"
	})

	assert_not_null(instance)
	if instance == null:
		return

	var grid := instance.content_root as GridContainer

	assert_eq(grid.get_theme_constant("h_separation"), 8)
	assert_eq(grid.get_theme_constant("v_separation"), 8)

	_release(instance)


func test_lua_template_can_declare_dropdown_options() -> void:
	var state := ContentState.new(
		ContentTypeRegistry.new(),
		components
	)

	state.start()

	var success := state.execute("""
		assert(UI.define_component("demo:choices", {
			tree = {
				component = "ui:dropdown",
				props = {
					options = {"Baixo", "Médio", "Alto"},
					selected = 1
				}
			}
		}))
	""", "demo")

	assert_true(success, str(state.get_errors()))
	state.close()

	_finalize()

	var instance := components.instantiate_component("demo:choices")

	assert_not_null(instance)

	if instance != null:
		var dropdown := instance.root as OptionButton

		assert_eq(dropdown.item_count, 3)
		assert_eq(dropdown.selected, 1)

		_release(instance)
