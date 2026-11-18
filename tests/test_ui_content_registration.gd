extends GutTest

const VALID_TEMPLATE := """
	assert(UI.define_component("demo_b:counter", {
		properties = {
			title = {type = "string", default = "Inicial"},
			button_label = {type = "string", default = "Clique"}
		},
		tree = {
			component = "core:column",
			children = {
				{
					name = "description",
					component = "core:label",
					props = {
						text = {["$prop"] = "title"}
					}
				},
				{
					name = "action",
					component = "core:button",
					props = {
						label = {["$prop"] = "button_label"}
					}
				}
			}
		},
		events = {
			pressed = {source = "action", event = "pressed"}
		}
	}))
"""

var components: UIComponentRegistry
var content_state: ContentState


func before_each() -> void:
	components = UIComponentRegistry.new()

	var column := UIComponentDefinition.from_scene(
		"core:column",
		_pack(VBoxContainer.new()),
		Callable(self, "_noop")
	)

	var label := UIComponentDefinition.from_scene(
		"core:label",
		_pack(Label.new()),
		Callable(self, "_apply_label"),
		{
			"text": {
				"type": TYPE_STRING,
				"default": "",
				"mod_editable": true
			}
		}
	)

	var button := UIComponentDefinition.from_scene(
		"core:button",
		_pack(Button.new()),
		Callable(self, "_apply_button"),
		{
			"label": {
				"type": TYPE_STRING,
				"default": "",
				"mod_editable": true
			}
		}
	)

	button.events = [&"pressed"]
	button.event_sources = {
		&"pressed": {
			"path": NodePath("."),
			"signal": &"pressed"
		}
	}

	assert_true(components.register_scene(column))
	assert_true(components.register_scene(label))
	assert_true(components.register_scene(button))

	content_state = ContentState.new(ContentTypeRegistry.new(), components)
	content_state.start()


func after_each() -> void:
	if content_state != null:
		content_state.close()


func _pack(control: Control) -> PackedScene:
	var scene := PackedScene.new()
	assert_eq(scene.pack(control), OK)
	control.free()
	return scene


func _noop(_control: Control, _values: Dictionary) -> void:
	pass


func _apply_label(control: Control, values: Dictionary) -> void:
	if values.has("text"):
		(control as Label).text = values["text"]


func _apply_button(control: Control, values: Dictionary) -> void:
	if values.has("label"):
		(control as Button).text = values["label"]


func test_ui_api_is_available_in_content_stage() -> void:
	assert_true(content_state.execute("""
		assert(type(UI) == "table")
		assert(type(UI.define_component) == "function")
	""", "demo_b"))


func test_lua_registers_composed_component() -> void:
	assert_true(content_state.execute(
		VALID_TEMPLATE, "demo_b"
	), str(content_state.get_errors()))

	assert_true(components.has_component("demo_b:counter"))
	assert_false(components.is_finalized())

	var definition := components.get_definition("demo_b:counter")

	assert_eq(definition.kind, UIComponentDefinition.Kind.TEMPLATE)
	assert_eq(definition.owner_mod_id, "demo_b")
	assert_eq(definition.properties["title"]["type"], TYPE_STRING)
	assert_eq(definition.template["component"], "core:column")
	assert_eq(definition.event_routes["pressed"]["source"], "action")


func test_component_survives_content_lua_state_shutdown() -> void:
	assert_true(content_state.execute(
		VALID_TEMPLATE, "demo_b"
	), str(content_state.get_errors()))

	content_state.close()

	assert_true(components.finalize(), str(components.errors))

	var instance := components.instantiate_component("demo_b:counter", {
		"title": "Demo B",
		"button_label": "Clique aqui"
	})

	assert_not_null(instance)

	var column := instance.root as VBoxContainer

	assert_not_null(column)
	assert_eq(column.get_child_count(), 2)
	assert_eq((column.get_child(0) as Label).text, "Demo B")
	assert_eq((column.get_child(1) as Button).text, "Clique aqui")

	instance.clear_callbacks()
	instance.root.free()


func test_bound_properties_update_without_rebuilding_tree() -> void:
	assert_true(content_state.execute(VALID_TEMPLATE, "demo_b"))
	assert_true(components.finalize())

	var instance := components.instantiate_component("demo_b:counter")
	var column := instance.root as VBoxContainer
	var label := column.get_child(0) as Label
	var button := column.get_child(1) as Button

	assert_true(instance.update({
		"title": "Tick: 10",
		"button_label": "Cliques: 5"
	}))

	assert_same(column.get_child(0), label)
	assert_same(column.get_child(1), button)
	assert_eq(label.text, "Tick: 10")
	assert_eq(button.text, "Cliques: 5")

	instance.clear_callbacks()
	instance.root.free()


func test_internal_button_event_is_forwarded() -> void:
	assert_true(content_state.execute(VALID_TEMPLATE, "demo_b"))
	assert_true(components.finalize())

	var instance := components.instantiate_component("demo_b:counter")
	var received: Array = []

	assert_true(instance.on_event(&"pressed", func(event: Dictionary):
		received.append(event["name"])
	))

	var button := instance.root.get_child(1) as Button
	button.pressed.emit()

	assert_eq(received, ["pressed"])

	instance.clear_callbacks()
	instance.root.free()


func test_mod_cannot_register_another_mod_namespace() -> void:
	assert_false(content_state.execute("""
		UI.define_component("demo_a:foreign", {
			tree = {component = "core:column"}
		})
	""", "demo_b"))

	assert_false(components.has_component("demo_a:foreign"))
	assert_false(content_state.errors.is_empty())


func test_invalid_native_component_reference_is_rejected() -> void:
	assert_true(content_state.execute("""
		UI.define_component("demo_b:invalid", {
			tree = {component = "core:missing"}
		})
	""", "demo_b"))

	assert_false(components.finalize())
	assert_false(components.errors.is_empty())


func test_duplicate_named_children_are_rejected() -> void:
	assert_true(content_state.execute("""
		UI.define_component("demo_b:duplicate", {
			tree = {
				component = "core:column",
				children = {
					{name = "action", component = "core:button"},
					{name = "action", component = "core:button"}
				}
			},
			events = {
				pressed = {source = "action", event = "pressed"}
			}
		})
	""", "demo_b"))

	assert_false(components.finalize())
	assert_false(components.errors.is_empty())


func test_replaced_ui_api_is_detected() -> void:
	assert_false(content_state.execute("""
		UI.define_component = function() return true end
	""", "demo_b"))

	assert_false(content_state.errors.is_empty())
