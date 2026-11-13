
extends GutTest


func test_valid_versions() -> void:
	assert_true(ModVersion.is_valid("0.1.0"))
	assert_true(ModVersion.is_valid("1.10.25"))
	assert_true(ModVersion.is_valid("65535.65535.65535"))


func test_invalid_versions() -> void:
	assert_false(ModVersion.is_valid(""))
	assert_false(ModVersion.is_valid("1.2"))
	assert_false(ModVersion.is_valid("1.2.3.4"))
	assert_false(ModVersion.is_valid("1.2.a"))
	assert_false(ModVersion.is_valid("-1.2.3"))
	assert_false(ModVersion.is_valid("1.2.65536"))


func test_version_comparison() -> void:
	assert_eq(ModVersion.compare("1.10.0", "1.9.0"), 1)
	assert_eq(ModVersion.compare("1.2.0", "1.3.0"), -1)
	assert_eq(ModVersion.compare("1.2.5", "1.2.5"), 0)
	assert_eq(ModVersion.compare("2.0.0", "1.99.99"), 1)


func test_version_constraints() -> void:
	assert_true(ModVersion.satisfies("1.5.0", ">=", "1.2.0"))
	assert_true(ModVersion.satisfies("1.5.0", "<", "2.0.0"))
	assert_true(ModVersion.satisfies("1.5.0", "=", "1.5.0"))
	assert_false(ModVersion.satisfies("1.5.0", "<", "1.2.0"))
	assert_false(ModVersion.satisfies("1.5.0", ">", "2.0.0"))
	assert_true(ModVersion.satisfies("1.5.0", "", ""))


func test_compatibility_line() -> void:
	assert_true(ModVersion.is_compatibility_line("0.1"))
	assert_true(ModVersion.is_compatibility_line("2.5"))
	assert_false(ModVersion.is_compatibility_line("0.1.0"))
	assert_false(ModVersion.is_compatibility_line("0"))


func test_game_version_compatibility() -> void:
	assert_true(ModVersion.matches_game_version("0.1.0", "0.1"))
	assert_true(ModVersion.matches_game_version("0.1.99", "0.1"))
	assert_false(ModVersion.matches_game_version("0.2.0", "0.1"))
	assert_false(ModVersion.matches_game_version("1.0.0", "0.1"))
