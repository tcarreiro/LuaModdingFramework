extends GutTest

var lua_state: LuaState
var codec: RuntimeStorage


func before_each() -> void:
	lua_state = LuaState.new()
	lua_state.open_libraries(LuaState.LUA_BASE | LuaState.LUA_TABLE)
	codec = RuntimeStorage.new()


func after_each() -> void:
	lua_state = null
	codec = null


func test_empty_storage_roundtrip() -> void:
	var storage := lua_state.create_table()
	var snapshot := codec.capture(lua_state, storage)

	assert_true(codec.errors.is_empty())
	assert_eq(snapshot["version"], RuntimeStorage.FORMAT_VERSION)

	var restored := codec.restore(lua_state, snapshot)

	assert_not_null(restored)
	assert_true(restored.to_dictionary().is_empty())


func test_nested_storage_roundtrip() -> void:
	var storage := lua_state.create_table()
	var player := lua_state.create_table()

	player.rawset("level", 12)
	player.rawset("name", "Explorer")
	storage.rawset("player", player)
	storage.rawset("enabled", true)

	var snapshot := codec.capture(lua_state, storage)
	var restored := codec.restore(lua_state, snapshot)

	assert_true(codec.errors.is_empty())
	assert_eq(restored.rawget("enabled"), true)

	var restored_player: LuaTable = restored.rawget("player")
	assert_eq(restored_player.rawget("level"), 12)
	assert_eq(restored_player.rawget("name"), "Explorer")


func test_circular_references_are_preserved() -> void:
	var storage := lua_state.create_table()
	storage.rawset("self", storage)

	var snapshot := codec.capture(lua_state, storage)
	var restored := codec.restore(lua_state, snapshot)
	var self_reference: LuaTable = restored.rawget("self")

	assert_true(codec.errors.is_empty())
	assert_eq(self_reference.get_pointer_value(), restored.get_pointer_value())


func test_shared_table_references_are_preserved() -> void:
	var storage := lua_state.create_table()
	var shared := lua_state.create_table()

	shared.rawset("value", 123)
	storage.rawset("first", shared)
	storage.rawset("second", shared)

	var snapshot := codec.capture(lua_state, storage)
	var restored := codec.restore(lua_state, snapshot)

	var first: LuaTable = restored.rawget("first")
	var second: LuaTable = restored.rawget("second")

	assert_eq(first.get_pointer_value(), second.get_pointer_value())


func test_numeric_keys_are_preserved() -> void:
	var storage := lua_state.create_table()
	storage.rawset(1, "first")
	storage.rawset(2, "second")

	var snapshot := codec.capture(lua_state, storage)
	var restored := codec.restore(lua_state, snapshot)

	assert_eq(restored.rawget(1), "first")
	assert_eq(restored.rawget(2), "second")


func test_lua_functions_cannot_be_saved() -> void:
	var storage := lua_state.create_table()
	var callback := lua_state.create_function(func() -> void: pass)

	storage.rawset("callback", callback)

	var snapshot := codec.capture(lua_state, storage)

	assert_true(snapshot.is_empty())
	assert_false(codec.errors.is_empty())


func test_rejects_invalid_snapshot() -> void:
	var restored := codec.restore(lua_state, {
		"version": 999,
		"root": 0,
		"tables": []
	})

	assert_null(restored)
	assert_false(codec.errors.is_empty())


func test_release_clears_codec_references() -> void:
	var storage := lua_state.create_table()
	storage.rawset("value", 42)

	var snapshot := codec.capture(lua_state, storage)

	assert_true(codec.errors.is_empty())
	assert_false(snapshot.is_empty())
	assert_same(codec._lua_state, lua_state)

	codec.release()

	assert_null(codec._lua_state)
	assert_true(codec._table_ids.is_empty())
	assert_true(codec._nodes.is_empty())
	assert_eq(codec._entry_count, 0)

	var restored := codec.restore(lua_state, snapshot)
	assert_not_null(restored)
	assert_eq(restored.rawget("value"), 42)
