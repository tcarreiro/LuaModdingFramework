extends GutTest

const TEST_ROOT := "user://lua_modder_runtime_manager_tests"
const BUILTIN_PATH := TEST_ROOT + "/builtin"
const USER_PATH := TEST_ROOT + "/user"

var runtime: RuntimeManager
var lifecycle_calls: Array[String] = []


func before_each() -> void:
	_delete_directory(TEST_ROOT)
	assert_eq(DirAccess.make_dir_recursive_absolute(BUILTIN_PATH), OK)
	assert_eq(DirAccess.make_dir_recursive_absolute(USER_PATH), OK)
	_create_mod("core")
	runtime = RuntimeManager.new()
	lifecycle_calls.clear()


func after_each() -> void:
	runtime.close()
	_delete_directory(TEST_ROOT)


func _create_mod(id: String, dependencies: Array[String] = []) -> void:
	var mod_path := BUILTIN_PATH.path_join(id)
	assert_eq(DirAccess.make_dir_recursive_absolute(mod_path), OK)
	_write_file(id, "manifest.json", JSON.stringify({
		"id": id,
		"version": "0.1.0",
		"game_version": "0.1",
		"display_name": id,
		"dependencies": dependencies
	}))


func _write_file(mod_id: String, file_name: String, content: String) -> void:
	var path := BUILTIN_PATH.path_join(mod_id).path_join(file_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	if file == null:
		return
	file.store_string(content)
	file.close()


func _resolve_mods(ids: Array[String] = []) -> Array[ModManifest]:
	var mod_manager := ModManager.new("0.1.0", BUILTIN_PATH, USER_PATH)
	mod_manager.discover()
	assert_eq(mod_manager.discovery_errors.size(), 0)
	var mods := mod_manager.resolve(ids)
	assert_eq(mod_manager.resolution_errors.size(), 0)
	return mods


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


func _get_test_value() -> int:
	return 42


func test_initial_phase() -> void:
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.CREATED)
	assert_null(runtime.get_state("core"))


func test_rejects_empty_mod_list() -> void:
	assert_false(runtime.prepare([]))
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)
	assert_false(runtime.get_errors().is_empty())


func test_mod_without_control_does_not_create_a_state() -> void:
	assert_true(runtime.prepare(_resolve_mods()))
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.PREPARED)
	assert_true(runtime.get_mod_ids().is_empty())
	assert_null(runtime.get_state("core"))
	assert_true(runtime.activate())
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.ACTIVE)
	assert_null(runtime.get_state("core"))


func test_control_has_no_game_during_setup() -> void:
	_write_file("core", "control.lua", """
		assert(game == nil)
		assert(script ~= nil)
		assert(mods.core == "0.1.0")
	""")
	assert_true(runtime.prepare(_resolve_mods()))
	assert_eq(runtime.get_mod_ids(), ["core"])
	assert_null(runtime.get_state("core"))
	assert_true(runtime.activate({"get_test_value": _get_test_value}))
	var state := runtime.get_state("core")
	assert_not_null(state)
	if state != null:
		assert_eq(state.get_phase(), RuntimeState.Phase.ACTIVE)


func test_all_mods_share_versions_but_not_lua_globals() -> void:
	_create_mod("demo_a")
	_write_file("core", "control.lua", """
		assert(mods.demo_a == "0.1.0")
		only_core = 123
	""")
	_write_file("demo_a", "control.lua", """
		assert(mods.core == "0.1.0")
		assert(only_core == nil)
		only_demo_a = 456
	""")
	assert_true(runtime.prepare(_resolve_mods(["demo_a"])))
	assert_eq(runtime.get_mod_ids(), ["core", "demo_a"])
	assert_true(runtime.activate())
	assert_not_null(runtime.get_state("core"))
	assert_not_null(runtime.get_state("demo_a"))


func test_dependency_order_is_preserved() -> void:
	_create_mod("demo_a")
	_create_mod("demo_b", ["demo_a"])
	for mod_id in ["core", "demo_a", "demo_b"]:
		_write_file(mod_id, "control.lua", "assert(game == nil)")
	assert_true(runtime.prepare(_resolve_mods(["demo_b"])))
	assert_eq(runtime.get_mod_ids(), ["core", "demo_a", "demo_b"])


func test_mod_without_control_is_still_listed_in_mod_versions() -> void:
	_create_mod("demo_a")
	_write_file("core", "control.lua", """
		assert(mods.demo_a == "0.1.0")
	""")
	assert_true(runtime.prepare(_resolve_mods(["demo_a"])))
	assert_eq(runtime.get_mod_ids(), ["core"])


func test_registers_lifecycle_callbacks_before_activation() -> void:
	_write_file("core", "control.lua", """
		script.on_init(function() end)
		script.on_load(function() end)
	""")
	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate())
	var state := runtime.get_state("core")
	assert_not_null(state)
	if state != null:
		assert_true(state.has_lifecycle_handler("on_init"))
		assert_true(state.has_lifecycle_handler("on_load"))


func test_invalid_lua_aborts_all_states() -> void:
	_create_mod("demo_a")
	_write_file("core", "control.lua", "only_core = true")
	_write_file("demo_a", "control.lua", "error('expected failure')")
	assert_false(runtime.prepare(_resolve_mods(["demo_a"])))
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)
	assert_true(runtime.get_mod_ids().is_empty())
	assert_null(runtime.get_state("core"))
	assert_false(runtime.activate())
	assert_false(runtime.get_errors().is_empty())


func test_api_replacement_aborts_preparation() -> void:
	_write_file("core", "control.lua", "script.on_init = function() end")
	assert_false(runtime.prepare(_resolve_mods()))
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)


func test_rejects_duplicate_manifest_ids() -> void:
	var mods := _resolve_mods()
	mods.append(mods[0])
	assert_false(runtime.prepare(mods))
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)


func test_cannot_activate_before_all_controls_are_prepared() -> void:
	assert_false(runtime.activate())
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.CREATED)


func test_invalid_game_api_is_rejected_before_activation() -> void:
	_write_file("core", "control.lua", "assert(game == nil)")
	assert_true(runtime.prepare(_resolve_mods()))
	assert_false(runtime.activate({"bad_function": 123}))
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.PREPARED)
	assert_null(runtime.get_state("core"))
	assert_true(runtime.activate({"get_test_value": _get_test_value}))
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.ACTIVE)


func test_cannot_prepare_twice() -> void:
	assert_true(runtime.prepare(_resolve_mods()))
	assert_false(runtime.prepare(_resolve_mods()))
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.PREPARED)


func test_cannot_activate_twice() -> void:
	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate())
	assert_false(runtime.activate())
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.ACTIVE)


func test_close_releases_all_states() -> void:
	_write_file("core", "control.lua", "assert(game == nil)")
	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate())
	assert_not_null(runtime.get_state("core"))
	runtime.close()
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.CLOSED)
	assert_null(runtime.get_state("core"))
	assert_true(runtime.get_mod_ids().is_empty())


func test_loader_rejects_oversized_control() -> void:
	_write_file("core", "control.lua", "-".repeat(RuntimeLoader.MAX_CONTROL_FILE_BYTES + 1))
	assert_false(runtime.prepare(_resolve_mods()))
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)
	assert_true(runtime.get_errors()[0].contains("exceeds"))


func _record_lifecycle_call(name: String) -> void:
	lifecycle_calls.append(name)


func test_new_game_runs_on_init_with_game_access() -> void:
	_write_file("core", "control.lua", """
		assert(game == nil)
		script.on_init(function()
			assert(game ~= nil)
			game.record("init:core")
		end)
		script.on_load(function() error("on_load must not run") end)
	""")
	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate({"record": _record_lifecycle_call}))
	assert_eq(lifecycle_calls, ["init:core"])


func test_loaded_mod_runs_on_load_without_game() -> void:
	_write_file("core", "control.lua", """
		script.on_init(function() error("on_init must not run") end)
		script.on_load(function()
			assert(game == nil)
			was_loaded = true
		end)
		script.on_configuration_changed(function(data)
			assert(was_loaded == true)
			assert(game ~= nil)
			game.record("loaded:core")
		end)
	""")
	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate({"record": _record_lifecycle_call}, ["core"], {}))
	assert_eq(lifecycle_calls, ["loaded:core"])


func test_mixed_existing_and_new_mods_get_different_callbacks() -> void:
	_create_mod("demo_a")
	_write_file("core", "control.lua", """
		script.on_init(function() error("core is not new") end)
		script.on_load(function()
			assert(game == nil)
			was_loaded = true
		end)
		script.on_configuration_changed(function(data)
			assert(was_loaded)
			game.record("config:core")
		end)
	""")
	_write_file("demo_a", "control.lua", """
		script.on_init(function()
			game.record("init:demo_a")
		end)
		script.on_load(function() error("demo_a is new") end)
		script.on_configuration_changed(function(data)
			game.record("config:demo_a")
		end)
	""")
	assert_true(runtime.prepare(_resolve_mods(["demo_a"])))
	assert_true(runtime.activate({"record": _record_lifecycle_call}, ["core"], {"mod_changes": {}}))
	assert_eq(lifecycle_calls, ["init:demo_a", "config:core", "config:demo_a"])


func test_configuration_changed_receives_consumer_data() -> void:
	_write_file("core", "control.lua", """
		script.on_configuration_changed(function(data)
			assert(data.mod_startup_settings_changed == true)
			assert(data.mod_changes.demo_a.new_version == "0.1.0")
			game.record("configuration")
		end)
	""")
	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate({"record": _record_lifecycle_call}, [], {
		"mod_startup_settings_changed": true,
		"mod_changes": {"demo_a": {"new_version": "0.1.0"}}
	}))
	assert_eq(lifecycle_calls, ["configuration"])


func test_configuration_changed_is_not_called_implicitly() -> void:
	_write_file("core", "control.lua", """
		script.on_configuration_changed(function(data)
			error("Unexpected configuration change")
		end)
	""")
	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate())
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.ACTIVE)


func test_on_init_failure_aborts_runtime() -> void:
	_write_file("core", "control.lua", """
		script.on_init(function() error("intentional lifecycle failure") end)
	""")
	assert_true(runtime.prepare(_resolve_mods()))
	assert_false(runtime.activate())
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)
	assert_null(runtime.get_state("core"))
	assert_true(str(runtime.get_errors()).contains("intentional lifecycle failure"))


func test_on_load_cannot_define_game() -> void:
	_write_file("core", "control.lua", """
		script.on_load(function()
			assert(game == nil)
			game = {}
		end)
	""")
	assert_true(runtime.prepare(_resolve_mods()))
	assert_false(runtime.activate({}, ["core"]))
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)
	assert_true(str(runtime.get_errors()).contains("defined game during on_load"))


func test_on_init_cannot_replace_game() -> void:
	_write_file("core", "control.lua", """
		script.on_init(function() game = {} end)
	""")
	assert_true(runtime.prepare(_resolve_mods()))
	assert_false(runtime.activate())
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)
	assert_true(str(runtime.get_errors()).contains("replaced the game API"))


func test_configuration_failure_aborts_all_states() -> void:
	_create_mod("demo_a")
	_write_file("core", "control.lua", """
		script.on_configuration_changed(function(data)
			error("configuration failed")
		end)
	""")
	_write_file("demo_a", "control.lua", """
		script.on_configuration_changed(function(data)
			game.record("should_not_run")
		end)
	""")
	assert_true(runtime.prepare(_resolve_mods(["demo_a"])))
	assert_false(runtime.activate({"record": _record_lifecycle_call}, [], {}))
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)
	assert_true(lifecycle_calls.is_empty())


func test_invalid_change_data_keeps_runtime_prepared() -> void:
	_write_file("core", "control.lua", "assert(game == nil)")
	assert_true(runtime.prepare(_resolve_mods()))
	assert_false(runtime.activate({}, [], "invalid"))
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.PREPARED)
	assert_true(runtime.activate())
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.ACTIVE)


func test_on_init_cannot_replace_script_api() -> void:
	_write_file("core", "control.lua", """
		script.on_init(function() script.on_init = function() end end)
	""")
	assert_true(runtime.prepare(_resolve_mods()))
	assert_false(runtime.activate())
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)
	assert_true(str(runtime.get_errors()).contains("replaced script.on_init"))


func test_lifecycle_uses_execution_guard() -> void:
	_write_file("core", "control.lua", """
		script.on_init(function()
			while true do end
		end)
	""")
	assert_true(runtime.prepare(_resolve_mods()))
	assert_false(runtime.activate())
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)
	assert_true(str(runtime.get_errors()).contains("on_init"))


func test_lifecycle_does_not_create_internal_globals() -> void:
	_write_file("core", "control.lua", """
		assert(__lua_modder_lifecycle_callback == nil)
		assert(__lua_modder_lifecycle_data == nil)

		script.on_init(function()
			assert(__lua_modder_lifecycle_callback == nil)
			assert(__lua_modder_lifecycle_data == nil)
			game.record("initialized")
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate({"record": _record_lifecycle_call}))
	assert_eq(lifecycle_calls, ["initialized"])
