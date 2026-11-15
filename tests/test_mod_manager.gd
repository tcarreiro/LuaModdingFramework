extends GutTest

const TEST_ROOT := "user://lua_modder_gut_tests"

var _builtin_path := TEST_ROOT + "/builtin"
var _user_path := TEST_ROOT + "/user"


func before_each() -> void:
	_delete_directory(TEST_ROOT)

	assert_eq(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_builtin_path)), OK)
	assert_eq(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_user_path)), OK)

	_create_mod("core", [], "0.1.0")


func after_each() -> void:
	_delete_directory(TEST_ROOT)


func _create_mod(id: String, dependencies: Array[String] = [], version: String = "1.0.0", game_version: String = "0.1", in_user_mods: bool = false) -> void:
	var root_path := _user_path if in_user_mods else _builtin_path
	var mod_path := root_path.path_join(id)

	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(mod_path))
	assert_eq(error, OK)

	if error != OK:
		return

	var manifest := {
		"id": id,
		"version": version,
		"game_version": game_version,
		"display_name": id,
		"dependencies": dependencies
	}

	var file := FileAccess.open(mod_path.path_join("manifest.json"), FileAccess.WRITE)
	assert_not_null(file)

	if file == null:
		return

	file.store_string(JSON.stringify(manifest))
	file.close()


func _delete_directory(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return

	var files := directory.get_files()
	var folders := directory.get_directories()
	directory = null

	for file_name in files:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(file_name)))

	for folder_name in folders:
		_delete_directory(path.path_join(folder_name))

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _discover_manager(current_game_version: String = "0.1.0") -> ModManager:
	var manager := ModManager.new(current_game_version, _builtin_path, _user_path)
	manager.discover()
	return manager


func _get_mod_ids(mods: Array[ModManifest]) -> Array[String]:
	var ids: Array[String] = []

	for mod in mods:
		ids.append(mod.id)

	return ids


func test_discover_builtin_mods() -> void:
	_create_mod("demo_a")

	var manager := _discover_manager()

	assert_eq(manager.discovery_errors.size(), 0)
	assert_not_null(manager.get_manifest("core"))
	assert_not_null(manager.get_manifest("demo_a"))


func test_discover_user_mods() -> void:
	_create_mod("external_mod", [], "1.0.0", "0.1", true)

	var manager := _discover_manager()
	var manifest := manager.get_manifest("external_mod")

	assert_not_null(manifest)
	if manifest == null:
		return

	assert_eq(manifest.root_path, _user_path.path_join("external_mod"))


func test_required_dependencies_load_first() -> void:
	_create_mod("demo_a", ["core >= 0.1.0"])
	_create_mod("demo_b", ["demo_a >= 1.0.0"])

	var manager := _discover_manager()
	var ordered := manager.resolve(["demo_b"])

	assert_eq(manager.resolution_errors.size(), 0)
	assert_eq(_get_mod_ids(ordered), ["core", "demo_a", "demo_b"])


func test_core_is_implicitly_required() -> void:
	_create_mod("aaa_mod")

	var manager := _discover_manager()
	var ordered := manager.resolve(["aaa_mod"])

	assert_eq(manager.resolution_errors.size(), 0)
	assert_eq(_get_mod_ids(ordered), ["core", "aaa_mod"])


func test_optional_dependency_can_be_missing() -> void:
	_create_mod("consumer", ["? optional_mod"])

	var manager := _discover_manager()
	var ordered := manager.resolve(["consumer"])

	assert_eq(manager.resolution_errors.size(), 0)
	assert_eq(_get_mod_ids(ordered), ["core", "consumer"])


func test_optional_dependency_affects_order_when_enabled() -> void:
	_create_mod("consumer", ["? library >= 1.0.0"])
	_create_mod("library")

	var manager := _discover_manager()
	var ordered := manager.resolve(["consumer", "library"])

	assert_eq(manager.resolution_errors.size(), 0)
	assert_eq(_get_mod_ids(ordered), ["core", "library", "consumer"])


func test_missing_required_dependency() -> void:
	_create_mod("consumer", ["missing_library"])

	var manager := _discover_manager()
	var ordered := manager.resolve(["consumer"])

	assert_true(ordered.is_empty())
	assert_true(manager.resolution_errors.size() > 0)


func test_incompatible_mods() -> void:
	_create_mod("demo_a", ["! demo_b"])
	_create_mod("demo_b")

	var manager := _discover_manager()
	var ordered := manager.resolve(["demo_a", "demo_b"])

	assert_true(ordered.is_empty())
	assert_true(manager.resolution_errors.size() > 0)


func test_optional_dependency_version_mismatch() -> void:
	_create_mod("consumer", ["? library >= 2.0.0"])
	_create_mod("library", [], "1.0.0")

	var manager := _discover_manager()
	var ordered := manager.resolve(["consumer", "library"])

	assert_true(ordered.is_empty())
	assert_true(manager.resolution_errors.size() > 0)


func test_no_order_dependency() -> void:
	_create_mod("a_consumer", ["~ z_library"])
	_create_mod("z_library")

	var manager := _discover_manager()
	var ordered := manager.resolve(["a_consumer"])

	assert_eq(manager.resolution_errors.size(), 0)
	assert_eq(_get_mod_ids(ordered), ["core", "a_consumer", "z_library"])


func test_circular_dependencies() -> void:
	_create_mod("demo_a", ["demo_b"])
	_create_mod("demo_b", ["demo_a"])

	var manager := _discover_manager()
	var ordered := manager.resolve(["demo_a"])

	assert_true(ordered.is_empty())
	assert_true(manager.resolution_errors.size() > 0)


func test_incompatible_game_version() -> void:
	_create_mod("demo_a", [], "1.0.0", "0.2")

	var manager := _discover_manager("0.1.0")
	var ordered := manager.resolve(["demo_a"])

	assert_true(ordered.is_empty())
	assert_true(manager.resolution_errors.size() > 0)


func test_compatible_game_patch_version() -> void:
	_create_mod("demo_a", [], "1.0.0", "0.1")

	var manager := _discover_manager("0.1.99")
	var ordered := manager.resolve(["demo_a"])

	assert_eq(manager.resolution_errors.size(), 0)
	assert_eq(_get_mod_ids(ordered), ["core", "demo_a"])


func test_duplicated_mod_id() -> void:
	_create_mod("demo_a")
	_create_mod("demo_a", [], "1.0.0", "0.1", true)

	var manager := _discover_manager()
	var ordered := manager.resolve(["demo_a"])

	assert_true(manager.discovery_errors.size() > 0)
	assert_true(manager.resolution_errors.size() > 0)
	assert_true(ordered.is_empty())


func test_invalid_manifest_version() -> void:
	_create_mod("demo_a", [], "invalid")

	var manager := _discover_manager()

	assert_true(manager.discovery_errors.size() > 0)
	assert_null(manager.get_manifest("demo_a"))


func test_missing_core() -> void:
	_delete_directory(_builtin_path.path_join("core"))

	var manager := _discover_manager()
	var ordered := manager.resolve([])

	assert_true(manager.discovery_errors.size() > 0)
	assert_true(manager.resolution_errors.size() > 0)
	assert_true(ordered.is_empty())


func test_versioned_mod_folder() -> void:
	_create_mod("demo_a")

	var original_path := _builtin_path.path_join("demo_a")
	var versioned_path := _builtin_path.path_join("demo_a_1.0.0")
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(original_path), ProjectSettings.globalize_path(versioned_path))

	assert_eq(error, OK)

	var manager := _discover_manager()

	assert_eq(manager.discovery_errors.size(), 0)
	assert_not_null(manager.get_manifest("demo_a"))


func test_invalid_mod_folder_name() -> void:
	_create_mod("demo_a")

	var original_path := _builtin_path.path_join("demo_a")
	var invalid_path := _builtin_path.path_join("wrong_name")
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(original_path), ProjectSettings.globalize_path(invalid_path))

	assert_eq(error, OK)

	var manager := _discover_manager()

	assert_true(manager.discovery_errors.size() > 0)
	assert_null(manager.get_manifest("demo_a"))
