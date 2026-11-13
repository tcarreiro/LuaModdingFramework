extends GutTest


func _create_setting() -> ModSetting:
	var setting := ModSetting.new()
	setting.id = "enemy_speed"
	setting.display_name = "Enemy Speed"
	setting.value_type = "string"
	setting.default_value = "normal"
	setting.allowed_values = ["slow", "normal", "fast"]
	return setting


func test_valid_setting() -> void:
	var setting := _create_setting()

	assert_eq(setting.validate(), "")
	assert_eq(setting.get_effective_value(), "normal")
	assert_false(setting.is_forced())


func test_missing_default_value() -> void:
	var setting := _create_setting()
	setting.default_value = null

	assert_false(setting.validate().is_empty())


func test_invalid_value_type() -> void:
	var setting := _create_setting()
	setting.value_type = "invalid"

	assert_false(setting.validate().is_empty())


func test_supported_types() -> void:
	var cases := [
		{"type": "bool", "value": true},
		{"type": "int", "value": 10},
		{"type": "double", "value": 1.5},
		{"type": "string", "value": "normal"},
		{"type": "color", "value": Color.RED}
	]

	for entry in cases:
		var setting := ModSetting.new()
		setting.id = "test_setting"
		setting.value_type = entry["type"]
		setting.default_value = entry["value"]

		assert_eq(setting.validate(), "", "Failed type: %s" % entry["type"])


func test_invalid_default_value_type() -> void:
	var setting := _create_setting()
	setting.default_value = 10

	assert_false(setting.validate().is_empty())


func test_allowed_values() -> void:
	var setting := _create_setting()

	assert_eq(setting.validate_value("fast"), "")
	assert_false(setting.validate_value("ultra_fast").is_empty())


func test_numeric_limits() -> void:
	var setting := ModSetting.new()
	setting.id = "enemy_count"
	setting.value_type = "int"
	setting.default_value = 10
	setting.minimum_value = 1
	setting.maximum_value = 100

	assert_eq(setting.validate(), "")
	assert_eq(setting.validate_value(50), "")
	assert_false(setting.validate_value(0).is_empty())
	assert_false(setting.validate_value(101).is_empty())


func test_invalid_numeric_range() -> void:
	var setting := ModSetting.new()
	setting.id = "enemy_count"
	setting.value_type = "int"
	setting.default_value = 10
	setting.minimum_value = 100
	setting.maximum_value = 1

	assert_false(setting.validate().is_empty())


func test_hidden_setting_does_not_force_value() -> void:
	var setting := _create_setting()
	setting.hidden = true

	assert_eq(setting.validate(), "")
	assert_false(setting.is_forced())
	assert_eq(setting.get_effective_value(), "normal")


func test_forced_value() -> void:
	var setting := _create_setting()
	setting.hidden = true
	setting.forced_value = "fast"

	assert_eq(setting.validate(), "")
	assert_true(setting.is_forced())
	assert_eq(setting.get_effective_value(), "fast")
	assert_eq(setting.default_value, "normal")


func test_forced_setting_must_be_hidden() -> void:
	var setting := _create_setting()
	setting.forced_value = "fast"

	assert_false(setting.validate().is_empty())


func test_invalid_forced_value() -> void:
	var setting := _create_setting()
	setting.hidden = true
	setting.forced_value = "ultra_fast"

	assert_false(setting.validate().is_empty())


func test_clone_is_independent() -> void:
	var setting := _create_setting()
	var cloned := setting.clone()

	cloned.default_value = "fast"
	cloned.allowed_values.append("ultra_fast")

	assert_eq(setting.default_value, "normal")
	assert_false(setting.allowed_values.has("ultra_fast"))
