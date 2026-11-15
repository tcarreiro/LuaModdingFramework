extends GutTest

const LOOT_SCRIPT = preload("res://example/content/content_loot.gd")
const STACK_SCRIPT = preload("res://example/content/content_item_stack.gd")
const CONTAINER_SCRIPT = preload("res://example/content/content_container.gd")

var types: ContentTypeRegistry
var state: ContentState


func before_each() -> void:
	types = ContentTypeRegistry.new()
	types.register_type("loot", LOOT_SCRIPT)
	types.register_struct("item-stack", STACK_SCRIPT)
	types.register_type("item-container", CONTAINER_SCRIPT)
	types.register_reference("item-stack", "item_id", "loot")

	state = ContentState.new(types)
	state.start()


func after_each() -> void:
	state.close()


func test_content_api_is_available() -> void:
	assert_true(state.execute("""
		assert(type(Content) == "table")
		assert(type(Content.raw) == "table")
		assert(type(Content.extend) == "function")
	""", "core"))


func test_register_template_from_json() -> void:
	var data := {
		"type": "loot",
		"id": "sword",
		"max_stack": 5
	}

	assert_true(state.define_from_json(data, "core"))
	assert_true(state.get_registry().has_template("loot", "sword"))

	assert_true(state.execute("""
		assert(Content.raw.loot.sword.max_stack == 5)
	""", "demo_a"))


func test_register_template_from_lua() -> void:
	assert_true(state.execute("""
		Content.extend({
			{type = "loot", id = "sword", max_stack = 10}
		})
	""", "core"))

	var registry := state.get_registry()

	assert_true(registry.has_template("loot", "sword"))
	assert_eq(registry.get_template("loot", "sword")["max_stack"], 10)


func test_lua_tables_are_shared_between_mods() -> void:
	assert_true(state.execute("""
		Content.extend({
			{type = "loot", id = "sword", max_stack = 1}
		})

		shared_sword = Content.raw.loot.sword
	""", "core"))

	assert_true(state.execute("""
		assert(shared_sword == Content.raw.loot.sword)
		shared_sword.max_stack = 25
		assert(Content.raw.loot.sword.max_stack == 25)
	""", "demo_a"))


func test_nested_struct_array_from_lua() -> void:
	assert_true(state.execute("""
		Content.extend({
			{
				type = "item-container",
				id = "starter_chest",
				capacity = 20,
				initial_items = {
					{item_id = "sword", amount = 3}
				}
			}
		})
	""", "core"))

	var data := state.get_registry().get_template("item-container", "starter_chest")

	assert_eq(data["initial_items"].size(), 1)
	assert_eq(data["initial_items"][0]["amount"], 3)


func test_duplicate_template_is_rejected() -> void:
	assert_true(state.execute("""
		Content.extend({
			{type = "loot", id = "sword", max_stack = 1}
		})
	""", "core"))

	assert_false(state.execute("""
		Content.extend({
			{type = "loot", id = "sword", max_stack = 10}
		})
	""", "demo_a"))

	assert_false(state.get_errors().is_empty())


func test_lua_syntax_error_is_reported() -> void:
	assert_false(state.execute("""
		Content.extend({
	""", "core", "core/content.lua"))

	assert_true(state.get_errors()[0].contains("core/content.lua"))


func test_restricted_lua_libraries() -> void:
	assert_true(state.execute("""
		assert(io == nil)
		assert(os == nil)
		assert(package == nil)
		assert(debug == nil)
	""", "core"))



func test_sync_direct_property_change() -> void:
	assert_true(state.execute("""
		Content.extend({
			{type = "loot", id = "sword", max_stack = 1}
		})
	""", "core"))

	assert_true(state.execute("""
		Content.raw.loot.sword.max_stack = 25
	""", "demo_a"))

	var registry := state.get_registry()

	assert_eq(registry.get_template("loot", "sword")["max_stack"], 25)
	assert_eq(registry.get_metadata("loot", "sword")["owner_mod_id"], "core")
	assert_eq(registry.get_metadata("loot", "sword")["last_modified_by"], "demo_a")


func test_sync_nested_struct_change() -> void:
	assert_true(state.execute("""
		Content.extend({
			{
				type = "item-container",
				id = "chest",
				initial_items = {
					{item_id = "sword", amount = 1}
				}
			}
		})
	""", "core"))

	assert_true(state.execute("""
		Content.raw["item-container"].chest.initial_items[1].amount = 10
	""", "demo_a"))

	var data := state.get_registry().get_template("item-container", "chest")

	assert_eq(data["initial_items"][0]["amount"], 10)


func test_sync_direct_template_creation() -> void:
	assert_true(state.execute("""
		Content.raw.loot = {
			sword = {
				type = "loot",
				id = "sword",
				max_stack = 5
			}
		}
	""", "demo_a"))

	var registry := state.get_registry()

	assert_true(registry.has_template("loot", "sword"))
	assert_eq(registry.get_metadata("loot", "sword")["owner_mod_id"], "demo_a")


func test_sync_direct_template_removal() -> void:
	assert_true(state.define_from_json({
		"type": "loot",
		"id": "sword",
		"max_stack": 1
	}, "core"))

	assert_true(state.execute("""
		Content.raw.loot.sword = nil
	""", "demo_a"))

	assert_false(state.get_registry().has_template("loot", "sword"))


func test_unchanged_template_preserves_metadata() -> void:
	assert_true(state.execute("""
		Content.extend({
			{type = "loot", id = "sword", max_stack = 1}
		})
	""", "core"))

	assert_true(state.execute("""
		assert(Content.raw.loot.sword.max_stack == 1)
	""", "demo_a"))

	var metadata := state.get_registry().get_metadata("loot", "sword")

	assert_eq(metadata["owner_mod_id"], "core")
	assert_eq(metadata["last_modified_by"], "core")


func test_sync_rejects_modified_identity() -> void:
	assert_true(state.execute("""
		Content.extend({
			{type = "loot", id = "sword", max_stack = 1}
		})
	""", "core"))

	assert_false(state.execute("""
		Content.raw.loot.sword.id = "another_sword"
	""", "demo_a"))

	assert_true(state.get_registry().has_template("loot", "sword"))
	assert_false(state.get_registry().has_template("loot", "another_sword"))


func test_sync_rejects_invalid_bucket() -> void:
	assert_false(state.execute("""
		Content.raw.loot = 123
	""", "core"))

	assert_false(state.get_errors().is_empty())


func test_sync_rejects_invalid_template_without_partial_changes() -> void:
	assert_true(state.execute("""
		Content.extend({
			{type = "loot", id = "sword", max_stack = 1}
		})
	""", "core"))

	assert_false(state.execute("""
		Content.raw.loot.sword.max_stack = 50
		Content.raw.loot.invalid = false
	""", "demo_a"))

	assert_eq(state.get_registry().get_template("loot", "sword")["max_stack"], 1)



func test_finish_returns_finalized_registry() -> void:
	assert_true(state.execute("""
		Content.extend({
			{type = "loot", id = "sword", max_stack = 5}
		})
	""", "core"))

	var registry := state.finish()

	assert_not_null(registry)
	assert_true(registry.is_finalized())
	assert_true(registry.has_template("loot", "sword"))
	assert_false(state.is_active())


func test_finish_normalizes_template_values() -> void:
	assert_true(state.define_from_json({
		"type": "loot",
		"id": "sword",
		"max_stack": 5.0
	}, "core"))

	var registry := state.finish()

	assert_not_null(registry)

	var template := registry.get_template("loot", "sword")
	assert_eq(typeof(template["max_stack"]), TYPE_INT)
	assert_eq(template["max_stack"], 5)


func test_finish_rejects_invalid_template() -> void:
	assert_true(state.execute("""
		Content.extend({
			{type = "loot", id = "sword", max_stack = "invalid"}
		})
	""", "core"))

	var registry := state.finish()

	assert_null(registry)
	assert_false(state.is_active())
	assert_false(state.get_errors().is_empty())


func test_finish_validates_nested_references() -> void:
	assert_true(state.execute("""
		Content.extend({
			{
				type = "item-container",
				id = "chest",
				initial_items = {
					{item_id = "missing_sword", amount = 1}
				}
			}
		})
	""", "core"))

	var registry := state.finish()

	assert_null(registry)
	assert_true(state.get_errors()[0].contains("initial_items[0].item_id"))


func test_finish_preserves_template_metadata() -> void:
	assert_true(state.execute("""
		Content.extend({
			{type = "loot", id = "sword", max_stack = 1}
		})
	""", "core"))

	assert_true(state.execute("""
		Content.raw.loot.sword.max_stack = 10
	""", "demo_a"))

	var registry := state.finish()

	assert_not_null(registry)

	var metadata := registry.get_metadata("loot", "sword")
	assert_eq(metadata["owner_mod_id"], "core")
	assert_eq(metadata["last_modified_by"], "demo_a")


func test_cannot_execute_after_finish() -> void:
	assert_not_null(state.finish())

	assert_false(state.execute("""
		Content.extend({
			{type = "loot", id = "sword"}
		})
	""", "core"))
