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


func _record_lifecycle_call(p_name: String) -> void:
	lifecycle_calls.append(p_name)



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


func test_storage_is_saved_and_restored_before_on_load() -> void:
	_write_file("core", "control.lua", """
		assert(storage.expeditions == nil)

		script.on_init(function()
			storage.expeditions = 17
		end)

		script.on_load(function()
			assert(game == nil)
			assert(storage.expeditions == 17)
		end)

		script.on_configuration_changed(function()
			game.record("restored:" .. storage.expeditions)
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate())

	var saved_storage := runtime.snapshot_storage()

	assert_true(saved_storage.has("core"))

	runtime.close()
	runtime = RuntimeManager.new()

	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate(
		{"record": _record_lifecycle_call},
		["core"],
		{},
		saved_storage
	))

	assert_eq(lifecycle_calls, ["restored:17"])


func test_on_load_cannot_modify_storage() -> void:
	_write_file("core", "control.lua", """
		script.on_init(function()
			storage.value = 10
		end)

		script.on_load(function()
			storage.value = 20
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate())

	var saved_storage := runtime.snapshot_storage()

	runtime.close()
	runtime = RuntimeManager.new()

	assert_true(runtime.prepare(_resolve_mods()))
	assert_false(runtime.activate({}, ["core"], null, saved_storage))

	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)
	assert_true(str(runtime.get_errors()).contains("modified storage during on_load"))


func test_storage_is_isolated_between_mods() -> void:
	_create_mod("demo_a")

	_write_file("core", "control.lua", """
		script.on_init(function()
			storage.owner = "core"
		end)
	""")

	_write_file("demo_a", "control.lua", """
		assert(storage.owner == nil)

		script.on_init(function()
			assert(storage.owner == nil)
			storage.owner = "demo_a"
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods(["demo_a"])))
	assert_true(runtime.activate())

	var saved_storage := runtime.snapshot_storage()

	assert_true(saved_storage.has("core"))
	assert_true(saved_storage.has("demo_a"))
	assert_ne(saved_storage["core"], saved_storage["demo_a"])


func test_events_follow_mod_order() -> void:
	_create_mod("demo_a")

	_write_file("core", "control.lua", """
		script.on_event("run_started", function(event)
			game.record("core")
		end)
	""")

	_write_file("demo_a", "control.lua", """
		script.on_event("run_started", function(event)
			game.record("demo_a")
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods(["demo_a"])))
	assert_true(runtime.activate({"record": _record_lifecycle_call}))
	assert_true(runtime.emit_event("run_started"))

	assert_eq(lifecycle_calls, ["core", "demo_a"])


func test_registering_again_replaces_handler() -> void:
	_write_file("core", "control.lua", """
		script.on_event("test_event", function(event)
			game.record("first")
		end)

		script.on_event("test_event", function(event)
			game.record("second")
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate({"record": _record_lifecycle_call}))
	assert_true(runtime.emit_event("test_event"))

	assert_eq(lifecycle_calls, ["second"])


func test_nil_unregisters_event_handler() -> void:
	_write_file("core", "control.lua", """
		script.on_event("test_event", function(event)
			game.record("unexpected")
		end)

		script.on_event("test_event", nil)
	""")

	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate({"record": _record_lifecycle_call}))
	assert_true(runtime.emit_event("test_event"))

	assert_true(lifecycle_calls.is_empty())


func test_handler_can_subscribe_to_multiple_events() -> void:
	_write_file("core", "control.lua", """
		script.on_event({"run_started", "run_finished"}, function(event)
			game.record(event.name)
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate({"record": _record_lifecycle_call}))

	assert_true(runtime.emit_event("run_started"))
	assert_true(runtime.emit_event("run_finished"))

	assert_eq(lifecycle_calls, ["run_started", "run_finished"])


func test_on_load_can_register_event_handlers() -> void:
	_write_file("core", "control.lua", """
		script.on_load(function()
			assert(game == nil)

			script.on_event("loaded_event", function(event)
				game.record("restored_handler")
			end)
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate(
		{"record": _record_lifecycle_call},
		["core"]
	))

	assert_true(runtime.emit_event("loaded_event"))
	assert_eq(lifecycle_calls, ["restored_handler"])


func test_on_init_can_register_event_handlers() -> void:
	_write_file("core", "control.lua", """
		script.on_init(function()
			script.on_event("initialized_event", function(event)
				game.record("initialized_handler")
			end)
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate({"record": _record_lifecycle_call}))
	assert_true(runtime.emit_event("initialized_event"))

	assert_eq(lifecycle_calls, ["initialized_handler"])


func test_event_payload_is_isolated_between_mods() -> void:
	_create_mod("demo_a")

	_write_file("core", "control.lua", """
		script.on_event("test_event", function(event)
			event.nested.score = 999
			game.record("core")
		end)
	""")

	_write_file("demo_a", "control.lua", """
		script.on_event("test_event", function(event)
			assert(event.nested.score == 7)
			game.record("demo_a")
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods(["demo_a"])))
	assert_true(runtime.activate({"record": _record_lifecycle_call}))

	assert_true(runtime.emit_event("test_event", {
		"nested": {"score": 7}
	}))

	assert_eq(lifecycle_calls, ["core", "demo_a"])


func test_event_handler_failure_aborts_runtime() -> void:
	_write_file("core", "control.lua", """
		script.on_event("test_event", function(event)
			error("intentional event failure")
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate())

	assert_false(runtime.emit_event("test_event"))
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)
	assert_null(runtime.get_state("core"))
	assert_true(str(runtime.get_errors()).contains("intentional event failure"))


func test_invalid_event_payload_is_rejected() -> void:
	_write_file("core", "control.lua", """
		script.on_event("test_event", function(event)
			error("should never execute")
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate())

	assert_false(runtime.emit_event("test_event", {
		"position": Vector3.ZERO
	}))

	assert_eq(runtime.get_phase(), RuntimeManager.Phase.ACTIVE)


func test_invalid_event_registration_aborts_setup() -> void:
	_write_file("core", "control.lua", """
		script.on_event("test_event", 123)
	""")

	assert_false(runtime.prepare(_resolve_mods()))
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)


func test_event_handler_uses_execution_guard() -> void:
	_write_file("core", "control.lua", """
		script.on_event("test_event", function(event)
			while true do end
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate())

	assert_false(runtime.emit_event("test_event"))
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)


func test_event_is_delivered_after_activation() -> void:
	_write_file("core", "control.lua", """
		script.on_init(function()
			storage.events_received = 0
		end)

		script.on_event("run_started", function(event)
			assert(event.name == "run_started")
			assert(event.difficulty == 3)

			storage.events_received = storage.events_received + 1
			game.record("event:" .. storage.events_received)
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate({"record": _record_lifecycle_call}))

	assert_true(runtime.emit_event("run_started", {"difficulty": 3}))
	assert_true(runtime.emit_event("run_started", {"difficulty": 3}))

	assert_eq(lifecycle_calls, ["event:1", "event:2"])


func test_custom_event_has_stable_name() -> void:
	_write_file("core", "control.lua", """
		local event_id = script.register_event("card_drawn")
		assert(event_id == "core:card_drawn")

		script.on_event(event_id, function(event)
			assert(event.name == "core:card_drawn")
			assert(event.mod_name == "core")
			assert(event.amount == 2)
			game.record("received")
		end)

		script.on_init(function()
			script.raise_event(event_id, {amount = 2})
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate({"record": _record_lifecycle_call}))
	assert_eq(lifecycle_calls, ["received"])


func test_another_mod_can_subscribe_to_custom_event() -> void:
	_create_mod("demo_a")

	_write_file("core", "control.lua", """
		local event_id = script.register_event("special_action")

		script.on_event(event_id, function(event)
			game.record("core")
		end)

		script.on_init(function()
			script.raise_event(event_id, {})
		end)
	""")

	_write_file("demo_a", "control.lua", """
		script.on_event("core:special_action", function(event)
			assert(event.mod_name == "core")
			game.record("demo_a")
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods(["demo_a"])))
	assert_true(runtime.activate({"record": _record_lifecycle_call}))
	assert_eq(lifecycle_calls, ["core", "demo_a"])


func test_foreign_mod_cannot_raise_custom_event() -> void:
	_create_mod("demo_a")

	_write_file("core", "control.lua", """
		script.register_event("protected_event")
	""")

	_write_file("demo_a", "control.lua", """
		script.on_init(function()
			script.raise_event("core:protected_event", {})
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods(["demo_a"])))
	assert_false(runtime.activate())
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)


func test_custom_event_cannot_be_raised_during_setup() -> void:
	_write_file("core", "control.lua", """
		local event_id = script.register_event("early_event")
		script.raise_event(event_id, {})
	""")

	assert_false(runtime.prepare(_resolve_mods()))
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)


func test_custom_event_cannot_be_raised_during_on_load() -> void:
	_write_file("core", "control.lua", """
		local event_id = script.register_event("load_event")

		script.on_load(function()
			script.raise_event(event_id, {})
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods()))
	assert_false(runtime.activate({}, ["core"]))
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)


func test_custom_events_are_queued_without_reentrant_execution() -> void:
	_create_mod("demo_a")

	_write_file("core", "control.lua", """
		local second = script.register_event("second")

		script.on_event("first", function(event)
			game.record("core:first:start")
			script.raise_event(second, {})
			game.record("core:first:end")
		end)

		script.on_event(second, function(event)
			game.record("core:second")
		end)
	""")

	_write_file("demo_a", "control.lua", """
		script.on_event("first", function(event)
			game.record("demo_a:first")
		end)

		script.on_event("core:second", function(event)
			game.record("demo_a:second")
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods(["demo_a"])))
	assert_true(runtime.activate({"record": _record_lifecycle_call}))
	assert_true(runtime.emit_event("first"))

	assert_eq(lifecycle_calls, [
		"core:first:start",
		"core:first:end",
		"demo_a:first",
		"core:second",
		"demo_a:second"
	])


func test_circular_custom_event_payload_is_rejected() -> void:
	_write_file("core", "control.lua", """
		local event_id = script.register_event("circular")

		script.on_init(function()
			local data = {}
			data.self = data
			script.raise_event(event_id, data)
		end)
	""")

	assert_true(runtime.prepare(_resolve_mods()))
	assert_false(runtime.activate())
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)
	assert_true(str(runtime.get_errors()).contains("Circular"))


func test_custom_event_nested_payload() -> void:
	_write_file("core", "control.lua", """
		local event_id = script.register_event("nested")

		script.on_event(event_id, function(event)
			assert(event.details.score == 7)
			assert(event.details.active == true)
			game.record("nested_ok")
		end)

		script.on_init(function()
			script.raise_event(event_id, {
				details = {
					score = 7,
					active = true
				}
			})
		end)
	""")
	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.activate({"record": _record_lifecycle_call}))
	assert_eq(lifecycle_calls, ["nested_ok"])


func test_remote_interfaces_are_collected_after_setup() -> void:
	_create_mod("demo_a")

	_write_file("core", "control.lua", """
		remote.add_interface("inventory", {
			get_quantity = function(item_id)
				return 10
			end,
			has_item = function(item_id)
				return true
			end
		})
	""")

	_write_file("demo_a", "control.lua", """
		remote.add_interface("inventory", {
			get_quantity = function(item_id)
				return 20
			end
		})
	""")

	assert_true(runtime.prepare(_resolve_mods(["demo_a"])))
	assert_eq(runtime.get_phase(), RuntimeManager.Phase.PREPARED)

	var interfaces := runtime.get_remote_interfaces()

	assert_eq(interfaces.size(), 2)
	assert_true(interfaces.has("core:inventory"))
	assert_true(interfaces.has("demo_a:inventory"))

	assert_eq(runtime.get_remote_interface_owner("core:inventory"), "core")
	assert_eq(runtime.get_remote_interface_owner("demo_a:inventory"), "demo_a")

	assert_true(runtime.has_remote_interface("core:inventory"))
	assert_true(runtime.has_remote_interface("demo_a:inventory"))
	assert_false(runtime.has_remote_interface("unknown:inventory"))

	assert_true(runtime.has_remote_method("core:inventory", "get_quantity"))
	assert_true(runtime.has_remote_method("core:inventory", "has_item"))
	assert_false(runtime.has_remote_method("core:inventory", "missing"))

	assert_true(runtime.has_remote_method("demo_a:inventory", "get_quantity"))
	assert_false(runtime.has_remote_method("demo_a:inventory", "has_item"))

	assert_true(runtime.activate())
	assert_true(runtime.has_remote_interface("core:inventory"))


func test_remote_catalog_ignores_mods_without_control() -> void:
	_create_mod("demo_a")

	_write_file("core", "control.lua", """
		remote.add_interface("example", {
			test = function()
				return true
			end
		})
	""")

	assert_true(runtime.prepare(_resolve_mods(["demo_a"])))

	assert_eq(runtime.get_remote_interfaces(), ["core:example"])
	assert_true(runtime.has_remote_interface("core:example"))
	assert_false(runtime.has_remote_interface("demo_a:example"))
	assert_eq(runtime.get_remote_interface_owner("demo_a:example"), "")


func test_remote_catalog_is_cleared_on_close() -> void:
	_write_file("core", "control.lua", """
		remote.add_interface("example", {
			test = function()
				return true
			end
		})
	""")

	assert_true(runtime.get_remote_interfaces().is_empty())

	assert_true(runtime.prepare(_resolve_mods()))
	assert_true(runtime.has_remote_interface("core:example"))

	runtime.close()

	assert_eq(runtime.get_phase(), RuntimeManager.Phase.CLOSED)
	assert_true(runtime.get_remote_interfaces().is_empty())
	assert_false(runtime.has_remote_interface("core:example"))
	assert_false(runtime.has_remote_method("core:example", "test"))


func test_invalid_remote_registration_aborts_manager_preparation() -> void:
	_write_file("core", "control.lua", """
		remote.add_interface("invalid", {
			test = 123
		})
	""")

	assert_false(runtime.prepare(_resolve_mods()))

	assert_eq(runtime.get_phase(), RuntimeManager.Phase.FAILED)
	assert_true(runtime.get_remote_interfaces().is_empty())
	assert_false(runtime.get_errors().is_empty())
