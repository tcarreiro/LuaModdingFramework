extends GutTest

var registry: RuntimeApiRegistry


func before_each() -> void:
	registry = RuntimeApiRegistry.new()


func _get_health() -> int:
	return 75


func _get_level() -> int:
	return 12


func _give_item(_item_id: String, _quantity: int) -> bool:
	return true


func test_register_root_function() -> void:
	assert_true(registry.register_function("", "get_health", _get_health))

	assert_true(registry.has_function("", "get_health"))
	assert_eq(registry.get_function("", "get_health").call(), 75)
	assert_eq(registry.get_functions().size(), 1)


func test_register_namespaced_functions() -> void:
	assert_true(registry.register_function("player", "get_health", _get_health))
	assert_true(registry.register_function("inventory", "give_item", _give_item))

	assert_true(registry.has_function("player", "get_health"))
	assert_true(registry.has_function("inventory", "give_item"))

	assert_eq(registry.get_function("player", "get_health").call(), 75)
	assert_true(registry.get_function("inventory", "give_item").call("bronze_gauntlet", 1))

	assert_eq(registry.get_functions().size(), 2)


func test_register_nested_namespace() -> void:
	assert_true(registry.register_function("player.stats", "get_level", _get_level))
	assert_true(registry.register_function("player", "get_health", _get_health))

	assert_true(registry.has_function("player.stats", "get_level"))
	assert_true(registry.has_function("player", "get_health"))

	assert_eq(registry.get_function("player.stats", "get_level").call(), 12)
	assert_eq(registry.get_functions().size(), 2)


func test_reject_duplicate_function() -> void:
	assert_true(registry.register_function("player", "get_health", _get_health))

	assert_false(registry.register_function("player", "get_health", _get_level))

	assert_eq(registry.get_functions().size(), 1)
	assert_eq(registry.get_function("player", "get_health").call(), 75)
	assert_eq(registry.errors.size(), 1)


func test_reject_function_namespace_conflict() -> void:
	assert_true(registry.register_function("", "player", _get_health))

	assert_false(registry.register_function("player", "get_level", _get_level))

	assert_eq(registry.get_functions().size(), 1)
	assert_false(registry.has_function("player", "get_level"))

	var other := RuntimeApiRegistry.new()

	assert_true(other.register_function("player", "get_health", _get_health))
	assert_false(other.register_function("", "player", _get_level))

	assert_eq(other.get_functions().size(), 1)


func test_reject_invalid_identifiers() -> void:
	assert_false(registry.register_function("123player", "get_health", _get_health))
	assert_false(registry.register_function("player..stats", "get_health", _get_health))
	assert_false(registry.register_function("player", "get-health", _get_health))
	assert_false(registry.register_function("player", "function", _get_health))
	assert_false(registry.register_function("player", "", _get_health))

	assert_true(registry.get_functions().is_empty())
	assert_eq(registry.errors.size(), 5)


func test_reject_invalid_callable() -> void:
	assert_false(registry.register_function("player", "get_health", Callable()))

	assert_false(registry.has_function("player", "get_health"))
	assert_false(registry.errors.is_empty())


func test_registry_cannot_be_modified_through_result() -> void:
	assert_true(registry.register_function("player", "get_health", _get_health))

	var functions := registry.get_functions()
	functions.clear()

	assert_true(registry.has_function("player", "get_health"))
	assert_eq(registry.get_functions().size(), 1)


func test_clear_registry() -> void:
	assert_true(registry.register_function("player", "get_health", _get_health))
	assert_false(registry.register_function("player", "get_health", _get_level))

	assert_false(registry.errors.is_empty())

	registry.clear()

	assert_true(registry.get_functions().is_empty())
	assert_true(registry.errors.is_empty())
	assert_false(registry.has_function("player", "get_health"))
