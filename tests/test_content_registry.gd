extends GutTest

const LOOT_SCRIPT = preload("res://example/content/content_loot.gd")
const STACK_SCRIPT = preload("res://example/content/content_item_stack.gd")
const CONTAINER_SCRIPT = preload("res://example/content/content_container.gd")

var content_types: ContentTypeRegistry
var registry: ContentRegistry


func before_each() -> void:
	content_types = ContentTypeRegistry.new()
	content_types.register_type("loot", LOOT_SCRIPT)
	content_types.register_struct("item-stack", STACK_SCRIPT)
	content_types.register_type("item-container", CONTAINER_SCRIPT)
	content_types.register_reference("item-stack", "item_id", "loot")

	registry = ContentRegistry.new(content_types)


func _loot(id: String, stack: Variant = 1) -> Dictionary:
	return {
		"type": "loot",
		"id": id,
		"max_stack": stack
	}


func _container(item_id: String) -> Dictionary:
	return {
		"type": "item-container",
		"id": "starter_chest",
		"capacity": 20,
		"initial_items": [
			{"item_id": item_id, "amount": 1}
		]
	}


func _validate_loot(data: Dictionary) -> String:
	if data.get("max_stack", 1) < 1:
		return "max_stack must be positive."
	return ""


func test_register_template() -> void:
	assert_true(registry.register_template(_loot("sword"), "core"))
	assert_true(registry.has_template("loot", "sword"))
	assert_eq(registry.get_template("loot", "sword")["max_stack"], 1)


func test_extend_multiple_templates() -> void:
	assert_true(registry.extend([
		_loot("sword"),
		_loot("shield"),
		_loot("potion")
	], "core"))

	assert_eq(registry.get_templates("loot").size(), 3)


func test_extend_is_atomic() -> void:
	assert_false(registry.extend([
		_loot("sword"),
		{"type": "unknown", "id": "invalid"}
	], "core"))

	assert_false(registry.has_template("loot", "sword"))


func test_duplicate_template_is_rejected() -> void:
	registry.register_template(_loot("sword"), "core")

	assert_false(registry.register_template(_loot("sword"), "demo_a"))
	assert_eq(registry.get_metadata("loot", "sword")["owner_mod_id"], "core")


func test_same_id_in_different_types() -> void:
	assert_true(registry.register_template(_loot("starter"), "core"))

	assert_true(registry.register_template({
		"type": "item-container",
		"id": "starter"
	}, "core"))

	assert_true(registry.has_template("loot", "starter"))
	assert_true(registry.has_template("item-container", "starter"))


func test_get_template_returns_deep_copy() -> void:
	registry.register_template(_container("sword"), "core")

	var data := registry.get_template("item-container", "starter_chest")
	data["initial_items"][0]["amount"] = 99

	var original := registry.get_template("item-container", "starter_chest")
	assert_eq(original["initial_items"][0]["amount"], 1)


func test_get_catalog_returns_deep_copy() -> void:
	registry.register_template(_loot("sword"), "core")

	var catalog := registry.get_catalog()
	catalog["loot"]["sword"]["max_stack"] = 99

	assert_eq(registry.get_template("loot", "sword")["max_stack"], 1)


func test_update_records_last_modifier() -> void:
	registry.register_template(_loot("sword"), "core")

	assert_true(registry.update("loot", "sword", {
		"max_stack": 10
	}, "demo_a"))

	assert_eq(registry.get_template("loot", "sword")["max_stack"], 10)

	var metadata := registry.get_metadata("loot", "sword")
	assert_eq(metadata["owner_mod_id"], "core")
	assert_eq(metadata["last_modified_by"], "demo_a")


func test_update_merges_nested_dictionaries() -> void:
	var data := _loot("sword")
	data["attributes"] = {
		"damage": 5,
		"range": 2
	}

	registry.register_template(data, "core")
	registry.update("loot", "sword", {
		"attributes": {
			"damage": 10
		}
	}, "demo_a")

	var updated := registry.get_template("loot", "sword")
	assert_eq(updated["attributes"]["damage"], 10)
	assert_eq(updated["attributes"]["range"], 2)


func test_update_replaces_arrays() -> void:
	registry.register_template(_container("sword"), "core")

	registry.update("item-container", "starter_chest", {
		"initial_items": [
			{"item_id": "potion", "amount": 3}
		]
	}, "demo_a")

	var items: Array = registry.get_template("item-container", "starter_chest")["initial_items"]
	assert_eq(items.size(), 1)
	assert_eq(items[0]["item_id"], "potion")


func test_identity_cannot_be_updated() -> void:
	registry.register_template(_loot("sword"), "core")

	assert_false(registry.update("loot", "sword", {
		"id": "new_sword"
	}, "demo_a"))

	assert_true(registry.has_template("loot", "sword"))
	assert_false(registry.has_template("loot", "new_sword"))


func test_replace_preserves_original_owner() -> void:
	registry.register_template(_loot("sword"), "core")

	assert_true(registry.replace("loot", "sword", _loot("sword", 50), "demo_a"))

	assert_eq(registry.get_template("loot", "sword")["max_stack"], 50)

	var metadata := registry.get_metadata("loot", "sword")
	assert_eq(metadata["owner_mod_id"], "core")
	assert_eq(metadata["last_modified_by"], "demo_a")


func test_remove_template() -> void:
	registry.register_template(_loot("sword"), "core")

	assert_true(registry.remove("loot", "sword", "demo_a"))
	assert_false(registry.has_template("loot", "sword"))
	assert_true(registry.get_metadata("loot", "sword").is_empty())


func test_finalize_normalizes_and_locks() -> void:
	registry.register_template(_loot("sword", 5.0), "core")

	assert_true(registry.finalize())
	assert_true(registry.is_finalized())

	var data := registry.get_template("loot", "sword")
	assert_eq(typeof(data["max_stack"]), TYPE_INT)
	assert_eq(data["max_stack"], 5)

	assert_false(registry.update("loot", "sword", {
		"max_stack": 10
	}, "demo_a"))


func test_finalize_is_atomic_on_validation_failure() -> void:
	registry.register_template(_loot("valid", 5.0), "core")
	registry.register_template(_loot("invalid", "bad"), "core")

	assert_false(registry.finalize())
	assert_false(registry.is_finalized())

	var original := registry.get_template("loot", "valid")
	assert_eq(typeof(original["max_stack"]), TYPE_FLOAT)
	assert_true(registry.errors.size() > 0)


func test_finalize_rejects_missing_reference() -> void:
	registry.register_template(_container("missing_sword"), "core")

	assert_false(registry.finalize())
	assert_true(registry.errors[0].contains("initial_items[0].item_id"))


func test_finalize_accepts_existing_reference() -> void:
	registry.register_template(_container("sword"), "core")
	registry.register_template(_loot("sword"), "demo_a")

	assert_true(registry.finalize())


func test_temporary_invalid_data_can_be_fixed_by_another_mod() -> void:
	registry.register_template(_loot("sword", "invalid"), "core")

	assert_true(registry.update("loot", "sword", {
		"max_stack": 5
	}, "demo_a"))

	assert_true(registry.finalize())


func test_custom_validator_runs_during_finalize() -> void:
	content_types.clear()
	content_types.register_type("loot", LOOT_SCRIPT, _validate_loot)
	registry = ContentRegistry.new(content_types)

	registry.register_template(_loot("sword", 0), "core")

	assert_false(registry.finalize())
	assert_true(registry.errors[0].contains("max_stack"))


func test_registration_requires_mod_id() -> void:
	assert_false(registry.register_template(_loot("sword"), ""))
	assert_false(registry.has_template("loot", "sword"))
