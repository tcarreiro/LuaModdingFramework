extends GutTest

var styles: UIStyleRegistry
var components: UIComponentRegistry

func before_each() -> void:
	styles = UIStyleRegistry.new()
	components = UIComponentRegistry.new()
	components.style_registry = styles


func _box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	return box


func _animated_style() -> UIStyleDefinition:
	var style := UIStyleDefinition.new()
	style.id = "core:animated-button"

	style.styleboxes = {
		"normal": _box(Color("#304050")),
		"hover": _box(Color("#6080A0")),
		"pressed": _box(Color("#203040")),
		"disabled": _box(Color("#353535"))
	}

	style.states = {
		"normal": {
			"scale": Vector2.ONE,
			"opacity": 1.0
		},
		"hover": {
			"scale": Vector2(1.1, 1.1)
		},
		"disabled": {
			"opacity": 0.5
		}
	}

	style.transition = {
		"properties": ["background_color", "scale", "opacity"],
		"duration": 0.12,
		"trans": Tween.TRANS_LINEAR,
		"ease": Tween.EASE_IN_OUT,
		"iterations": 1
	}

	return style


func _apply_button(control: Control, values: Dictionary) -> void:
	var button := control as Button

	if values.has("disabled"):
		button.disabled = values["disabled"]


func _register_button(style_id: String = "core:animated-button") -> void:
	var button := Button.new()
	var scene := PackedScene.new()

	assert_eq(scene.pack(button), OK)
	button.free()

	var definition := UIComponentDefinition.from_scene(
		"core:button",
		scene,
		Callable(self, "_apply_button"),
		{
			"style": {
				"type": TYPE_STRING,
				"default": style_id,
				"mod_editable": true
			},
			"disabled": {
				"type": TYPE_BOOL,
				"default": false,
				"mod_editable": true
			}
		}
	)

	assert_true(components.register_scene(definition))
	assert_true(components.finalize())


func _prepare_animated_button() -> UIComponentInstance:
	assert_true(styles.register_style(_animated_style()))
	assert_true(styles.finalize())
	_register_button()

	var instance := components.instantiate_component("core:button")
	assert_not_null(instance)
	return instance


func test_registered_states_are_inherited() -> void:
	var parent := _animated_style()
	parent.id = "core:base"

	var child := UIStyleDefinition.new()
	child.id = "core:derived"
	child.parent = "core:base"
	child.states = {
		"hover": {"opacity": 0.8}
	}
	child.transition = {
		"duration": 0.3
	}

	assert_true(styles.register_style(parent))
	assert_true(styles.register_style(child))
	assert_true(styles.finalize())

	var result := styles.prepare_instance("core:derived", {}, true)

	assert_eq(result.states["hover"]["scale"], Vector2(1.1, 1.1))
	assert_eq(result.states["hover"]["opacity"], 0.8)
	assert_eq(result.transition["duration"], 0.3)
	assert_eq(result.transition["properties"], parent.transition["properties"])


func test_invalid_transition_property_is_rejected() -> void:
	var style := _animated_style()
	style.transition["properties"].append("texture")

	assert_false(styles.register_style(style))
	assert_false(styles.errors.is_empty())


func test_invalid_visual_state_is_rejected() -> void:
	var style := _animated_style()
	style.states["unknown"] = {"scale": Vector2.ONE}

	assert_false(styles.register_style(style))


func test_controller_is_created_for_animated_style() -> void:
	var instance := _prepare_animated_button()

	assert_not_null(instance.transition)
	assert_eq(instance.transition.current_state, "normal")
	assert_false(instance.transition.is_animating())

	instance.root.free()


func test_state_changes_without_tree_apply_values_immediately() -> void:
	var instance := _prepare_animated_button()
	var button := instance.content_root as Button

	instance.transition.set_state("hover")

	assert_eq(instance.transition.current_state, "hover")
	assert_eq(button.scale, Vector2(1.1, 1.1))
	assert_false(instance.transition.is_animating())

	instance.root.free()



func test_transition_animates_local_stylebox() -> void:
	var first := _prepare_animated_button()
	var second := components.instantiate_component("core:button")

	first.root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	second.root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(first.root)
	add_child(second.root)

	var first_transition := first.transition
	first_transition.set_state("hover")

	assert_true(first_transition.is_animating())

	first_transition._apply_progress(0.5)

	var first_box := first.content_root.get_theme_stylebox("normal") as StyleBoxFlat
	var second_box := second.content_root.get_theme_stylebox("normal") as StyleBoxFlat

	var normal_color := Color("#304050")
	var hover_color := Color("#6080A0")
	var expected_color := normal_color.lerp(hover_color, 0.5)

	assert_true(first_box.bg_color.is_equal_approx(expected_color))
	assert_eq(second_box.bg_color, normal_color)
	assert_ne(first_box, second_box)

	assert_true(first.content_root.scale.is_equal_approx(Vector2(1.05, 1.05)))

	await get_tree().create_timer(0.2).timeout

	var hover_box := first.content_root.get_theme_stylebox("hover") as StyleBoxFlat

	assert_eq(hover_box.bg_color, hover_color)
	assert_false(first_transition.is_animating())

	first.root.free()
	second.root.free()



func test_interrupted_transition_starts_from_current_color() -> void:
	var instance := _prepare_animated_button()
	add_child(instance.root)

	instance.transition.set_state("hover")

	await get_tree().create_timer(0.05).timeout

	var current_box := instance.content_root.get_theme_stylebox("normal") as StyleBoxFlat
	var current_color := current_box.bg_color

	instance.transition.set_state("normal")

	var restarted_box := instance.content_root.get_theme_stylebox("normal") as StyleBoxFlat

	assert_true(restarted_box.bg_color.is_equal_approx(current_color))
	assert_eq(instance.transition.current_state, "normal")

	instance.root.free()


func test_disabled_property_changes_visual_state() -> void:
	var instance := _prepare_animated_button()
	add_child(instance.root)

	assert_true(instance.update({"disabled": true}))
	assert_true((instance.content_root as Button).disabled)
	assert_eq(instance.transition.current_state, "disabled")

	await get_tree().create_timer(0.18).timeout

	assert_true(is_equal_approx(instance.content_root.modulate.a, 0.5))

	assert_true(instance.update({"disabled": false}))
	assert_eq(instance.transition.current_state, "normal")

	instance.root.free()


func test_visual_only_scale_uses_center_pivot() -> void:
	var style := _animated_style()
	style.layout["scale_mode"] = "visual_only"
	style.layout["pivot_ratio"] = Vector2(0.5, 0.5)

	assert_true(styles.register_style(style))
	assert_true(styles.finalize())
	_register_button()

	var instance := components.instantiate_component("core:button")
	assert_not_null(instance)

	var button := instance.content_root as Button
	button.size = Vector2(240, 48)

	assert_true(button.offset_transform_enabled)
	assert_true(button.offset_transform_visual_only)
	assert_eq(button.offset_transform_pivot_ratio, Vector2(0.5, 0.5))

	instance.transition.set_state("hover")

	assert_eq(button.scale, Vector2.ONE)
	assert_eq(button.offset_transform_scale, Vector2(1.1, 1.1))

	# O pivot relativo acompanha o redimensionamento.
	button.size = Vector2(320, 64)

	assert_eq(button.offset_transform_pivot_ratio, Vector2(0.5, 0.5))
	assert_eq(
		button.size * button.offset_transform_pivot_ratio,
		Vector2(160, 32)
	)

	instance.root.free()


func test_visual_only_scale_supports_custom_pivot() -> void:
	var style := _animated_style()

	style.layout["scale_mode"] = "visual_only"
	style.layout["pivot_ratio"] = Vector2(0.25, 0.75)
	style.layout["pivot_offset"] = Vector2(8, -3)

	assert_true(styles.register_style(style))
	assert_true(styles.finalize())
	_register_button()

	var instance := components.instantiate_component("core:button")
	assert_not_null(instance)

	var button := instance.content_root as Button

	assert_eq(button.offset_transform_pivot_ratio, Vector2(0.25, 0.75))
	assert_eq(button.offset_transform_pivot, Vector2(8, -3))

	instance.root.free()


func test_invalid_scale_mode_is_rejected() -> void:
	var style := _animated_style()
	style.layout["scale_mode"] = "unknown"

	assert_false(styles.register_style(style))
	assert_false(styles.errors.is_empty())
