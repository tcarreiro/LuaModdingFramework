extends GutTest

var registry: UIComponentRegistry
var mount: VBoxContainer
var state: RuntimeState
var bridge: UIRuntimeBridge


func before_each() -> void:
	registry = UIComponentRegistry.new()

	mount = VBoxContainer.new()
	add_child(mount)

	var button := Button.new()
	var scene := PackedScene.new()
	assert_eq(scene.pack(button), OK)
	button.free()

	var definition := UIComponentDefinition.from_scene(
		"core:test-button",
		scene,
		Callable(self, "_apply_button"),
		{
			"label": {
				"type": TYPE_STRING,
				"default": "Default",
				"mod_editable": true
			},
			"disabled": {
				"type": TYPE_BOOL,
				"default": false,
				"mod_editable": true
			}
		}
	)

	definition.events = [&"pressed"]
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

func after_each() -> void:
	if bridge != null:
		bridge.close()

	if state != null:
		state.close()

	if is_instance_valid(mount):
		mount.free()

	await wait_process_frames(2)



func _apply_button(control: Control, values: Dictionary) -> void:
	var button := control as Button

	if values.has("label"):
		button.text = values["label"]

	if values.has("disabled"):
		button.disabled = values["disabled"]


func _start_runtime(source: String) -> void:
	state = RuntimeState.new("demo")

	assert_true(state.start())

	bridge = UIRuntimeBridge.new()
	bridge.setup(registry, mount, state)

	var api := RuntimeApiRegistry.new()
	var functions := bridge.get_api_functions()

	for name in functions:
		assert_true(api.register_function("ui", name, functions[name]))

	assert_true(state.execute(source, "demo", "test-ui.lua"), str(state.get_errors()))
	assert_true(state.finish_setup())
	assert_true(state.activate({}, api), str(state.get_errors()))
	assert_true(state.run_lifecycle("on_init"), str(state.get_errors()))


func test_lua_can_create_component() -> void:
	_start_runtime("""
		script.on_init(function()
			window_handle = game.ui.open("core:test-button", {
				label = "Inventory"
			})
			assert(window_handle > 0)
		end)
	""")

	assert_eq(mount.get_child_count(), 1)
	assert_eq((mount.get_child(0) as Button).text, "Inventory")


func test_lua_can_update_component() -> void:
	_start_runtime("""
		script.on_init(function()
			local handle = game.ui.open("core:test-button")
			assert(game.ui.set(handle, {
				label = "Updated",
				disabled = true
			}))
		end)
	""")

	var button := mount.get_child(0) as Button

	assert_eq(button.text, "Updated")
	assert_true(button.disabled)


func test_native_event_invokes_lua_callback() -> void:
	_start_runtime("""
		script.on_init(function()
			local handle = game.ui.open("core:test-button")

			assert(game.ui.on(handle, "pressed", function(event)
				assert(event.name == "pressed")
				storage.presses = (storage.presses or 0) + 1
			end))
		end)
	""")

	(mount.get_child(0) as Button).pressed.emit()

	assert_eq(state._storage.rawget("presses"), 1)
	assert_true(state.get_errors().is_empty())


func test_hook_returns_lua_result() -> void:
	_start_runtime("""
		script.on_init(function()
			local handle = game.ui.open("core:test-button")

			assert(game.ui.hook(handle, "can_drop", function(item_id)
				return item_id == 42
			end))
		end)
	""")

	var instance: UIComponentInstance = bridge._instances[1]

	assert_true(instance.call_hook(&"can_drop", [42]))
	assert_false(instance.call_hook(&"can_drop", [10]))


func test_lua_can_close_component() -> void:
	_start_runtime("""
		script.on_init(function()
			local handle = game.ui.open("core:test-button")
			assert(game.ui.close(handle))
		end)
	""")

	assert_eq(mount.get_child_count(), 0)
	assert_true(bridge._instances.is_empty())
	assert_true(state._ui_callbacks.is_empty())


func test_invalid_handle_is_rejected() -> void:
	_start_runtime("""
		script.on_init(function()
			assert(not game.ui.set(9999, {label = "Invalid"}))
			assert(not game.ui.close(9999))
		end)
	""")

	assert_true(bridge._instances.is_empty())
	assert_eq(mount.get_child_count(), 0)


func test_unexposed_component_cannot_be_created() -> void:
	var private_scene := PackedScene.new()
	var node := PanelContainer.new()
	assert_eq(private_scene.pack(node), OK)
	node.free()

	# Usamos outro registry porque o anterior já está finalizado.
	registry = UIComponentRegistry.new()

	var definition := UIComponentDefinition.from_scene(
		"core:private",
		private_scene,
		Callable(self, "_apply_noop")
	)
	definition.exposed_to_mods = false

	assert_true(registry.register_scene(definition))
	assert_true(registry.finalize())

	_start_runtime("""
		script.on_init(function()
			assert(game.ui.open("core:private") == 0)
		end)
	""")

	assert_eq(mount.get_child_count(), 0)


func _apply_noop(_control: Control, _values: Dictionary) -> void:
	pass


func test_bridge_cleanup_releases_lua_callbacks() -> void:
	_start_runtime("""
		script.on_init(function()
			local handle = game.ui.open("core:test-button")

			assert(game.ui.on(handle, "pressed", function(event)
				storage.called = true
			end))
		end)
	""")

	assert_eq(state._ui_callbacks.size(), 1)

	bridge.close()

	assert_true(state._ui_callbacks.is_empty())
	assert_true(state._ui_coroutines.is_empty())
	assert_eq(mount.get_child_count(), 0)


func test_ui_can_close_itself_from_event() -> void:
	_start_runtime("""
		script.on_init(function()
			local handle = game.ui.open("core:test-button")

			assert(game.ui.on(handle, "pressed", function(event)
				assert(game.ui.close(handle))
			end))
		end)
	""")

	assert_eq(mount.get_child_count(), 1)

	var button := mount.get_child(0) as Button
	button.pressed.emit()

	assert_eq(mount.get_child_count(), 0)
	assert_true(bridge._instances.is_empty())
	assert_true(state._ui_callbacks.is_empty())


func test_closed_component_is_eventually_freed() -> void:
	_start_runtime("""
		script.on_init(function()
			window_handle = game.ui.open("core:test-button")
		end)
	""")

	var button := mount.get_child(0) as Button

	assert_true(bridge._api_close(1))

	assert_eq(mount.get_child_count(), 0)
	assert_false(button.is_inside_tree())

	assert_true(button.is_queued_for_deletion())
	assert_true(is_instance_valid(button))

	await wait_process_frames(2)

	assert_false(is_instance_valid(button))
