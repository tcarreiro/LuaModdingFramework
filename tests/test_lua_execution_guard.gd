extends GutTest

var lua: LuaState
var guard: LuaExecutionGuard


func before_each() -> void:
	lua = LuaState.new()
	lua.open_libraries(LuaState.LUA_BASE | LuaState.LUA_MATH)
	guard = LuaExecutionGuard.new()


func after_each() -> void:
	lua = null
	guard = null


func test_normal_execution() -> void:
	assert_true(guard.execute(lua, """
		result = 2 + 3
	"""))

	assert_eq(lua.globals["result"], 5)


func test_instruction_limit() -> void:
	guard.max_instructions = 2000
	guard.max_duration_ms = 10000

	assert_false(guard.execute(lua, """
		local total = 0

		for i = 1, 100000 do
			total = total + i
		end
	"""))

	assert_true(guard.last_error.contains("instruction limit"))


func test_source_size_limit() -> void:
	guard.max_source_bytes = 10

	assert_false(guard.execute(lua, """
		result = 123456789
	"""))

	assert_true(guard.last_error.contains("maximum allowed size"))


func test_syntax_error() -> void:
	assert_false(guard.execute(lua, """
		function invalid(
	"""))

	assert_false(guard.last_error.is_empty())


func test_execution_error() -> void:
	assert_false(guard.execute(lua, """
		error("Intentional failure")
	"""))

	assert_true(guard.last_error.contains("Intentional failure"))


func test_execution_after_failed_script() -> void:
	assert_false(guard.execute(lua, "error('Failure')"))
	assert_true(guard.execute(lua, "value = 42"))
	assert_eq(lua.globals["value"], 42)
