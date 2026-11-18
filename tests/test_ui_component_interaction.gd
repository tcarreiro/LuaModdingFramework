extends GutTest

var registry: UIComponentRegistry


func before_each() -> void:
	registry = UIComponentRegistry.new()


func _noop(_control: Control, _values: Dictionary) -> void:
	pass


func _register_button() -> void:
	var button := Button.new()
	var scene := PackedScene.new()

	assert_eq(scene.pack(button), OK)
	button.free()

	var definition := UIComponentDefinition.from_scene(
		"core:button", scene, _noop
	)

	definition.events = [
		&"pressed",
		&"opened"
	]

	definition.event_sources = {
		&"pressed": {
			"path": NodePath("."),
			"signal": &"pressed"
		}
	}

	definition.hooks = {
		&"can_drop": {
			"type": TYPE_BOOL,
			"args": [TYPE_INT],
			"fallback": false
		}
	}

	assert_true(registry.register_scene(definition))
	assert_true(registry.finalize())


func test_interactions_are_created_lazily() -> void:
	_register_button()

	var instance := registry.instantiate_component("core:button")

	assert_null(instance.interaction)

	assert_true(instance.on_event(&"opened", func(_event): pass))
	assert_not_null(instance.interaction)

	instance.root.free()


func test_native_button_signal_dispatches_event() -> void:
	_register_button()

	var instance := registry.instantiate_component("core:button")
	var received: Array = []

	assert_true(instance.on_event(&"pressed", func(event: Dictionary):
		received.append(event)
	))

	(instance.content_root as Button).pressed.emit()

	assert_eq(received.size(), 1)
	assert_eq(received[0]["name"], "pressed")
	assert_true(received[0]["arguments"].is_empty())

	instance.clear_callbacks()
	instance.root.free()


func test_manual_event_dispatch() -> void:
	_register_button()

	var instance := registry.instantiate_component("core:button")
	var received: Array = []

	assert_true(instance.on_event(&"opened", func(event: Dictionary):
		received.append(event["arguments"][0])
	))

	assert_true(instance.emit_event(&"opened", [42]))
	assert_eq(received, [42])

	instance.clear_callbacks()
	instance.root.free()


func test_multiple_event_listeners() -> void:
	_register_button()

	var instance := registry.instantiate_component("core:button")
	var results: Array = []

	assert_true(instance.on_event(&"pressed", func(_event): results.append("A")))
	assert_true(instance.on_event(&"pressed", func(_event): results.append("B")))

	(instance.content_root as Button).pressed.emit()

	assert_eq(results, ["A", "B"])

	instance.clear_callbacks()
	instance.root.free()


func test_unsubscribing_disconnects_native_signal() -> void:
	_register_button()

	var instance := registry.instantiate_component("core:button")
	var calls := [0]

	var handler := func(_event):
		calls[0] += 1

	assert_true(instance.on_event(&"pressed", handler))
	(instance.content_root as Button).pressed.emit()

	assert_true(instance.off_event(&"pressed", handler))
	(instance.content_root as Button).pressed.emit()

	assert_eq(calls[0], 1)
	assert_true(instance.interaction._connections.is_empty())

	instance.root.free()


func test_hook_returns_fallback_when_unregistered() -> void:
	_register_button()

	var instance := registry.instantiate_component("core:button")

	assert_false(instance.call_hook(&"can_drop", [42]))

	instance.root.free()


func test_hook_returns_handler_result() -> void:
	_register_button()

	var instance := registry.instantiate_component("core:button")

	assert_true(instance.set_hook(&"can_drop", func(item_id: int) -> bool:
		return item_id == 42
	))

	assert_true(instance.call_hook(&"can_drop", [42]))
	assert_false(instance.call_hook(&"can_drop", [10]))

	instance.clear_callbacks()
	instance.root.free()


func test_invalid_hook_return_uses_fallback() -> void:
	_register_button()

	var instance := registry.instantiate_component("core:button")

	assert_true(instance.set_hook(&"can_drop", func(_item_id: int):
		return "invalid"
	))

	assert_false(instance.call_hook(&"can_drop", [42]))
	assert_false(instance.interaction.errors.is_empty())

	instance.clear_callbacks()
	instance.root.free()


func test_invalid_hook_argument_uses_fallback() -> void:
	_register_button()

	var instance := registry.instantiate_component("core:button")

	assert_true(instance.set_hook(&"can_drop", func(_item_id: int):
		return true
	))

	assert_false(instance.call_hook(&"can_drop", ["invalid"]))
	assert_false(instance.interaction.errors.is_empty())

	instance.clear_callbacks()
	instance.root.free()


func test_undeclared_events_and_hooks_are_rejected() -> void:
	_register_button()

	var instance := registry.instantiate_component("core:button")

	assert_false(instance.on_event(&"unknown", func(_event): pass))
	assert_false(instance.set_hook(&"unknown", func(): return true))

	instance.clear_callbacks()
	instance.root.free()


func test_static_component_has_no_interaction_overhead() -> void:
	_register_button()

	var instance := registry.instantiate_component("core:button")

	assert_null(instance.interaction)

	instance.root.free()
