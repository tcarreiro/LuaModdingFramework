extends GutTest

const LOOT_SCRIPT = preload("res://example/content/content_loot.gd")
const STACK_SCRIPT = preload("res://example/content/content_item_stack.gd")
const CONTAINER_SCRIPT = preload("res://example/content/content_container.gd")

const PLAIN_STACK_SCRIPT = preload("res://example/content/content_plain_stack.gd")
const PLAIN_CONTAINER_SCRIPT = preload("res://example/content/content_plain_container.gd")

var content_types: ContentTypeRegistry
var validator: ContentValidator

func before_each() -> void:
	content_types = ContentTypeRegistry.new()
	content_types.register_type("loot", LOOT_SCRIPT)
	content_types.register_struct("item-stack", STACK_SCRIPT)
	content_types.register_type("item-container", CONTAINER_SCRIPT)
	content_types.register_reference("item-stack", "item_id", "loot")

	validator = ContentValidator.new(content_types)


func _validate_loot(data: Dictionary) -> String:
	if data.get("max_stack", 0) < 1:
		return "max_stack must be greater than zero."

	return ""


func test_valid_template() -> void:
	var data := {
		"type": "loot",
		"id": "bronze_gauntlet",
		"max_stack": 1,
		"weight": 2.5
	}

	assert_true(validator.validate("loot", data))
	assert_eq(validator.errors.size(), 0)


func test_valid_nested_struct_array() -> void:
	var data := {
		"type": "item-container",
		"id": "starter_chest",
		"capacity": 20,
		"initial_items": [
			{"item_id": "sword", "amount": 1},
			{"item_id": "potion", "amount": 5}
		]
	}

	assert_true(validator.validate("item-container", data))
	assert_eq(validator.errors.size(), 0)


func test_invalid_nested_property() -> void:
	var data := {
		"id": "starter_chest",
		"initial_items": [
			{"item_id": "sword", "amount": "five"}
		]
	}

	assert_false(validator.validate("item-container", data))
	assert_true(validator.errors[0].contains("initial_items[0].amount"))


func test_unknown_property() -> void:
	assert_false(validator.validate("loot", {"unknown": 123}))
	assert_true(validator.errors[0].contains("unknown"))


func test_invalid_template_type() -> void:
	assert_false(validator.validate("loot", {"type": "item-container"}))
	assert_true(validator.errors[0].contains("type"))


func test_missing_properties_are_allowed() -> void:
	assert_true(validator.validate("loot", {"id": "simple_item"}))

	var normalized := validator.get_normalized_data()
	assert_false(normalized.has("max_stack"))


func test_normalize_json_integer() -> void:
	var data := {"max_stack": 4.0}

	assert_true(validator.validate("loot", data))

	var normalized := validator.get_normalized_data()
	assert_eq(typeof(normalized["max_stack"]), TYPE_INT)
	assert_eq(normalized["max_stack"], 4)


func test_reject_fractional_integer() -> void:
	assert_false(validator.validate("loot", {"max_stack": 4.5}))


func test_integer_is_valid_float() -> void:
	assert_true(validator.validate("loot", {"weight": 2}))

	var normalized := validator.get_normalized_data()
	assert_eq(typeof(normalized["weight"]), TYPE_FLOAT)


func test_reject_invalid_array() -> void:
	assert_false(validator.validate("item-container", {
		"initial_items": "not_an_array"
	}))


func test_reject_invalid_struct_element() -> void:
	assert_false(validator.validate("item-container", {
		"initial_items": [123]
	}))


func test_validate_standalone_struct() -> void:
	assert_true(validator.validate_struct("item-stack", {
		"item_id": "sword",
		"amount": 5
	}))


func test_custom_validator() -> void:
	content_types.clear()
	content_types.register_type("loot", LOOT_SCRIPT, _validate_loot)

	assert_true(validator.validate("loot", {"max_stack": 5}))
	assert_false(validator.validate("loot", {"max_stack": 0}))
	assert_true(validator.errors[0].contains("max_stack"))


func test_failed_validation_has_no_normalized_data() -> void:
	assert_true(validator.validate("loot", {"max_stack": 1}))
	assert_false(validator.get_normalized_data().is_empty())

	assert_false(validator.validate("loot", {"max_stack": "invalid"}))
	assert_true(validator.get_normalized_data().is_empty())


func test_original_data_is_not_modified() -> void:
	var data := {"max_stack": 5.0}

	assert_true(validator.validate("loot", data))

	assert_eq(typeof(data["max_stack"]), TYPE_FLOAT)
	assert_eq(typeof(validator.get_normalized_data()["max_stack"]), TYPE_INT)


func test_reference_existence_is_not_checked_yet() -> void:
	assert_true(validator.validate_struct("item-stack", {
		"item_id": "item_that_does_not_exist",
		"amount": 1
	}))


func test_validate_explicit_struct_binding_without_class_name() -> void:
	content_types.register_struct("plain-stack", PLAIN_STACK_SCRIPT)
	content_types.register_type("plain-container", PLAIN_CONTAINER_SCRIPT)
	content_types.register_struct_binding("plain-container", "initial_items", "plain-stack")

	var valid_data := {
		"id": "starter",
		"initial_items": [
			{"item_id": "sword", "amount": 5}
		]
	}

	assert_true(validator.validate("plain-container", valid_data))

	var invalid_data := {
		"id": "starter",
		"initial_items": [
			{"item_id": "sword", "amount": "invalid"}
		]
	}

	assert_false(validator.validate("plain-container", invalid_data))
	assert_true(validator.errors[0].contains("initial_items[0].amount"))
