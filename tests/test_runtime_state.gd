extends GutTest

var state: RuntimeState


func before_each() -> void:
	state = RuntimeState.new("core")
	assert_true(state.start({
		"core": "0.1.0",
		"demo_a": "0.1.0"
	}))


func after_each() -> void:
	state.close()


func _get_test_value() -> int:
	return 42


func test_initial_phase_is_setup() -> void:
	assert_eq(state.get_phase(), RuntimeState.Phase.SETUP)


func test_control_has_no_game_access() -> void:
	assert_true(state.execute_control("""
		assert(game == nil)
		assert(script ~= nil)
		assert(mods["core"] == "0.1.0")
	""", "core/control.lua"))


func test_register_lifecycle_handlers() -> void:
	assert_true(state.execute_control("""
		script.on_init(function()
			assert(game ~= nil)
		end)

		script.on_load(function()
		end)

		script.on_configuration_changed(function(event)
		end)
	""", "core/control.lua"))

	assert_true(state.has_lifecycle_handler("on_init"))
	assert_true(state.has_lifecycle_handler("on_load"))
	assert_true(state.has_lifecycle_handler("on_configuration_changed"))


func test_lifecycle_handler_can_be_unregistered() -> void:
	assert_true(state.execute_control("""
		script.on_init(function() end)
		script.on_init(nil)
	""", "core/control.lua"))

	assert_false(state.has_lifecycle_handler("on_init"))


func test_invalid_lifecycle_handler_is_rejected() -> void:
	assert_false(state.execute_control("""
		script.on_init(123)
	""", "core/control.lua"))

	assert_false(state.get_errors().is_empty())
	assert_false(state.finish_setup())


func test_lua_states_are_isolated() -> void:
	var second := RuntimeState.new("demo_a")

	assert_true(second.start({
		"core": "0.1.0",
		"demo_a": "0.1.0"
	}))

	assert_true(state.execute_control("""
		shared_value = 99
	""", "core/control.lua"))

	var success := second.execute_control("""
		assert(shared_value == nil)
		shared_value = 10
	""", "demo_a/control.lua")

	if not success:
		print("RuntimeState demo_a errors: ", second.get_errors())

	assert_true(success)

	assert_true(state.execute_control("""
		assert(shared_value == 99)
	""", "core/check.lua"))

	second.close()


func test_cannot_activate_before_setup_finishes() -> void:
	assert_false(state.activate())
	assert_eq(state.get_phase(), RuntimeState.Phase.SETUP)


func test_setup_then_activation() -> void:
	assert_true(state.execute_control("""
		assert(game == nil)
	""", "core/control.lua"))

	assert_true(state.finish_setup())
	assert_eq(state.get_phase(), RuntimeState.Phase.PREPARED)

	assert_true(state.activate({
		"get_test_value": _get_test_value
	}))

	assert_eq(state.get_phase(), RuntimeState.Phase.ACTIVE)


func test_cannot_execute_control_after_setup() -> void:
	assert_true(state.finish_setup())

	assert_false(state.execute_control("""
		late_registration = true
	""", "core/control.lua"))


func test_cannot_replace_script_api() -> void:
	assert_false(state.execute_control("""
		script.on_init = function() end
	""", "core/control.lua"))

	assert_false(state.finish_setup())


func test_cannot_define_game_during_setup() -> void:
	assert_false(state.execute_control("""
		game = {}
	""", "core/control.lua"))

	assert_true(state.get_errors()[0].contains("game"))


func test_restricted_libraries() -> void:
	assert_true(state.execute_control("""
		assert(io == nil)
		assert(os == nil)
		assert(package == nil)
		assert(debug == nil)
		assert(dofile == nil)
		assert(loadfile == nil)
	""", "core/control.lua"))


func test_close_releases_state() -> void:
	state.close()

	assert_eq(state.get_phase(), RuntimeState.Phase.CLOSED)
	assert_false(state.finish_setup())
