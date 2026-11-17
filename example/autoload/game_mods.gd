extends Node

const GAME_VERSION := "0.1.0"
const RUNTIME_SAVE_PATH := "user://lua_modder_playground.save"

const LOOT_SCRIPT = preload("res://example/content/content_loot.gd")
const STACK_SCRIPT = preload("res://example/content/content_item_stack.gd")
const CONTAINER_SCRIPT = preload("res://example/content/content_container.gd")

const EQUIPMENT_SCRIPT = preload("res://example/content/content_equipment.gd")
const GAUNTLET_SCRIPT = preload("res://example/content/content_gauntlet.gd")
const CARD_SCRIPT = preload("res://example/content/content_card.gd")

var mod_manager: ModManager
var selected_mods: Array[ModManifest] = []
var selected_mod_ids: Array[String] = []
var settings_registry: ModSettingsRegistry
var selected_settings: Dictionary[String, Variant] = {}
var content_registry: ContentRegistry

# Settings stage
var prepare_errors: Array[String] = []
var prepare_warnings: Array[String] = []

# Content stage
var content_errors: Array[String] = []

# Runtime stage (owned by the example game, not the framework)
var runtime_manager: RuntimeManager
var runtime_errors: Array[String] = []
var runtime_log: Array[String] = []
var world_time: int = 0

func _ready() -> void:
	mod_manager = ModManager.new(GAME_VERSION, "res://example/mods")
	mod_manager.discover()

	for error in mod_manager.discovery_errors:
		push_warning("[GameMods] %s" % error)


func get_available_mods() -> Array[ModManifest]:
	return mod_manager.get_available_mods()


func prepare_new_game(mod_ids: Array[String]) -> bool:
	stop_runtime()
	selected_mods.clear()
	selected_mod_ids.clear()
	selected_settings.clear()
	settings_registry = null
	prepare_errors.clear()
	prepare_warnings.clear()
	content_registry = null
	content_errors.clear()

	var resolved_mods := mod_manager.resolve(mod_ids)

	if not mod_manager.resolution_errors.is_empty():
		prepare_errors.append_array(mod_manager.resolution_errors)
		return false

	var loader := SettingsLoader.new()
	var registry := loader.run(resolved_mods)

	prepare_errors.append_array(loader.errors)
	prepare_warnings.append_array(loader.warnings)

	if registry == null:
		return false

	selected_mods = resolved_mods
	selected_mod_ids = mod_ids.duplicate()
	settings_registry = registry

	for setting in registry.get_all_settings():
		selected_settings[setting.id] = setting.get_effective_value()

	return true



func run_content_stage() -> bool:
	stop_runtime()
	content_registry = null
	content_errors.clear()

	if settings_registry == null or selected_mods.is_empty():
		content_errors.append("Settings Stage must be completed before Content Stage.")
		return false

	var content_types := _register_content_types()
	if not content_types.errors.is_empty():
		content_errors.append_array(content_types.errors)
		return false

	var startup_settings := _collect_startup_settings()
	if not content_errors.is_empty():
		return false

	var loader := ContentLoader.new(content_types)
	content_registry = loader.run(selected_mods, startup_settings)
	content_errors.append_array(loader.errors)
	return content_registry != null


func _register_content_types() -> ContentTypeRegistry:
	var types := ContentTypeRegistry.new()
	# Templates
	types.register_type("loot", LOOT_SCRIPT, _validate_loot)
	types.register_type("equipment", EQUIPMENT_SCRIPT)
	types.register_type("gauntlet", GAUNTLET_SCRIPT, _validate_gauntlet)
	types.register_type("card", CARD_SCRIPT)
	types.register_type("item-container", CONTAINER_SCRIPT)
	# Structs
	types.register_struct("item-stack", STACK_SCRIPT)
	types.register_struct_binding("equipment", "attached_items", "item-stack")
	# References
	types.register_reference("item-stack", "item_id", "loot")
	types.register_reference("equipment", "material_id", "loot")
	return types


func _collect_startup_settings() -> Dictionary:
	var values: Dictionary = {}
	for setting in settings_registry.get_all_settings():
		if setting.scope != ModSetting.STARTUP:
			continue
		if not selected_settings.has(setting.id):
			content_errors.append("Missing startup setting '%s'." % setting.id)
			return {}
		values[setting.id] = selected_settings[setting.id]
	return values


#region Runtime playground
func start_new_runtime() -> bool:
	world_time = 0
	runtime_log.clear()
	return _start_runtime()


func _start_runtime(existing_mod_ids: Array[String] = [], saved_storage: Dictionary = {}) -> bool:
	stop_runtime()
	runtime_errors.clear()

	if content_registry == null or selected_mods.is_empty():
		runtime_errors.append("Content Stage must be completed before Runtime Stage.")
		return false

	var api := _create_runtime_api()
	if not api.errors.is_empty():
		runtime_errors.append_array(api.errors)
		return false

	runtime_manager = RuntimeManager.new()
	if not runtime_manager.prepare(selected_mods):
		return _runtime_failed()
	if not runtime_manager.activate({}, existing_mod_ids, null, saved_storage, api):
		return _runtime_failed()

	_add_runtime_log("Runtime ativo: %s" % ", ".join(PackedStringArray(runtime_manager.get_mod_ids())))
	return true


func _create_runtime_api() -> RuntimeApiRegistry:
	var api := RuntimeApiRegistry.new()
	api.register_function("world", "get_time", Callable(self, "_runtime_get_time"))
	api.register_function("player", "get_name", Callable(self, "_runtime_get_player_name"))
	api.register_function("settings", "get_enemy_speed", Callable(self, "_runtime_get_enemy_speed"))
	api.register_function("debug", "log", Callable(self, "_runtime_log_message"))
	return api


func advance_tick() -> bool:
	if not is_runtime_active():
		runtime_errors.append("Runtime Stage is not active.")
		return false
	world_time += 1
	if not runtime_manager.emit_event("on_tick", {"tick": world_time}):
		return _runtime_failed()
	return true


func is_runtime_active() -> bool:
	return runtime_manager != null and runtime_manager.get_phase() == RuntimeManager.Phase.ACTIVE


func stop_runtime() -> void:
	if runtime_manager == null:
		return
	runtime_manager.close()
	runtime_manager = null


func _runtime_failed() -> bool:
	if runtime_manager != null:
		runtime_errors.append_array(runtime_manager.get_errors())
	stop_runtime()
	return false


#region Runtime persistence
func save_runtime() -> bool:
	runtime_errors.clear()
	if not is_runtime_active():
		runtime_errors.append("Cannot save an inactive Runtime Stage.")
		return false

	var snapshots := runtime_manager.snapshot_storage()
	if snapshots.is_empty() and not runtime_manager.get_mod_ids().is_empty():
		runtime_errors.append_array(runtime_manager.get_errors())
		return false

	var file := FileAccess.open(RUNTIME_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		runtime_errors.append("Cannot create save file: %s" % error_string(FileAccess.get_open_error()))
		return false

	file.store_var(_build_save_data(snapshots), false)
	file.close()
	_add_runtime_log("Storage salvo em %s" % RUNTIME_SAVE_PATH)
	return true


func _build_save_data(snapshots: Dictionary) -> Dictionary:
	return {
		"version": 1,
		"selected_mod_ids": selected_mod_ids.duplicate(),
		"selected_settings": selected_settings.duplicate(true),
		"runtime_mod_ids": runtime_manager.get_mod_ids(),
		"storage": snapshots,
		"world_time": world_time
	}


func save_and_restore_runtime() -> bool:
	if not save_runtime():
		return false
	stop_runtime()
	return restore_runtime()


func restore_runtime() -> bool:
	runtime_errors.clear()
	var saved := _read_save_data()
	if saved.is_empty():
		return false

	var selected_ids := _read_saved_mod_ids(saved["selected_mod_ids"])
	var existing_ids := _read_saved_mod_ids(saved["runtime_mod_ids"])
	if not runtime_errors.is_empty():
		return false

	if not prepare_new_game(selected_ids):
		runtime_errors.append_array(prepare_errors)
		return false

	if not _restore_selected_settings(saved["selected_settings"]):
		return false
	if not run_content_stage():
		runtime_errors.append_array(content_errors)
		return false

	world_time = saved["world_time"]
	if not _start_runtime(existing_ids, saved["storage"]):
		return false
	_add_runtime_log("Storage restaurado; on_load executado para os mods existentes.")
	return true


func _read_save_data() -> Dictionary:
	var file := FileAccess.open(RUNTIME_SAVE_PATH, FileAccess.READ)
	if file == null:
		runtime_errors.append("Cannot read save file: %s" % error_string(FileAccess.get_open_error()))
		return {}
	var saved: Variant = file.get_var(false)
	file.close()
	if not _is_valid_save_data(saved):
		runtime_errors.append("Invalid playground save format or fields.")
		return {}
	return saved


func _is_valid_save_data(saved: Variant) -> bool:
	if not saved is Dictionary or saved.get("version") != 1:
		return false
	return saved.get("selected_mod_ids") is Array \
		and saved.get("runtime_mod_ids") is Array \
		and saved.get("selected_settings") is Dictionary \
		and saved.get("storage") is Dictionary \
		and typeof(saved.get("world_time")) == TYPE_INT


func _read_saved_mod_ids(raw_ids: Array) -> Array[String]:
	var ids: Array[String] = []
	for id in raw_ids:
		if typeof(id) != TYPE_STRING:
			runtime_errors.append("Invalid mod ID in playground save.")
			return []
		ids.append(id)
	return ids


func _restore_selected_settings(saved: Dictionary) -> bool:
	var restored: Dictionary[String, Variant] = {}
	for setting in settings_registry.get_all_settings():
		if not saved.has(setting.id):
			runtime_errors.append("Missing saved setting '%s'." % setting.id)
			return false
		var value: Variant = saved[setting.id]
		var validation_error := setting.validate_value(value)
		if not validation_error.is_empty():
			runtime_errors.append("Invalid saved setting '%s': %s" % [setting.id, validation_error])
			return false
		if setting.is_forced() and value != setting.get_effective_value():
			runtime_errors.append("Forced setting '%s' differs from the current value." % setting.id)
			return false
		restored[setting.id] = value
	selected_settings = restored
	return true
#endregion


#region Consumer API
func _runtime_get_time() -> int:
	return world_time


func _runtime_get_player_name() -> String:
	return "Explorador"


func _runtime_get_enemy_speed() -> String:
	return str(selected_settings.get("enemy_speed", "normal"))


func _runtime_log_message(message: Variant) -> void:
	_add_runtime_log(str(message))


func _add_runtime_log(message: String) -> void:
	runtime_log.append(message)
	print("[RuntimePlayground] ", message)
#endregion
#endregion


func _validate_loot(data: Dictionary) -> String:
	if data.has("max_stack") and data["max_stack"] < 1:
		return "max_stack must be greater than zero."

	if data.has("weight") and data["weight"] < 0.0:
		return "weight cannot be negative."

	return ""


func _validate_gauntlet(data: Dictionary) -> String:
	if data.get("socket_count", 1) < 1:
		return "socket_count must be greater than zero."

	return ""
