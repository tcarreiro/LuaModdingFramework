extends GutTest

const LOOT_SCRIPT = preload("res://example/content/content_loot.gd")
const EQUIPMENT_SCRIPT = preload("res://example/content/content_equipment.gd")
const GAUNTLET_SCRIPT = preload("res://example/content/content_gauntlet.gd")
const CARD_SCRIPT = preload("res://example/content/content_card.gd")
const STACK_SCRIPT = preload("res://example/content/content_item_stack.gd")
const CONTAINER_SCRIPT = preload("res://example/content/content_container.gd")

var types: ContentTypeRegistry


func before_each() -> void:
	types = ContentTypeRegistry.new()
	types.register_type("loot", LOOT_SCRIPT)
	types.register_type("equipment", EQUIPMENT_SCRIPT)
	types.register_type("gauntlet", GAUNTLET_SCRIPT)
	types.register_type("card", CARD_SCRIPT)


func _validate_loot(data: Dictionary) -> String:
	if data.get("max_stack", 1) < 1:
		return "max_stack must be positive."
	return ""


func _validate_gauntlet(data: Dictionary) -> String:
	if data.get("socket_count", 1) < 1:
		return "socket_count must be positive."
	return ""


func _gauntlet(id: String) -> Dictionary:
	return {"type": "gauntlet", "id": id, "max_stack": 1, "armor": 2, "socket_count": 1}


func test_infer_parent_without_class_name() -> void:
	assert_eq(types.get_parent_type("equipment"), "loot")
	assert_eq(types.get_parent_type("gauntlet"), "equipment")
	assert_eq(types.get_parent_type("card"), "loot")
	assert_true(types.validate_inheritance())


func test_parent_can_be_registered_after_child() -> void:
	var registry := ContentTypeRegistry.new()
	registry.register_type("gauntlet", GAUNTLET_SCRIPT)
	registry.register_type("loot", LOOT_SCRIPT)
	registry.register_type("equipment", EQUIPMENT_SCRIPT)
	assert_true(registry.validate_inheritance())
	assert_eq(registry.get_parent_type("gauntlet"), "equipment")


func test_declared_parent_is_supported() -> void:
	var registry := ContentTypeRegistry.new()
	registry.register_type("gauntlet", GAUNTLET_SCRIPT, Callable(), "equipment")
	registry.register_type("equipment", EQUIPMENT_SCRIPT, Callable(), "loot")
	registry.register_type("loot", LOOT_SCRIPT)
	assert_true(registry.validate_inheritance())
	assert_eq(registry.get_type_lineage("gauntlet"), ["loot", "equipment", "gauntlet"])


func test_inherited_property_metadata() -> void:
	var properties := types.get_properties("gauntlet")
	assert_true(properties.has("id"))
	assert_true(properties.has("max_stack"))
	assert_true(properties.has("weight"))
	assert_true(properties.has("armor"))
	assert_true(properties.has("socket_count"))
	assert_eq(properties["max_stack"]["type"], TYPE_INT)


func test_is_subtype_and_family() -> void:
	assert_true(types.is_subtype("gauntlet", "loot"))
	assert_true(types.is_subtype("gauntlet", "equipment"))
	assert_true(types.is_subtype("loot", "loot"))
	assert_false(types.is_subtype("card", "equipment"))
	assert_eq(types.get_derived_types("equipment"), ["equipment", "gauntlet"])
	assert_eq(types.get_root_type("gauntlet"), "loot")


func test_validator_accepts_inherited_properties() -> void:
	var validator := ContentValidator.new(types)
	assert_true(validator.validate("gauntlet", _gauntlet("bronze")))
	assert_false(validator.validate("gauntlet", {"type": "gauntlet", "id": "bronze", "unknown": 5}))


func test_parent_and_child_business_validators() -> void:
	types.clear()
	types.register_type("loot", LOOT_SCRIPT, _validate_loot)
	types.register_type("equipment", EQUIPMENT_SCRIPT)
	types.register_type("gauntlet", GAUNTLET_SCRIPT, _validate_gauntlet)
	var validator := ContentValidator.new(types)
	assert_false(validator.validate("gauntlet", {"type": "gauntlet", "id": "bronze", "max_stack": 0}))
	assert_true(validator.errors[0].contains("max_stack"))
	assert_false(validator.validate("gauntlet", {"type": "gauntlet", "id": "bronze", "socket_count": 0}))
	assert_true(validator.errors[0].contains("socket_count"))
	assert_true(validator.validate("gauntlet", _gauntlet("bronze")))


func test_polymorphic_reference_from_struct() -> void:
	types.register_struct("item-stack", STACK_SCRIPT)
	types.register_type("item-container", CONTAINER_SCRIPT)
	types.register_reference("item-stack", "item_id", "loot")
	var catalog := ContentRegistry.new(types)
	assert_true(catalog.register_template(_gauntlet("bronze"), "core"))
	assert_true(catalog.register_template({
		"type": "item-container", "id": "chest",
		"initial_items": [{"item_id": "bronze", "amount": 1}]
	}, "core"))
	assert_true(catalog.finalize())


func test_polymorphic_reference_still_rejects_missing_id() -> void:
	types.register_struct("item-stack", STACK_SCRIPT)
	types.register_type("item-container", CONTAINER_SCRIPT)
	types.register_reference("item-stack", "item_id", "loot")
	var catalog := ContentRegistry.new(types)
	catalog.register_template({
		"type": "item-container", "id": "chest",
		"initial_items": [{"item_id": "missing", "amount": 1}]
	}, "core")
	assert_false(catalog.finalize())
	assert_true(catalog.errors[0].contains("unknown Reference"))


func test_reference_binding_is_inherited() -> void:
	assert_true(types.register_reference("equipment", "material_id", "loot"))
	assert_eq(types.get_reference_target("gauntlet", "material_id"), "loot")
	var catalog := ContentRegistry.new(types)
	var data := _gauntlet("bronze")
	data["material_id"] = "missing"
	assert_true(catalog.register_template(data, "core"))
	assert_false(catalog.finalize())
	assert_true(catalog.errors[0].contains("material_id"))


func test_struct_binding_is_inherited() -> void:
	types.register_struct("item-stack", STACK_SCRIPT)
	assert_true(types.register_struct_binding("equipment", "attached_items", "item-stack"))
	assert_eq(types.get_struct_binding("gauntlet", "attached_items").get("struct_type"), "item-stack")


func test_query_family_does_not_change_exact_bucket() -> void:
	var catalog := ContentRegistry.new(types)
	catalog.register_template({"type": "loot", "id": "stone"}, "core")
	catalog.register_template(_gauntlet("bronze"), "core")
	catalog.register_template({"type": "card", "id": "evasion"}, "demo_a")
	assert_true(catalog.finalize())
	assert_eq(catalog.get_templates("loot").size(), 1)
	assert_eq(catalog.get_templates_in_family("loot").size(), 3)
	assert_eq(catalog.get_template_in_family("loot", "bronze")["type"], "gauntlet")


func test_duplicate_id_within_family_is_rejected() -> void:
	var catalog := ContentRegistry.new(types)
	catalog.register_template(_gauntlet("shared"), "core")
	catalog.register_template({"type": "card", "id": "shared"}, "core")
	assert_false(catalog.finalize())
	assert_true(catalog.errors[0].contains("Duplicate Template ID"))


func test_same_id_in_unrelated_family_is_allowed() -> void:
	types.register_type("item-container", CONTAINER_SCRIPT)
	var catalog := ContentRegistry.new(types)
	catalog.register_template(_gauntlet("shared"), "core")
	catalog.register_template({"type": "item-container", "id": "shared"}, "core")
	assert_true(catalog.finalize())


func test_unknown_explicit_parent_is_rejected_at_finalize() -> void:
	var registry := ContentTypeRegistry.new()
	assert_true(registry.register_type("gauntlet", GAUNTLET_SCRIPT, Callable(), "missing"))
	assert_false(registry.validate_inheritance())
	assert_true(registry.errors[0].contains("unknown parent"))


func test_explicit_cycle_is_rejected() -> void:
	var registry := ContentTypeRegistry.new()
	registry.register_type("loot", LOOT_SCRIPT, Callable(), "gauntlet")
	registry.register_type("gauntlet", GAUNTLET_SCRIPT, Callable(), "loot")
	assert_false(registry.validate_inheritance())
	assert_true(registry.errors[0].contains("cycle"))


func test_inherited_struct_binding_validates_nested_reference() -> void:
	types.register_struct("item-stack", STACK_SCRIPT)
	types.register_struct_binding("equipment", "attached_items", "item-stack")
	types.register_reference("item-stack", "item_id", "loot")
	var catalog := ContentRegistry.new(types)
	var data := _gauntlet("bronze")
	data["attached_items"] = [{"item_id": "missing", "amount": 1}]
	catalog.register_template(data, "core")
	assert_false(catalog.finalize())
	assert_true(catalog.errors[0].contains("attached_items[0].item_id"))


func test_content_state_can_register_derived_template_from_lua() -> void:
	var state := ContentState.new(types)
	state.start()
	assert_true(state.execute("""
		Content.extend({
			{type = "gauntlet", id = "bronze", max_stack = 1, armor = 2, socket_count = 1}
		})
	""", "core"))
	var catalog := state.finish()
	assert_not_null(catalog)
	if catalog != null:
		assert_eq(catalog.get_template_in_family("loot", "bronze")["type"], "gauntlet")
	state.close()
