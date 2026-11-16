extends GutTest

var lua_state: LuaState
var guard: LuaExecutionGuard


func before_each() -> void:
	lua_state = LuaState.new()
	lua_state.open_libraries(
		LuaState.LUA_BASE |
		LuaState.LUA_STRING |
		LuaState.LUA_TABLE |
		LuaState.LUA_MATH
	)

	LuaExecutionGuard.restrict_base_functions(lua_state)
	guard = LuaExecutionGuard.new()


func after_each() -> void:
	lua_state = null
	guard = null


func test_invoke_existing_lua_function() -> void:
	assert_true(guard.execute(lua_state, """
		function double(value)
			return value * 2
		end
	"""))

	var callback: LuaFunction = lua_state.globals["double"]

	assert_true(guard.invoke(lua_state, callback, [21], "double"))
	assert_eq(guard.last_result, 42)


func test_invoke_passes_multiple_arguments() -> void:
	assert_true(guard.execute(lua_state, """
		function add(a, b)
			return a + b
		end
	"""))

	var callback: LuaFunction = lua_state.globals["add"]

	assert_true(guard.invoke(lua_state, callback, [10, 32]))
	assert_eq(guard.last_result, 42)


func test_invoke_rejects_infinite_loop() -> void:
	guard.max_instructions = 10_000

	assert_true(guard.execute(lua_state, """
		function infinite_loop()
			while true do
			end
		end
	"""))

	var callback: LuaFunction = lua_state.globals["infinite_loop"]

	assert_false(guard.invoke(lua_state, callback))
	assert_true(guard.last_error.contains("instruction limit"))


func test_invoke_rejects_callback_from_another_state() -> void:
	assert_true(guard.execute(lua_state, """
		function callback()
			return true
		end
	"""))

	var callback: LuaFunction = lua_state.globals["callback"]

	var another_state := LuaState.new()
	another_state.open_libraries(LuaState.LUA_BASE)

	assert_false(guard.invoke(another_state, callback))
	assert_true(guard.last_error.contains("different LuaState"))


func test_invoke_recovers_after_error() -> void:
	assert_true(guard.execute(lua_state, """
		function failing()
			error("expected failure")
		end

		function working()
			return 123
		end
	"""))

	var failing: LuaFunction = lua_state.globals["failing"]
	var working: LuaFunction = lua_state.globals["working"]

	assert_false(guard.invoke(lua_state, failing))
	assert_false(guard.last_error.is_empty())

	assert_true(guard.invoke(lua_state, working))
	assert_eq(guard.last_result, 123)
	assert_eq(guard.last_error, "")
