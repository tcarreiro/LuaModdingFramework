extends GutTest

var styles: UIStyleRegistry
var components: UIComponentRegistry


func before_each() -> void:
	styles = UIStyleRegistry.new()
	components = UIComponentRegistry.new()
	components.style_registry = styles


func _style(id: String, parent: String = "") -> UIStyleDefinition:
	var definition := UIStyleDefinition.new()
	definition.id = id
	definition.parent = parent
	return definition


func _base_button_style() -> UIStyleDefinition:
	var definition := _style("core:button-base")
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#304050")

	definition.styleboxes["normal"] = normal
	definition.layout = {
		"padding": 6,
		"stretch_x": "fill"
	}
	definition.colors["font_color"] = Color.WHITE
	definition.font_sizes["font_size"] = 16
	definition.mod_overrides = [
		"layout.padding",
		"layout.margin",
		"font_sizes.font_size"
	]
	return definition


func _register_button(style_id: String = "core:button-base") -> void:
	var button := Button.new()
	var scene := PackedScene.new()
	assert_eq(scene.pack(button), OK)
	button.free()

	var definition := UIComponentDefinition.from_scene(
		"core:button", scene, func(_control: Control, _values: Dictionary) -> void: pass,
		{
			"style": {
				"type": TYPE_STRING,
				"default": style_id,
				"mod_editable": true
			},
			"style_overrides": {
				"type": TYPE_DICTIONARY,
				"default": {},
				"mod_editable": true
			}
		}
	)
	assert_true(components.register_scene(definition))
	assert_true(components.finalize())


func test_style_inheritance() -> void:
	var base := _base_button_style()
	var derived := _style("core:button-primary", "core:button-base")

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color("#405A70")
	derived.styleboxes["hover"] = hover
	derived.layout["stretch_x"] = "expand_fill"

	assert_true(styles.register_style(base))
	assert_true(styles.register_style(derived))
	assert_true(styles.finalize())

	var result := styles.prepare_instance("core:button-primary", {}, true)

	assert_eq(result.layout["padding"], 6)
	assert_eq(result.layout["stretch_x"], "expand_fill")
	assert_eq(result.font_sizes["font_size"], 16)
	assert_true(result.styleboxes.has("normal"))
	assert_true(result.styleboxes.has("hover"))


func test_stylebox_copies_are_independent() -> void:
	assert_true(styles.register_style(_base_button_style()))
	assert_true(styles.finalize())

	var first := styles.prepare_instance("core:button-base", {}, true)
	var second := styles.prepare_instance("core:button-base", {}, true)

	var first_box := first.styleboxes["normal"] as StyleBoxFlat
	var second_box := second.styleboxes["normal"] as StyleBoxFlat

	assert_ne(first_box, second_box)

	first_box.bg_color = Color.RED

	assert_ne(first_box.bg_color, second_box.bg_color)


func test_allowed_mod_override() -> void:
	assert_true(styles.register_style(_base_button_style()))
	assert_true(styles.finalize())

	var result := styles.prepare_instance("core:button-base", {
		"layout": {"padding": 12},
		"font_sizes": {"font_size": 20}
	})

	assert_not_null(result)
	assert_eq(result.layout["padding"], 12)
	assert_eq(result.font_sizes["font_size"], 20)


func test_restricted_mod_override() -> void:
	assert_true(styles.register_style(_base_button_style()))
	assert_true(styles.finalize())

	var result := styles.prepare_instance("core:button-base", {
		"colors": {"font_color": Color.RED}
	})

	assert_null(result)
	assert_false(styles.errors.is_empty())


func test_style_registry_is_frozen() -> void:
	assert_true(styles.register_style(_base_button_style()))
	assert_true(styles.finalize())

	assert_false(styles.register_style(_style("core:another")))
	assert_false(styles.has_style("core:another"))


func test_cyclic_style_inheritance_is_rejected() -> void:
	assert_true(styles.register_style(_style("core:a", "core:b")))
	assert_true(styles.register_style(_style("core:b", "core:a")))
	assert_false(styles.finalize())


func test_component_receives_local_stylebox() -> void:
	assert_true(styles.register_style(_base_button_style()))
	assert_true(styles.finalize())
	_register_button()

	var first := components.instantiate_component("core:button")
	var second := components.instantiate_component("core:button")

	assert_not_null(first)
	assert_not_null(second)

	var first_button := first.root as Button
	var second_button := second.root as Button

	var first_box := first_button.get_theme_stylebox("normal")
	var second_box := second_button.get_theme_stylebox("normal")

	assert_ne(first_box, second_box)
	assert_eq(first_box.get_content_margin(SIDE_LEFT), 6.0)

	first.root.free()
	second.root.free()


func test_margin_creates_only_one_wrapper() -> void:
	var style := _base_button_style()
	style.layout["margin"] = Vector4(4, 6, 8, 10)
	style.layout["min_size"] = Vector2(90, 30)
	style.layout["stretch_x"] = "expand_fill"
	style.layout["stretch_y"] = "center"
	style.layout["stretch_ratio"] = 2.0

	assert_true(styles.register_style(style))
	assert_true(styles.finalize())
	_register_button()

	var instance := components.instantiate_component("core:button")

	assert_true(instance.root is MarginContainer)
	assert_true(instance.content_root is Button)
	assert_same(instance.root.get_child(0), instance.content_root)

	assert_eq(instance.root.size_flags_horizontal, Control.SIZE_EXPAND_FILL)
	assert_eq(instance.root.size_flags_vertical, Control.SIZE_SHRINK_CENTER)
	assert_eq(instance.root.size_flags_stretch_ratio, 2.0)
	assert_eq(instance.content_root.custom_minimum_size, Vector2(90, 30))
	assert_eq((instance.root as MarginContainer).get_theme_constant("margin_left"), 4)
	assert_eq((instance.root as MarginContainer).get_theme_constant("margin_top"), 6)

	instance.root.free()


func test_without_margin_does_not_create_wrapper() -> void:
	assert_true(styles.register_style(_base_button_style()))
	assert_true(styles.finalize())
	_register_button()

	var instance := components.instantiate_component("core:button")

	assert_same(instance.root, instance.content_root)
	assert_true(instance.root is Button)

	instance.root.free()


func test_cross_alignment_is_applied_to_direct_child() -> void:
	var style := _style("core:column")
	style.layout = {
		"display": "flex",
		"direction": "vertical",
		"cross_alignment": "center",
		"gap": 5
	}

	assert_true(styles.register_style(style))
	assert_true(styles.finalize())

	var column := VBoxContainer.new()
	var column_scene := PackedScene.new()
	assert_eq(column_scene.pack(column), OK)
	column.free()

	var label := Label.new()
	var label_scene := PackedScene.new()
	assert_eq(label_scene.pack(label), OK)
	label.free()

	var column_definition := UIComponentDefinition.from_scene(
		"core:column", column_scene,
		func(_control: Control, _values: Dictionary) -> void: pass,
		{
			"style": {
				"type": TYPE_STRING,
				"default": "core:column",
				"mod_editable": true
			}
		}
	)

	var label_definition := UIComponentDefinition.from_scene(
		"core:label", label_scene,
		func(_control: Control, _values: Dictionary) -> void: pass
	)

	assert_true(components.register_scene(column_definition))
	assert_true(components.register_scene(label_definition))

	var template := UIComponentDefinition.from_template(
		"demo:layout", "demo",
		{
			"component": "core:column",
			"children": [
				{"component": "core:label"}
			]
		}
	)

	assert_true(components.register_template(template))
	assert_true(components.finalize())

	var instance := components.instantiate_component("demo:layout")
	assert_not_null(instance)

	var child := instance.root.get_child(0) as Label

	assert_not_null(child)
	assert_eq(child.size_flags_horizontal, Control.SIZE_SHRINK_CENTER)

	instance.root.free()
