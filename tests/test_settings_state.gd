extends GutTest

var settings_state: SettingsState


func before_each() -> void:
	settings_state = SettingsState.new()
	settings_state.start()


func after_each() -> void:
	settings_state.close()
	settings_state = null


func test_state_initialization() -> void:
	assert_true(settings_state.is_active())


func test_define_setting_from_lua() -> void:
	var source := """
		Settings.define({
			id = "enemy_speed",
			display_name = "Enemy Speed",
			value_type = "string",
			default_value = "normal",
			allowed_values = {"slow", "normal", "fast"}
		})
	"""

	assert_true(settings_state.execute(source, "mod_a"))

	var registry := settings_state.finish()
	assert_not_null(registry)
	if registry == null:
		return

	var setting := registry.get_setting("enemy_speed")

	assert_not_null(setting)
	assert_eq(setting.owner_mod_id, "mod_a")
	assert_eq(setting.default_value, "normal")
	assert_eq(setting.allowed_values, ["slow", "normal", "fast"])


func test_multiple_mods_share_lua_state() -> void:
	assert_true(settings_state.execute("shared_value = 42", "mod_a"))

	var source := """
		Settings.define({
			id = "shared_test",
			value_type = "int",
			default_value = shared_value
		})
	"""

	assert_true(settings_state.execute(source, "mod_b"))

	var registry := settings_state.finish()
	assert_not_null(registry)
	if registry == null:
		return

	assert_eq(registry.get_effective_value("shared_test"), 42)
	assert_eq(registry.get_setting("shared_test").owner_mod_id, "mod_b")


func test_update_setting_from_another_mod() -> void:
	var definition := """
		Settings.define({
			id = "enemy_speed",
			value_type = "string",
			default_value = "normal",
			allowed_values = {"slow", "normal", "fast"}
		})
	"""

	var update := """
		Settings.update("enemy_speed", {
			default_value = "fast",
			description = "Modified by another mod"
		})
	"""

	assert_true(settings_state.execute(definition, "mod_a"))
	assert_true(settings_state.execute(update, "mod_b"))

	var registry := settings_state.finish()
	assert_not_null(registry)
	if registry == null:
		return

	var setting := registry.get_setting("enemy_speed")

	assert_eq(setting.default_value, "fast")
	assert_eq(setting.owner_mod_id, "mod_a")
	assert_eq(setting.last_modified_by, "mod_b")


func test_force_setting_from_another_mod() -> void:
	var definition := """
		Settings.define({
			id = "enemy_speed",
			value_type = "string",
			default_value = "normal",
			allowed_values = {"slow", "normal", "fast"}
		})
	"""

	assert_true(settings_state.execute(definition, "mod_a"))
	assert_true(settings_state.execute('Settings.force("enemy_speed", "fast")', "mod_b"))

	var registry := settings_state.finish()
	assert_not_null(registry)
	if registry == null:
		return

	var setting := registry.get_setting("enemy_speed")

	assert_true(setting.hidden)
	assert_true(setting.is_forced())
	assert_eq(setting.forced_value, "fast")
	assert_eq(setting.forced_by_mod_id, "mod_b")


func test_conflicting_forced_values() -> void:
	var definition := """
		Settings.define({
			id = "enemy_speed",
			value_type = "string",
			default_value = "normal",
			allowed_values = {"slow", "normal", "fast"}
		})
	"""

	assert_true(settings_state.execute(definition, "mod_a"))
	assert_true(settings_state.execute('Settings.force("enemy_speed", "fast")', "mod_b"))
	assert_true(settings_state.execute('Settings.force("enemy_speed", "slow")', "mod_c"))

	var registry := settings_state.finish()
	assert_not_null(registry)
	if registry == null:
		return

	assert_eq(registry.get_effective_value("enemy_speed"), "slow")
	assert_eq(registry.get_setting("enemy_speed").forced_by_mod_id, "mod_c")
	assert_eq(registry.warnings.size(), 1)


func test_color_setting_from_lua() -> void:
	var source := """
		Settings.define({
			id = "interface_color",
			value_type = "color",
			default_value = {r = 1, g = 0, b = 0, a = 1}
		})
	"""

	assert_true(settings_state.execute(source, "mod_a"))

	var registry := settings_state.finish()
	assert_not_null(registry)
	if registry == null:
		return

	assert_eq(registry.get_effective_value("interface_color"), Color.RED)


func test_invalid_setting_rejects_stage() -> void:
	var source := """
		Settings.define({
			id = "invalid_setting",
			value_type = "int",
			default_value = "not_a_number"
		})
	"""

	assert_false(settings_state.execute(source, "mod_a"))

	var registry := settings_state.finish()
	assert_null(registry)


func test_unavailable_libraries() -> void:
	var source := """
		return type(os) == "nil"
			and type(io) == "nil"
			and type(debug) == "nil"
			and type(Node) == "nil"
			and type(Engine) == "nil"
			and type(require) == "nil"
	"""

	assert_true(settings_state.execute(source, "mod_a"))

	var registry := settings_state.finish()
	assert_not_null(registry)


func test_finish_disposes_lua_state() -> void:
	assert_true(settings_state.is_active())

	var registry := settings_state.finish()

	assert_not_null(registry)
	assert_false(settings_state.is_active())
	assert_false(settings_state.execute("return 1", "mod_a"))


func test_lua_utils_array_conversion() -> void:
	var lua_state := LuaState.new()
	lua_state.open_libraries(LuaState.LUA_BASE)

	var values = LuaUtils.to_lua_value(lua_state, ["slow", "normal", "fast"])
	lua_state.globals["values"] = values

	var result = lua_state.do_string("""
		return values[1] == "slow"
			and values[2] == "normal"
			and values[3] == "fast"
			and #values == 3
	""")

	assert_eq(result, true)
	
