extends GutTest

var styles: UIStyleRegistry
var components: UIComponentRegistry
var premades: UIPremadeCatalog


func before_each() -> void:
	styles = UIStyleRegistry.new()
	components = UIComponentRegistry.new()
	components.style_registry = styles

	premades = UIPremadeCatalog.new()

	assert_true(
		premades.install(components, styles),
		str(premades.errors)
	)


func _finalize_registries() -> void:
	assert_true(styles.finalize(), str(styles.errors))
	assert_true(components.finalize(), str(components.errors))


func test_builtin_components_are_registered() -> void:
	assert_true(components.has_component("ui:label"))
	assert_true(components.has_component("ui:div"))
	assert_true(components.has_component("ui:button"))

	assert_true(styles.has_style("ui:label-default"))
	assert_true(styles.has_style("ui:div-default"))
	assert_true(styles.has_style("ui:button-default"))


func test_premades_do_not_have_fixed_minimum_size() -> void:
	_finalize_registries()
	for id in ["ui:label", "ui:div", "ui:button"]:
		var instance := components.instantiate_component(id)
		assert_not_null(instance)
		assert_eq(instance.content_root.custom_minimum_size, Vector2.ZERO)
		instance.clear_callbacks()
		instance.root.free()



func test_div_exposes_its_content_slot() -> void:
	_finalize_registries()

	var instance := components.instantiate_component("ui:div", {
		"direction": "horizontal"
	})

	assert_not_null(instance, str(components.errors))
	if instance == null:
		return

	var content := instance.get_slot() as BoxContainer

	assert_not_null(content)
	if content != null:
		assert_false(content.vertical)

	instance.clear_callbacks()
	instance.root.free()



func test_label_can_receive_hover() -> void:
	var style := UIStyleDefinition.new()
	style.id = "test:hover-label"
	style.layout = {
		"scale_mode": "visual_only",
		"pivot_ratio": Vector2(0.5, 0.5)
	}
	style.states = {
		"hover": {
			"scale": Vector2(1.1, 1.1)
		}
	}

	assert_true(styles.register_style(style))
	_finalize_registries()

	var instance := components.instantiate_component("ui:label", {
		"text": "Hover em Label",
		"style": "test:hover-label"
	})

	assert_not_null(instance)
	assert_eq(instance.content_root.mouse_filter, Control.MOUSE_FILTER_PASS)

	instance.transition.set_state("hover")

	assert_eq(instance.content_root.offset_transform_scale, Vector2(1.1, 1.1))

	instance.clear_callbacks()
	instance.root.free()


func test_div_can_change_background_on_hover() -> void:
	var style := UIStyleDefinition.new()
	style.id = "test:hover-div"
	style.visual = {
		"background_color": Color("#202B3A"),
		"border_radius": 6
	}
	style.states = {
		"hover": {
			"background_color": Color("#4B6481")
		}
	}

	assert_true(styles.register_style(style))
	_finalize_registries()

	var instance := components.instantiate_component("ui:div", {
		"style": "test:hover-div"
	})

	assert_not_null(instance)

	var panel := instance.content_root as PanelContainer

	instance.transition.set_state("hover")

	var box := panel.get_theme_stylebox("panel") as StyleBoxFlat

	assert_not_null(box)
	assert_eq(box.bg_color, Color("#4B6481"))

	instance.clear_callbacks()
	instance.root.free()


func test_button_has_native_pressed_event() -> void:
	_finalize_registries()

	var instance := components.instantiate_component("ui:button", {
		"label": "Confirmar"
	})

	assert_not_null(instance)

	var received: Array = []

	assert_true(instance.on_event(&"pressed", func(event: Dictionary):
		received.append(event["name"])
	))

	var button := instance.content_root as Button

	assert_eq(button.text, "Confirmar")

	button.pressed.emit()

	assert_eq(received, ["pressed"])

	instance.clear_callbacks()
	instance.root.free()


func test_button_accepts_native_theme_sounds() -> void:
	var hover_sound := AudioStreamWAV.new()

	var style := UIStyleDefinition.new()
	style.id = "test:button-sounds"
	style.sounds = {
		"hover_sound": hover_sound
	}

	assert_true(styles.register_style(style))
	_finalize_registries()

	var instance := components.instantiate_component("ui:button", {
		"style": "test:button-sounds"
	})

	assert_not_null(instance)

	var button := instance.content_root as Button

	assert_same(
		button.get_theme_sound(&"hover_sound"),
		hover_sound
	)

	instance.clear_callbacks()
	instance.root.free()


func test_stylebox_is_generated_from_visual_properties() -> void:
	var compiler := UIStyleBoxCompiler.new()

	var result := compiler.compile({
		"background_color": Color("#223344"),
		"border_color": Color("#778899"),
		"border_width": 2,
		"border_radius": 10,
		"padding": 12
	})

	assert_not_null(result)
	assert_true(result is StyleBoxFlat)

	var box := result as StyleBoxFlat

	assert_eq(box.bg_color, Color("#223344"))
	assert_eq(box.border_width_left, 2)
	assert_eq(box.corner_radius_top_left, 10)
	assert_eq(box.content_margin_left, 12.0)
