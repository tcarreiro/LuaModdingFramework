extends GutTest

const TEST_ROOT := "user://lua_modder_settings_loader_tests"
const BUILTIN_PATH := TEST_ROOT + "/builtin"
const USER_PATH := TEST_ROOT + "/user"


func before_each() -> void:
	_delete_directory(TEST_ROOT)

	assert_eq(DirAccess.make_dir_recursive_absolute(BUILTIN_PATH), OK)
	assert_eq(DirAccess.make_dir_recursive_absolute(USER_PATH), OK)

	_create_mod("core")


func after_each() -> void:
	_delete_directory(TEST_ROOT)


func _create_mod(id: String, dependencies: Array[String] = []) -> void:
	var mod_path := BUILTIN_PATH.path_join(id)

	assert_eq(DirAccess.make_dir_recursive_absolute(mod_path), OK)

	var manifest := {
		"id": id,
		"version": "0.1.0",
		"game_version": "0.1",
		"display_name": id,
		"dependencies": dependencies
	}

	_write_file(id, "manifest.json", JSON.stringify(manifest))


func _write_file(mod_id: String, file_name: String, content: String) -> void:
	var path := BUILTIN_PATH.path_join(mod_id).path_join(file_name)
	var file := FileAccess.open(path, FileAccess.WRITE)

	assert_not_null(file)
	if file == null:
		return

	file.store_string(content)
	file.close()


func _delete_directory(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return

	var files := directory.get_files()
	var folders := directory.get_directories()
	directory = null

	for file_name in files:
		DirAccess.remove_absolute(path.path_join(file_name))

	for folder_name in folders:
		_delete_directory(path.path_join(folder_name))

	DirAccess.remove_absolute(path)


func _resolve_mods(ids: Array[String] = []) -> Array[ModManifest]:
	var manager := ModManager.new("0.1.0", BUILTIN_PATH, USER_PATH)
	manager.discover()

	assert_eq(manager.discovery_errors.size(), 0)

	var mods := manager.resolve(ids)
	assert_eq(manager.resolution_errors.size(), 0)

	return mods


func test_empty_settings_stage() -> void:
	var loader := SettingsLoader.new()
	var registry := loader.run(_resolve_mods())

	assert_not_null(registry)
	assert_eq(loader.errors.size(), 0)

	if registry != null:
		assert_eq(registry.get_all_settings().size(), 0)


func test_load_settings_json() -> void:
	var definitions := [
		{
			"id": "enemy_speed",
			"value_type": "string",
			"default_value": "normal",
			"allowed_values": ["slow", "normal", "fast"]
		},
		{
			"id": "random_events",
			"value_type": "bool",
			"default_value": true
		}
	]

	_write_file("core", "settings.json", JSON.stringify(definitions))

	var loader := SettingsLoader.new()
	var registry := loader.run(_resolve_mods())

	assert_not_null(registry)
	assert_eq(loader.errors.size(), 0)

	if registry == null:
		return

	assert_eq(registry.get_all_settings().size(), 2)
	assert_eq(registry.get_effective_value("enemy_speed"), "normal")
	assert_eq(registry.get_effective_value("random_events"), true)


func test_lua_can_modify_json_setting() -> void:
	var definitions := [{
		"id": "enemy_speed",
		"value_type": "string",
		"default_value": "normal",
		"allowed_values": ["slow", "normal", "fast"]
	}]

	_write_file("core", "settings.json", JSON.stringify(definitions))
	_write_file("core", "settings.lua", """
		local setting = Settings.get("enemy_speed")
		if setting ~= nil and setting.default_value == "normal" then
			Settings.update("enemy_speed", {default_value = "fast"})
		end
	""")

	var loader := SettingsLoader.new()
	var registry := loader.run(_resolve_mods())

	assert_not_null(registry)
	assert_eq(loader.errors.size(), 0)

	if registry != null:
		assert_eq(registry.get_effective_value("enemy_speed"), "fast")


func test_three_rounds_and_shared_lua_state() -> void:
	_create_mod("demo_a")

	_write_file("core", "settings.lua", """
		shared_speed = "fast"
	""")

	_write_file("demo_a", "settings.lua", """
		Settings.define({
			id = "enemy_speed",
			value_type = "string",
			default_value = "normal",
			allowed_values = {"slow", "normal", "fast"}
		})
	""")

	_write_file("core", "settings-updates.lua", """
		local setting = Settings.get("enemy_speed")
		if setting ~= nil then
			Settings.update("enemy_speed", {default_value = "slow"})
		end
	""")

	_write_file("demo_a", "settings-final-fixes.lua", """
		Settings.force("enemy_speed", shared_speed)
	""")

	var loader := SettingsLoader.new()
	var registry := loader.run(_resolve_mods(["demo_a"]))

	assert_not_null(registry)
	assert_eq(loader.errors.size(), 0)

	if registry == null:
		return

	var setting := registry.get_setting("enemy_speed")

	assert_eq(setting.default_value, "slow")
	assert_eq(setting.forced_value, "fast")
	assert_eq(setting.forced_by_mod_id, "demo_a")
	assert_true(setting.hidden)


func test_dependency_order_in_definitions_round() -> void:
	_create_mod("demo_a")
	_create_mod("demo_b", ["demo_a"])

	_write_file("demo_a", "settings.lua", """
		Settings.define({
			id = "enemy_speed",
			value_type = "string",
			default_value = "normal"
		})
	""")

	_write_file("demo_b", "settings.lua", """
		local setting = Settings.get("enemy_speed")
		if setting ~= nil then
			Settings.update("enemy_speed", {default_value = "fast"})
		end
	""")

	var loader := SettingsLoader.new()
	var registry := loader.run(_resolve_mods(["demo_b"]))

	assert_not_null(registry)
	assert_eq(loader.errors.size(), 0)

	if registry != null:
		assert_eq(registry.get_effective_value("enemy_speed"), "fast")
		assert_eq(registry.get_setting("enemy_speed").owner_mod_id, "demo_a")


func test_conflicting_forced_values() -> void:
	_create_mod("demo_a")
	_create_mod("demo_b", ["demo_a"])

	_write_file("core", "settings.lua", """
		Settings.define({
			id = "enemy_speed",
			value_type = "string",
			default_value = "normal",
			allowed_values = {"slow", "normal", "fast"}
		})
	""")

	_write_file("demo_a", "settings-updates.lua", """
		Settings.force("enemy_speed", "fast")
	""")

	_write_file("demo_b", "settings-final-fixes.lua", """
		Settings.force("enemy_speed", "slow")
	""")

	var loader := SettingsLoader.new()
	var registry := loader.run(_resolve_mods(["demo_b"]))

	assert_not_null(registry)
	assert_eq(loader.errors.size(), 0)
	assert_eq(loader.warnings.size(), 1)

	if registry != null:
		assert_eq(registry.get_effective_value("enemy_speed"), "slow")
		assert_eq(registry.get_setting("enemy_speed").forced_by_mod_id, "demo_b")


func test_color_setting_from_json() -> void:
	var definitions := [{
		"id": "interface_color",
		"value_type": "color",
		"default_value": {"r": 1, "g": 0, "b": 0}
	}]

	_write_file("core", "settings.json", JSON.stringify(definitions))

	var loader := SettingsLoader.new()
	var registry := loader.run(_resolve_mods())

	assert_not_null(registry)
	assert_eq(loader.errors.size(), 0)

	if registry != null:
		assert_eq(registry.get_effective_value("interface_color"), Color.RED)


func test_invalid_json_rejects_stage() -> void:
	_write_file("core", "settings.json", "{ invalid json")

	var loader := SettingsLoader.new()
	var registry := loader.run(_resolve_mods())

	assert_null(registry)
	assert_true(loader.errors.size() > 0)


func test_invalid_setting_rejects_stage() -> void:
	var definitions := [{
		"id": "invalid_setting",
		"value_type": "int",
		"default_value": "not_an_integer"
	}]

	_write_file("core", "settings.json", JSON.stringify(definitions))

	var loader := SettingsLoader.new()
	var registry := loader.run(_resolve_mods())

	assert_null(registry)
	assert_true(loader.errors.size() > 0)


func test_lua_error_rejects_stage() -> void:
	_write_file("core", "settings.lua", """
		error("Intentional test error")
	""")

	var loader := SettingsLoader.new()
	var registry := loader.run(_resolve_mods())

	assert_null(registry)
	assert_true(loader.errors.size() > 0)


func test_new_run_creates_new_registry() -> void:
	var definitions := [{
		"id": "enemy_speed",
		"value_type": "string",
		"default_value": "normal"
	}]

	_write_file("core", "settings.json", JSON.stringify(definitions))

	var loader := SettingsLoader.new()
	var first_registry := loader.run(_resolve_mods())

	assert_not_null(first_registry)
	if first_registry == null:
		return

	assert_true(first_registry.has_setting("enemy_speed"))

	var path := BUILTIN_PATH.path_join("core/settings.json")
	assert_eq(DirAccess.remove_absolute(path), OK)

	var second_registry := loader.run(_resolve_mods())

	assert_not_null(second_registry)
	if second_registry == null:
		return

	assert_false(second_registry.has_setting("enemy_speed"))
	assert_true(first_registry.has_setting("enemy_speed"))
