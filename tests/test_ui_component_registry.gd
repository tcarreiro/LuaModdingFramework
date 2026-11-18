extends GutTest

var registry: UIComponentRegistry
var column_scene: PackedScene
var label_scene: PackedScene


func before_each() -> void:
	registry = UIComponentRegistry.new()
	column_scene = _packed(VBoxContainer.new())
	label_scene = _packed(Label.new())


func _packed(node: Control) -> PackedScene:
	var scene := PackedScene.new()
	assert_eq(scene.pack(node), OK)
	node.free()
	return scene


func _apply_label(control: Control, values: Dictionary) -> void:
	if values.has("text"):
		(control as Label).text = values["text"]


func _noop(_control: Control, _values: Dictionary) -> void:
	pass


func _register_native() -> void:
	var column := UIComponentDefinition.from_scene("core:column", column_scene, _noop)
	var label := UIComponentDefinition.from_scene("core:label", label_scene, _apply_label, {
		"text": {"type": TYPE_STRING, "default": "", "mod_editable": true},
		"internal_color": {"type": TYPE_COLOR, "default": Color.WHITE, "mod_editable": false}
	})
	assert_true(registry.register_scene(column))
	assert_true(registry.register_scene(label))


func _card_template() -> UIComponentDefinition:
	return UIComponentDefinition.from_template("demo:item_card", "demo", {
		"component": "core:column",
		"children": [
			{"component": "core:label", "props": {"text": {"$prop": "title"}}}
		]
	}, {
		"title": {"type": TYPE_STRING, "default": "Item", "mod_editable": true}
	})


func test_native_scene_can_be_instantiated() -> void:
	_register_native()
	assert_true(registry.finalize())
	var instance := registry.instantiate_component("core:label", {"text": "Hello"})
	assert_not_null(instance)
	assert_true(instance.root is Label)
	assert_eq((instance.root as Label).text, "Hello")
	instance.root.free()


func test_mod_can_register_composed_template() -> void:
	_register_native()
	assert_true(registry.register_template(_card_template()))
	assert_true(registry.finalize())
	var card := registry.instantiate_component("demo:item_card", {"title": "Bronze Gauntlet"})
	assert_not_null(card)
	assert_true(card.root is VBoxContainer)
	assert_eq(card.root.get_child_count(), 1)
	assert_eq((card.root.get_child(0) as Label).text, "Bronze Gauntlet")
	card.root.free()


func test_template_updates_bound_property_without_rebuilding_tree() -> void:
	_register_native()
	registry.register_template(_card_template())
	assert_true(registry.finalize())
	var card := registry.instantiate_component("demo:item_card")
	var child := card.root.get_child(0) as Label
	assert_true(card.update({"title": "Iron Gauntlet"}))
	assert_same(card.root.get_child(0), child)
	assert_eq(child.text, "Iron Gauntlet")
	card.root.free()


func test_multiple_instances_are_independent() -> void:
	_register_native()
	registry.register_template(_card_template())
	assert_true(registry.finalize())
	var first := registry.instantiate_component("demo:item_card")
	var second := registry.instantiate_component("demo:item_card")
	assert_true(first.update({"title": "A"}))
	assert_eq((first.root.get_child(0) as Label).text, "A")
	assert_eq((second.root.get_child(0) as Label).text, "Item")
	first.root.free()
	second.root.free()


func test_restricted_properties_are_rejected() -> void:
	_register_native()
	assert_true(registry.finalize())
	assert_null(registry.instantiate_component("core:label", {"internal_color": Color.RED}))
	assert_false(registry.errors.is_empty())


func test_mod_template_cannot_set_restricted_child_properties() -> void:
	_register_native()
	var template := UIComponentDefinition.from_template("demo:bad", "demo", {
		"component": "core:label",
		"props": {"internal_color": Color.RED}
	})
	assert_true(registry.register_template(template))
	assert_false(registry.finalize())


func test_missing_component_and_cycles_are_rejected() -> void:
	var broken := UIComponentDefinition.from_template("demo:broken", "demo", {"component": "missing:component"})
	assert_true(registry.register_template(broken))
	assert_false(registry.finalize())

	registry.clear()
	var a := UIComponentDefinition.from_template("demo:a", "demo", {"component": "demo:b"})
	var b := UIComponentDefinition.from_template("demo:b", "demo", {"component": "demo:a"})
	assert_true(registry.register_template(a))
	assert_true(registry.register_template(b))
	assert_false(registry.finalize())


func test_finalization_prevents_new_definitions() -> void:
	_register_native()
	assert_true(registry.finalize())
	assert_false(registry.register_template(_card_template()))
	assert_false(registry.has_component("demo:item_card"))


func test_definition_is_copied_on_registration() -> void:
	_register_native()
	var card := _card_template()
	assert_true(registry.register_template(card))
	card.template["component"] = "missing:component"
	card.properties["title"]["default"] = "Changed"
	assert_true(registry.finalize())
	var instance := registry.instantiate_component("demo:item_card")
	assert_eq((instance.root.get_child(0) as Label).text, "Item")
	instance.root.free()


func test_slots_and_drag_references() -> void:
	var definition := UIComponentDefinition.from_scene(
		"core:draggable",
		column_scene,
		_noop,
		{},
		{"default": NodePath("."), "content": NodePath(".")}
	)
	definition.drag_target = NodePath(".")
	definition.drag_handle = NodePath(".")

	assert_true(registry.register_scene(definition))
	assert_true(registry.finalize())

	var instance := registry.instantiate_component("core:draggable")

	assert_same(instance.get_slot("content"), instance.root)
	assert_same(instance.get_drag_target(), instance.root)
	assert_same(instance.get_drag_handle(), instance.root)

	instance.root.free()
