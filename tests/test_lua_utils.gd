extends GutTest


func test_normalize_integer() -> void:
	assert_eq(LuaUtils.normalize_integer(10.0), 10)
	assert_eq(LuaUtils.normalize_integer(0.0), 0)
	assert_eq(LuaUtils.normalize_integer(-25.0), -25)

	assert_eq(typeof(LuaUtils.normalize_integer(10.0)), TYPE_INT)


func test_normalize_integer_preserves_invalid_values() -> void:
	assert_eq(LuaUtils.normalize_integer(10.5), 10.5)
	assert_eq(LuaUtils.normalize_integer("10"), "10")
	assert_eq(LuaUtils.normalize_integer(true), true)

	assert_eq(typeof(LuaUtils.normalize_integer(10.5)), TYPE_FLOAT)
	assert_eq(typeof(LuaUtils.normalize_integer(9007199254740992.0)), TYPE_FLOAT)


func test_normalize_integer_fields() -> void:
	var data := {
		"default_value": 10.0,
		"minimum_value": 0.0,
		"maximum_value": 100.0,
		"allowed_values": [10.0, 25.0, 50.0]
	}

	var fields := ["default_value", "minimum_value", "maximum_value", "allowed_values"]

	LuaUtils.normalize_fields(data, [], [], fields)

	assert_eq(typeof(data["default_value"]), TYPE_INT)
	assert_eq(typeof(data["minimum_value"]), TYPE_INT)
	assert_eq(typeof(data["maximum_value"]), TYPE_INT)

	for value in data["allowed_values"]:
		assert_eq(typeof(value), TYPE_INT)

	assert_eq(data["allowed_values"], [10, 25, 50])


func test_same_lua_object_checks_identity_type_and_owner_state() -> void:
	var first := LuaState.new()
	var second := LuaState.new()

	var original := first.create_table()
	first.globals.rawset("reference", original)

	var alias: LuaTable = first.globals.rawget("reference")
	var different := first.create_table()
	var foreign := second.create_table()
	var function := first.create_function(func(): return true)

	assert_true(LuaUtils.same_lua_object(first, original, alias))
	assert_false(LuaUtils.same_lua_object(first, original, different))
	assert_false(LuaUtils.same_lua_object(first, original, foreign))
	assert_false(LuaUtils.same_lua_object(first, original, function))
	assert_false(LuaUtils.same_lua_object(second, original, alias))
	assert_false(LuaUtils.same_lua_object(null, original, alias))
