extends GutTest

const LOOT_SCRIPT = preload("res://example/content/content_loot.gd")
const STACK_SCRIPT = preload("res://example/content/content_item_stack.gd")
const CONTAINER_SCRIPT = preload("res://example/content/content_container.gd")

const PLAIN_STACK_SCRIPT = preload("res://example/content/content_plain_stack.gd")
const PLAIN_CONTAINER_SCRIPT = preload("res://example/content/content_plain_container.gd")

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



func test_resolve_struct_array_property() -> void:
	registry.register_struct("item-stack", STACK_SCRIPT)
	registry.register_type("item-container", CONTAINER_SCRIPT)

	var binding := registry.get_struct_binding("item-container", "initial_items")

	assert_eq(binding.get("struct_type"), "item-stack")
	assert_eq(binding.get("is_array"), true)


func test_struct_binding_requires_registered_struct() -> void:
	registry.register_type("item-container", CONTAINER_SCRIPT)

	var binding := registry.get_struct_binding("item-container", "initial_items")

	assert_true(binding.is_empty())


func test_primitive_property_has_no_struct_binding() -> void:
	registry.register_type("item-container", CONTAINER_SCRIPT)

	var binding := registry.get_struct_binding("item-container", "capacity")

	assert_true(binding.is_empty())


func test_explicit_struct_binding_without_class_name() -> void:
	assert_true(registry.register_type("plain-container", PLAIN_CONTAINER_SCRIPT))
	assert_true(registry.register_struct("plain-stack", PLAIN_STACK_SCRIPT))
	assert_true(registry.register_struct_binding("plain-container", "initial_items", "plain-stack"))
	assert_true(registry.validate_struct_bindings())

	var binding := registry.get_struct_binding("plain-container", "initial_items")

	assert_eq(binding["struct_type"], "plain-stack")
	assert_true(binding["is_array"])


func test_explicit_struct_binding_forward_reference() -> void:
	registry.register_type("plain-container", PLAIN_CONTAINER_SCRIPT)

	assert_true(registry.register_struct_binding("plain-container", "initial_items", "plain-stack"))

	registry.register_struct("plain-stack", PLAIN_STACK_SCRIPT)

	assert_true(registry.validate_struct_bindings())


func test_explicit_struct_binding_unknown_target() -> void:
	registry.register_type("plain-container", PLAIN_CONTAINER_SCRIPT)
	registry.register_struct_binding("plain-container", "initial_items", "missing")

	assert_false(registry.validate_struct_bindings())


func test_explicit_struct_binding_rejects_primitive() -> void:
	registry.register_type("plain-container", PLAIN_CONTAINER_SCRIPT)

	assert_false(registry.register_struct_binding("plain-container", "id", "plain-stack"))
