extends GutTest

const LOOT_SCRIPT = preload("res://example/content/content_loot.gd")
const STACK_SCRIPT = preload("res://example/content/content_item_stack.gd")
const CONTAINER_SCRIPT = preload("res://example/content/content_container.gd")

var registry: ContentTypeRegistry


func before_each() -> void:
	registry = ContentTypeRegistry.new()


func _validate_loot(data: Dictionary) -> String:
	if data.get("max_stack", 0) < 1:
		return "max_stack must be greater than zero."

	return ""


func test_register_definition() -> void:
	assert_true(registry.register_type("loot", LOOT_SCRIPT))
	assert_true(registry.has_type("loot"))
	assert_false(registry.has_struct("loot"))
	assert_eq(registry.get_registered_script("loot"), LOOT_SCRIPT)


func test_register_struct() -> void:
	assert_true(registry.register_struct("item-stack", STACK_SCRIPT))
	assert_true(registry.has_struct("item-stack"))
	assert_false(registry.has_type("item-stack"))


func test_inspect_definition_properties() -> void:
	registry.register_type("loot", LOOT_SCRIPT)

	var properties := registry.get_properties("loot")

	assert_true(properties.has("id"))
	assert_true(properties.has("max_stack"))
	assert_true(properties.has("weight"))

	assert_eq(properties["id"]["type"], TYPE_STRING)
	assert_eq(properties["max_stack"]["type"], TYPE_INT)
	assert_eq(properties["weight"]["type"], TYPE_FLOAT)


func test_inspect_struct_array() -> void:
	registry.register_type("item-container", CONTAINER_SCRIPT)
	registry.register_struct("item-stack", STACK_SCRIPT)

	var properties := registry.get_properties("item-container")

	assert_true(properties.has("initial_items"))
	assert_eq(properties["initial_items"]["type"], TYPE_ARRAY)


func test_internal_properties_are_not_exposed() -> void:
	registry.register_type("loot", LOOT_SCRIPT)

	var properties := registry.get_properties("loot")

	assert_false(properties.has("_runtime_cache"))


func test_get_properties_returns_copy() -> void:
	registry.register_type("loot", LOOT_SCRIPT)

	var properties := registry.get_properties("loot")
	var property_data: Dictionary = properties["max_stack"]

	property_data["type"] = TYPE_STRING

	var original := registry.get_properties("loot")
	assert_eq(original["max_stack"]["type"], TYPE_INT)


func test_duplicate_type_is_rejected() -> void:
	assert_true(registry.register_type("loot", LOOT_SCRIPT))
	assert_false(registry.register_struct("loot", STACK_SCRIPT))

	assert_eq(registry.errors.size(), 1)
	assert_true(registry.has_type("loot"))


func test_register_reference() -> void:
	registry.register_struct("item-stack", STACK_SCRIPT)
	registry.register_type("loot", LOOT_SCRIPT)

	assert_true(registry.register_reference("item-stack", "item_id", "loot"))
	assert_true(registry.validate_references())
	assert_eq(registry.get_reference_target("item-stack", "item_id"), "loot")


func test_forward_reference() -> void:
	registry.register_struct("item-stack", STACK_SCRIPT)

	assert_true(registry.register_reference("item-stack", "item_id", "loot"))

	registry.register_type("loot", LOOT_SCRIPT)

	assert_true(registry.validate_references())


func test_missing_reference_target() -> void:
	registry.register_struct("item-stack", STACK_SCRIPT)
	registry.register_reference("item-stack", "item_id", "missing-type")

	assert_false(registry.validate_references())
	assert_true(registry.errors.size() > 0)


func test_reference_requires_string_property() -> void:
	registry.register_struct("item-stack", STACK_SCRIPT)

	assert_false(registry.register_reference("item-stack", "amount", "loot"))
	assert_true(registry.errors.size() > 0)


func test_reference_requires_existing_property() -> void:
	registry.register_struct("item-stack", STACK_SCRIPT)

	assert_false(registry.register_reference("item-stack", "unknown", "loot"))


func test_optional_validator() -> void:
	registry.register_type("loot", LOOT_SCRIPT)

	assert_eq(registry.validate_custom("loot", {"max_stack": 0}), "")


func test_custom_validator() -> void:
	registry.register_type("loot", LOOT_SCRIPT, _validate_loot)

	assert_eq(registry.validate_custom("loot", {"max_stack": 10}), "")

	var error := registry.validate_custom("loot", {"max_stack": 0})

	assert_false(error.is_empty())
	assert_true(error.contains("max_stack"))


func test_invalid_type_id() -> void:
	assert_false(registry.register_type("invalid type", LOOT_SCRIPT))
	assert_false(registry.has_type("invalid type"))


func test_clear_registry() -> void:
	registry.register_type("loot", LOOT_SCRIPT)
	registry.register_struct("item-stack", STACK_SCRIPT)

	registry.clear()

	assert_false(registry.has_type("loot"))
	assert_false(registry.has_struct("item-stack"))
	assert_eq(registry.errors.size(), 0)
