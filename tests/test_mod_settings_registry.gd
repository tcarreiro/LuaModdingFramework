extends GutTest

var registry: SettingsRegistry


func before_each() -> void:
	registry = SettingsRegistry.new()


func _create_setting(id: String = "enemy_speed") -> ModSetting:
	var setting := ModSetting.new()
	setting.id = id
	setting.display_name = "Enemy Speed"
	setting.value_type = "string"
	setting.default_value = "normal"
	setting.allowed_values = ["slow", "normal", "fast"]
	return setting


func test_register_setting() -> void:
	var setting := _create_setting()

	assert_true(registry.register(setting, "mod_a"))
	assert_true(registry.has_setting("enemy_speed"))
	assert_eq(registry.get_setting("enemy_speed").owner_mod_id, "mod_a")


func test_duplicate_setting_is_rejected() -> void:
	assert_true(registry.register(_create_setting(), "mod_a"))
	assert_false(registry.register(_create_setting(), "mod_b"))

	assert_eq(registry.errors.size(), 1)
	assert_eq(registry.get_setting("enemy_speed").owner_mod_id, "mod_a")


func test_invalid_setting_is_rejected() -> void:
	var setting := _create_setting()
	setting.default_value = 123

	assert_false(registry.register(setting, "mod_a"))
	assert_false(registry.has_setting("enemy_speed"))


func test_another_mod_can_update_setting() -> void:
	registry.register(_create_setting(), "mod_a")

	var result := registry.update("enemy_speed", {
		"default_value": "fast",
		"description": "Modified enemy speed"
	}, "mod_b")

	assert_true(result)

	var setting := registry.get_setting("enemy_speed")
	assert_eq(setting.default_value, "fast")
	assert_eq(setting.owner_mod_id, "mod_a")
	assert_eq(setting.last_modified_by, "mod_b")


func test_force_setting() -> void:
	registry.register(_create_setting(), "mod_a")

	assert_true(registry.force("enemy_speed", "fast", "mod_b"))

	var setting := registry.get_setting("enemy_speed")

	assert_true(setting.hidden)
	assert_true(setting.is_forced())
	assert_eq(setting.forced_value, "fast")
	assert_eq(setting.forced_by_mod_id, "mod_b")
	assert_eq(registry.get_effective_value("enemy_speed"), "fast")


func test_hidden_settings_are_excluded_from_ui() -> void:
	registry.register(_create_setting("enemy_speed"), "mod_a")
	registry.register(_create_setting("enemy_count"), "mod_a")

	registry.force("enemy_speed", "fast", "mod_b")

	var visible := registry.get_visible_settings()

	assert_eq(visible.size(), 1)
	assert_eq(visible[0].id, "enemy_count")
	assert_eq(registry.get_all_settings().size(), 2)


func test_conflicting_forced_values() -> void:
	registry.register(_create_setting(), "mod_a")

	assert_true(registry.force("enemy_speed", "fast", "mod_b"))
	assert_true(registry.force("enemy_speed", "slow", "mod_c"))

	assert_eq(registry.get_effective_value("enemy_speed"), "slow")
	assert_eq(registry.get_setting("enemy_speed").forced_by_mod_id, "mod_c")
	assert_eq(registry.warnings.size(), 1)
	assert_true(registry.warnings[0].contains("mod_b"))
	assert_true(registry.warnings[0].contains("mod_c"))


func test_same_forced_value_does_not_warn() -> void:
	registry.register(_create_setting(), "mod_a")

	registry.force("enemy_speed", "fast", "mod_b")
	registry.force("enemy_speed", "fast", "mod_c")

	assert_eq(registry.warnings.size(), 0)
	assert_eq(registry.get_setting("enemy_speed").forced_by_mod_id, "mod_c")


func test_invalid_force_does_not_modify_setting() -> void:
	registry.register(_create_setting(), "mod_a")

	assert_false(registry.force("enemy_speed", "ultra_fast", "mod_b"))

	var setting := registry.get_setting("enemy_speed")

	assert_false(setting.is_forced())
	assert_false(setting.hidden)
	assert_eq(registry.get_effective_value("enemy_speed"), "normal")
	assert_eq(registry.errors.size(), 1)


func test_invalid_update_is_atomic() -> void:
	registry.register(_create_setting(), "mod_a")

	var result := registry.update("enemy_speed", {
		"default_value": "invalid",
		"description": "Should not be applied"
	}, "mod_b")

	assert_false(result)

	var setting := registry.get_setting("enemy_speed")
	assert_eq(setting.default_value, "normal")
	assert_eq(setting.description, "")
	assert_eq(setting.last_modified_by, "mod_a")


func test_unknown_property_is_rejected() -> void:
	registry.register(_create_setting(), "mod_a")

	assert_false(registry.update("enemy_speed", {"owner_mod_id": "mod_b"}, "mod_b"))
	assert_eq(registry.get_setting("enemy_speed").owner_mod_id, "mod_a")


func test_setting_cannot_be_modified_by_reference() -> void:
	registry.register(_create_setting(), "mod_a")

	var setting := registry.get_setting("enemy_speed")
	setting.default_value = "fast"
	setting.allowed_values.clear()

	var original := registry.get_setting("enemy_speed")

	assert_eq(original.default_value, "normal")
	assert_eq(original.allowed_values.size(), 3)


func test_player_cannot_change_forced_setting() -> void:
	registry.register(_create_setting(), "mod_a")
	registry.force("enemy_speed", "fast", "mod_b")

	assert_false(registry.validate_player_value("enemy_speed", "slow").is_empty())


func test_player_cannot_change_hidden_setting() -> void:
	registry.register(_create_setting(), "mod_a")
	registry.update("enemy_speed", {"hidden": true}, "mod_b")

	assert_false(registry.validate_player_value("enemy_speed", "normal").is_empty())


func test_player_value_validation() -> void:
	registry.register(_create_setting(), "mod_a")

	assert_eq(registry.validate_player_value("enemy_speed", "fast"), "")
	assert_false(registry.validate_player_value("enemy_speed", "invalid").is_empty())


func test_remove_forced_value() -> void:
	registry.register(_create_setting(), "mod_a")
	registry.force("enemy_speed", "fast", "mod_b")

	var result := registry.update("enemy_speed", {
		"forced_value": null,
		"hidden": false
	}, "mod_c")

	assert_true(result)

	var setting := registry.get_setting("enemy_speed")
	assert_false(setting.is_forced())
	assert_false(setting.hidden)
	assert_eq(setting.get_effective_value(), "normal")


func test_clear_registry() -> void:
	registry.register(_create_setting(), "mod_a")
	registry.force("enemy_speed", "invalid", "mod_b")

	registry.clear()

	assert_false(registry.has_setting("enemy_speed"))
	assert_eq(registry.get_all_settings().size(), 0)
	assert_eq(registry.errors.size(), 0)
	assert_eq(registry.warnings.size(), 0)
