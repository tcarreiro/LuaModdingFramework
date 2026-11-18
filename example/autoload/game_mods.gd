extends Node

signal runtime_log_changed(message: String)

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
var settings_registry: SettingsRegistry
var selected_settings: Dictionary[String, Variant] = {}
var content_registry: ContentRegistry

# UI: catálogo permanente do consumidor; mount temporário da tela de Runtime.
var ui_catalog: PlaygroundUiCatalog
var _ui_mount: Control

# Settings stage
var prepare_errors: Array[String] = []
var prepare_warnings: Array[String] = []

# Content stage
var content_errors: Array[String] = []

# Runtime stage
var runtime_manager: RuntimeManager
var runtime_errors: Array[String] = []
var runtime_log: Array[String] = []
var world_time: int = 0

func _ready() -> void:
	mod_manager = ModManager.new(GAME_VERSION, "res://example/mods")
	mod_manager.discover()

	for error in mod_manager.discovery_errors:
		push_warning("[GameMods] %s" % error)

	ui_catalog = PlaygroundUiCatalog.new()
	if not ui_catalog.build():
		for error in ui_catalog.errors:
			push_error("[PlaygroundUI] %s" % error)


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
	content_registry = null
	content_errors.clear()

	if settings_registry == null or selected_mods.is_empty():
		content_errors.append("Settings Stage must be completed before Content Stage.")
		return false

	var content_types := ContentTypeRegistry.new()

	# Templates
	content_types.register_type("loot", LOOT_SCRIPT, _validate_loot)
	content_types.register_type("equipment", EQUIPMENT_SCRIPT)
	content_types.register_type("gauntlet", GAUNTLET_SCRIPT, _validate_gauntlet)
	content_types.register_type("card", CARD_SCRIPT)
	content_types.register_type("item-container", CONTAINER_SCRIPT)

	# Structs
	content_types.register_struct("item-stack", STACK_SCRIPT)
	content_types.register_struct_binding("equipment", "attached_items", "item-stack")

	# References
	content_types.register_reference("item-stack", "item_id", "loot")
	content_types.register_reference("equipment", "material_id", "loot")

	if not content_types.errors.is_empty():
		content_errors.append_array(content_types.errors)
		return false

	var startup_settings: Dictionary = {}

	for setting in settings_registry.get_all_settings():
		if setting.scope != ModSetting.STARTUP:
			continue

		if not selected_settings.has(setting.id):
			content_errors.append("Missing startup setting '%s'." % setting.id)
			return false

		startup_settings[setting.id] = selected_settings[setting.id]

	# Novo catálogo para este carregamento de mods.
	# Estilos nativos preparados; componentes ainda abertos a registro.
	var next_ui_catalog := PlaygroundUiCatalog.new()

	if not next_ui_catalog.build(false):
		content_errors.append_array(next_ui_catalog.errors)
		return false

	var loader := ContentLoader.new(content_types)

	var next_content_registry := loader.run(
		selected_mods,
		startup_settings,
		next_ui_catalog.component_registry
	)

	content_errors.append_array(loader.errors)

	if next_content_registry == null:
		return false

	# Os mods já registraram seus templates no Content Stage.
	# Validamos todas as referências, permissões e rotas antes do Runtime.
	if not next_ui_catalog.component_registry.finalize():
		content_errors.append_array(next_ui_catalog.component_registry.errors)
		return false

	content_registry = next_content_registry
	ui_catalog = next_ui_catalog

	return true



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


func attach_ui_mount(mount: Control) -> bool:
	if mount == null or not is_instance_valid(mount) or not mount.is_inside_tree():
		runtime_errors.append("O ponto de montagem da UI não está na SceneTree.")
		return false
	if is_runtime_active():
		runtime_errors.append("Não é permitido alterar o mount durante um Runtime ativo.")
		return false
	_ui_mount = mount
	return true


func detach_ui_mount(mount: Control) -> void:
	if _ui_mount == mount:
		_ui_mount = null


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
	if _ui_mount == null or not is_instance_valid(_ui_mount) or not _ui_mount.is_inside_tree():
		runtime_errors.append("Runtime Stage requer um mount de UI válido.")
		return false
	if ui_catalog == null or not ui_catalog.component_registry.is_finalized():
		runtime_errors.append("O catálogo de UI do consumidor não foi finalizado.")
		return false

	var api := RuntimeApiRegistry.new()
	api.register_function("world", "get_time", Callable(self, "_runtime_get_time"))
	api.register_function("player", "get_name", Callable(self, "_runtime_get_player_name"))
	api.register_function("settings", "get_enemy_speed", Callable(self, "_runtime_get_enemy_speed"))
	api.register_function("debug", "log", Callable(self, "_runtime_log_message"))

	if not api.errors.is_empty():
		runtime_errors.append_array(api.errors)
		return false

	runtime_manager = RuntimeManager.new()
	if not runtime_manager.configure_ui_bridge(Callable(self, "_create_mod_ui_bridge")):
		return _runtime_failed()

	if not runtime_manager.prepare(selected_mods):
		return _runtime_failed()

	if not runtime_manager.activate({}, existing_mod_ids, null, saved_storage, api):
		return _runtime_failed()

	# on_load() não possui acesso ao game. A UI é reconstruída somente
	# depois da ativação completa, tanto em jogos novos quanto restaurados.
	if not runtime_manager.emit_event("on_ui_ready"):
		return _runtime_failed()

	_add_runtime_log("Runtime ativo: %s" % ", ".join(PackedStringArray(runtime_manager.get_mod_ids())))
	return true


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
	if runtime_manager != null:
		runtime_manager.close()
		runtime_manager = null
	# Os bridges encerram os componentes Lua antes de os LuaStates fecharem.
	# Os hosts visuais são exclusivos do playground e pertencem à tela atual.
	if _ui_mount != null and is_instance_valid(_ui_mount):
		for child in _ui_mount.get_children():
			child.hide()
			child.queue_free()


func _runtime_failed() -> bool:
	if runtime_manager != null:
		runtime_errors.append_array(runtime_manager.get_errors())

	stop_runtime()
	return false


func _create_mod_ui_bridge(mod_id: String, state: RuntimeState) -> UIRuntimeBridge:
	# Chamado pela factory REAL do RuntimeManager, uma vez para cada mod.
	var host := VBoxContainer.new()
	host.name = "UI_%s" % mod_id
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.add_theme_constant_override("separation", 8)

	var heading := Label.new()
	heading.text = "MOD  /  %s" % mod_id.to_upper()
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", Color("#91afc9"))
	host.add_child(heading)
	_ui_mount.add_child(host)

	var bridge := UIRuntimeBridge.new()
	bridge.setup(ui_catalog.component_registry, host, state)
	return bridge


#region Persistence

func save_runtime() -> bool:
	runtime_errors.clear()

	if not is_runtime_active():
		runtime_errors.append("Cannot save an inactive Runtime Stage.")
		return false

	var snapshots := runtime_manager.snapshot_storage()
	if snapshots.is_empty() and not runtime_manager.get_mod_ids().is_empty():
		return _runtime_failed()

	var file := FileAccess.open(RUNTIME_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		runtime_errors.append("Cannot create save file: %s" % error_string(FileAccess.get_open_error()))
		return false

	file.store_var({
		"version": 1,
		"selected_mod_ids": selected_mod_ids.duplicate(),
		"selected_settings": selected_settings.duplicate(true),
		"runtime_mod_ids": runtime_manager.get_mod_ids(),
		"storage": snapshots,
		"world_time": world_time
	}, false)
	file.close()

	_add_runtime_log("Storage salvo em %s" % RUNTIME_SAVE_PATH)
	return true


func save_and_restore_runtime() -> bool:
	if not save_runtime():
		return false

	stop_runtime()
	return restore_runtime()


func restore_runtime() -> bool:
	runtime_errors.clear()

	var file := FileAccess.open(RUNTIME_SAVE_PATH, FileAccess.READ)
	if file == null:
		runtime_errors.append("Cannot read save file: %s" % error_string(FileAccess.get_open_error()))
		return false

	var saved: Variant = file.get_var(false)
	file.close()

	if not saved is Dictionary or saved.get("version") != 1:
		runtime_errors.append("Invalid playground save format.")
		return false

	var raw_selected: Variant = saved.get("selected_mod_ids")
	var raw_existing: Variant = saved.get("runtime_mod_ids")
	var raw_settings: Variant = saved.get("selected_settings")
	var raw_storage: Variant = saved.get("storage")
	var raw_time: Variant = saved.get("world_time")

	if not raw_selected is Array or not raw_existing is Array \
			or not raw_settings is Dictionary or not raw_storage is Dictionary \
			or typeof(raw_time) != TYPE_INT:
		runtime_errors.append("Playground save contains invalid fields.")
		return false

	var selected_ids: Array[String] = []
	var existing_ids: Array[String] = []

	for id in raw_selected:
		if typeof(id) != TYPE_STRING:
			runtime_errors.append("Invalid selected mod ID in save.")
			return false
		selected_ids.append(id)

	for id in raw_existing:
		if typeof(id) != TYPE_STRING:
			runtime_errors.append("Invalid active runtime mod ID in save.")
			return false
		existing_ids.append(id)

	if not prepare_new_game(selected_ids):
		runtime_errors.append_array(prepare_errors)
		return false

	var restored_settings: Dictionary[String, Variant] = {}

	for setting in settings_registry.get_all_settings():
		if not raw_settings.has(setting.id):
			runtime_errors.append("Missing saved setting '%s'." % setting.id)
			return false

		var value: Variant = raw_settings[setting.id]
		var validation_error := setting.validate_value(value)

		if not validation_error.is_empty():
			runtime_errors.append("Invalid saved setting '%s': %s" % [setting.id, validation_error])
			return false

		if setting.is_forced() and value != setting.get_effective_value():
			runtime_errors.append("Forced setting '%s' differs from the current value." % setting.id)
			return false

		restored_settings[setting.id] = value

	selected_settings = restored_settings

	if not run_content_stage():
		runtime_errors.append_array(content_errors)
		return false

	world_time = raw_time

	if not _start_runtime(existing_ids, raw_storage):
		return false

	_add_runtime_log("Storage restaurado; on_load executado para os mods existentes.")
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
	runtime_log_changed.emit(message)
