extends GutTest

const TEST_ROOT := "user://lua_modder_content_loader_tests"
const BUILTIN_PATH := TEST_ROOT + "/builtin"
const USER_PATH := TEST_ROOT + "/user"

const LOOT_SCRIPT = preload("res://example/content/content_loot.gd")
const STACK_SCRIPT = preload("res://example/content/content_item_stack.gd")
const CONTAINER_SCRIPT = preload("res://example/content/content_container.gd")

var types: ContentTypeRegistry


func before_each() -> void:
	_delete_directory(TEST_ROOT)

	assert_eq(DirAccess.make_dir_recursive_absolute(BUILTIN_PATH), OK)
	assert_eq(DirAccess.make_dir_recursive_absolute(USER_PATH), OK)

	_create_mod("core")

	types = ContentTypeRegistry.new()
	types.register_type("loot", LOOT_SCRIPT)
	types.register_struct("item-stack", STACK_SCRIPT)
	types.register_type("item-container", CONTAINER_SCRIPT)
	types.register_reference("item-stack", "item_id", "loot")


func after_each() -> void:
	_delete_directory(TEST_ROOT)


func _create_mod(id: String, dependencies: Array[String] = []) -> void:
	var path := BUILTIN_PATH.path_join(id)

	assert_eq(DirAccess.make_dir_recursive_absolute(path), OK)

	var manifest := {
		"id": id,
		"version": "0.1.0",
		"game_version": "0.1",
		"display_name": id,
		"dependencies": dependencies
	}

	_write_file(id, "manifest.json", JSON.stringify(manifest))


func _write_file(mod_id: String, relative_path: String, content: String) -> void:
	var path := BUILTIN_PATH.path_join(mod_id).path_join(relative_path)

	assert_eq(DirAccess.make_dir_recursive_absolute(path.get_base_dir()), OK)

	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)

	if file == null:
		return

	file.store_string(content)
	file.close()


func _delete_directory(path: String) -> void:
	var directory := DirAccess.open(path)

	if directory == null:
		return

	var files := directory.get_files()
	var folders := directory.get_directories()
	directory = null

	for file_name in files:
		DirAccess.remove_absolute(path.path_join(file_name))

	for folder_name in folders:
		_delete_directory(path.path_join(folder_name))

	DirAccess.remove_absolute(path)


func _resolve_mods(ids: Array[String] = []) -> Array[ModManifest]:
	var manager := ModManager.new("0.1.0", BUILTIN_PATH, USER_PATH)
	manager.discover()

	assert_eq(manager.discovery_errors.size(), 0)

	var mods := manager.resolve(ids)
	assert_eq(manager.resolution_errors.size(), 0)

	return mods


func _loot(id: String, max_stack: Variant = 1) -> Dictionary:
	return {
		"type": "loot",
		"id": id,
		"max_stack": max_stack
	}


func test_empty_content_stage() -> void:
	var loader := ContentLoader.new(types)
	var registry := loader.run(_resolve_mods())

	assert_not_null(registry)
	assert_eq(loader.errors.size(), 0)

	if registry != null:
		assert_true(registry.is_finalized())
		assert_true(registry.get_catalog().is_empty())


func test_load_content_json_recursively() -> void:
	_write_file("core", "content/loot/items.json", JSON.stringify([
		_loot("sword"),
		_loot("shield")
	]))

	_write_file("core", "content/loot/rare/items.json", JSON.stringify([
		_loot("rare_sword")
	]))

	var loader := ContentLoader.new(types)
	var registry := loader.run(_resolve_mods())

	assert_not_null(registry)

	if registry == null:
		return

	assert_eq(registry.get_templates("loot").size(), 3)
	assert_true(registry.has_template("loot", "rare_sword"))


func test_content_lua_can_modify_json() -> void:
	_write_file("core", "content/items.json", JSON.stringify([
		_loot("sword")
	]))

	_write_file("core", "content.lua", """
		Content.raw.loot.sword.max_stack = 10
	""")

	var loader := ContentLoader.new(types)
	var registry := loader.run(_resolve_mods())

	assert_not_null(registry)

	if registry != null:
		assert_eq(registry.get_template("loot", "sword")["max_stack"], 10)


func test_lua_only_mod() -> void:
	_write_file("core", "content.lua", """
		Content.extend({
			{type = "loot", id = "sword", max_stack = 5}
		})
	""")

	var loader := ContentLoader.new(types)
	var registry := loader.run(_resolve_mods())

	assert_not_null(registry)

	if registry != null:
		assert_eq(registry.get_template("loot", "sword")["max_stack"], 5)


func test_three_rounds_and_shared_lua_state() -> void:
	_create_mod("demo_a")

	_write_file("core", "content.lua", """
		shared_stack_bonus = 3

		Content.extend({
			{type = "loot", id = "sword", max_stack = 1}
		})
	""")

	_write_file("demo_a", "content.lua", """
		Content.extend({
			{type = "loot", id = "shield", max_stack = 2}
		})
	""")

	_write_file("core", "content-updates.lua", """
		Content.raw.loot.shield.max_stack = 5
	""")

	_write_file("demo_a", "content-updates.lua", """
		Content.raw.loot.sword.max_stack = shared_stack_bonus + 3
	""")

	_write_file("core", "content-final-fixes.lua", """
		Content.raw.loot.shield.max_stack = 9
	""")

	var loader := ContentLoader.new(types)
	var registry := loader.run(_resolve_mods(["demo_a"]))

	assert_not_null(registry)
	assert_eq(loader.errors.size(), 0)

	if registry == null:
		return

	assert_eq(registry.get_template("loot", "sword")["max_stack"], 6)
	assert_eq(registry.get_template("loot", "shield")["max_stack"], 9)

	assert_eq(registry.get_metadata("loot", "sword")["last_modified_by"], "demo_a")
	assert_eq(registry.get_metadata("loot", "shield")["last_modified_by"], "core")


func test_dependency_order() -> void:
	_create_mod("demo_a")
	_create_mod("demo_b", ["demo_a"])

	_write_file("demo_a", "content.lua", """
		Content.extend({
			{type = "loot", id = "sword", max_stack = 1}
		})
	""")

	_write_file("demo_b", "content.lua", """
		Content.raw.loot.sword.max_stack = 20
	""")

	var loader := ContentLoader.new(types)
	var registry := loader.run(_resolve_mods(["demo_b"]))

	assert_not_null(registry)

	if registry != null:
		assert_eq(registry.get_template("loot", "sword")["max_stack"], 20)


func test_startup_settings_and_mod_versions() -> void:
	_create_mod("demo_a")

	_write_file("core", "content.lua", """
		assert(mods["demo_a"] == "0.1.0")

		Content.extend({
			{
				type = "loot",
				id = "sword",
				max_stack = settings.startup.enemy_count.value
			}
		})
	""")

	var loader := ContentLoader.new(types)
	var registry := loader.run(_resolve_mods(["demo_a"]), {
		"enemy_count": 7
	})

	assert_not_null(registry)

	if registry != null:
		assert_eq(registry.get_template("loot", "sword")["max_stack"], 7)


func test_invalid_json_rejects_stage() -> void:
	_write_file("core", "content/items.json", "{ invalid json")

	var loader := ContentLoader.new(types)
	var registry := loader.run(_resolve_mods())

	assert_null(registry)
	assert_false(loader.errors.is_empty())


func test_invalid_json_root_rejects_stage() -> void:
	_write_file("core", "content/items.json", JSON.stringify(_loot("sword")))

	var loader := ContentLoader.new(types)
	var registry := loader.run(_resolve_mods())

	assert_null(registry)
	assert_true(loader.errors[0].contains("array"))


func test_invalid_template_rejects_stage() -> void:
	_write_file("core", "content/items.json", JSON.stringify([
		_loot("sword", "invalid")
	]))

	var loader := ContentLoader.new(types)
	var registry := loader.run(_resolve_mods())

	assert_null(registry)
	assert_false(loader.errors.is_empty())


func test_lua_error_rejects_stage() -> void:
	_write_file("core", "content.lua", """
		error("Intentional test error")
	""")

	var loader := ContentLoader.new(types)
	var registry := loader.run(_resolve_mods())

	assert_null(registry)
	assert_false(loader.errors.is_empty())


func test_missing_reference_rejects_stage() -> void:
	_write_file("core", "content/containers.json", JSON.stringify([
		{
			"type": "item-container",
			"id": "chest",
			"initial_items": [
				{"item_id": "missing_sword", "amount": 1}
			]
		}
	]))

	var loader := ContentLoader.new(types)
	var registry := loader.run(_resolve_mods())

	assert_null(registry)
	assert_false(loader.errors.is_empty())


func test_later_mod_can_fix_invalid_template() -> void:
	_create_mod("demo_a")

	_write_file("core", "content/items.json", JSON.stringify([
		_loot("sword", "invalid")
	]))

	_write_file("demo_a", "content-final-fixes.lua", """
		Content.raw.loot.sword.max_stack = 5
	""")

	var loader := ContentLoader.new(types)
	var registry := loader.run(_resolve_mods(["demo_a"]))

	assert_not_null(registry)

	if registry != null:
		assert_eq(registry.get_template("loot", "sword")["max_stack"], 5)


func test_new_run_creates_new_registry() -> void:
	_write_file("core", "content/items.json", JSON.stringify([
		_loot("sword")
	]))

	var loader := ContentLoader.new(types)
	var first_registry := loader.run(_resolve_mods())

	assert_not_null(first_registry)

	if first_registry == null:
		return

	var path := BUILTIN_PATH.path_join("core/content/items.json")
	assert_eq(DirAccess.remove_absolute(path), OK)

	var second_registry := loader.run(_resolve_mods())

	assert_not_null(second_registry)

	if second_registry != null:
		assert_false(second_registry.has_template("loot", "sword"))
		assert_true(first_registry.has_template("loot", "sword"))


func test_empty_mod_list_is_rejected() -> void:
	var loader := ContentLoader.new(types)
	var registry := loader.run([])

	assert_null(registry)
	assert_false(loader.errors.is_empty())
