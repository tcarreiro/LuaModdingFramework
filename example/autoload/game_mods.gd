extends Node

const GAME_VERSION := "0.1.0"

const LOOT_SCRIPT = preload("res://example/content/content_loot.gd")
const STACK_SCRIPT = preload("res://example/content/content_item_stack.gd")
const CONTAINER_SCRIPT = preload("res://example/content/content_container.gd")

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

func _ready() -> void:
	mod_manager = ModManager.new(GAME_VERSION, "res://example/mods")
	mod_manager.discover()

	for error in mod_manager.discovery_errors:
		push_warning("[GameMods] %s" % error)


func get_available_mods() -> Array[ModManifest]:
	return mod_manager.get_available_mods()


func prepare_new_game(mod_ids: Array[String]) -> bool:
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

	content_types.register_type("loot", LOOT_SCRIPT, _validate_loot)
	content_types.register_type("item-container", CONTAINER_SCRIPT)
	content_types.register_struct("item-stack", STACK_SCRIPT)
	content_types.register_reference("item-stack", "item_id", "loot")

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

	var loader := ContentLoader.new(content_types)
	content_registry = loader.run(selected_mods, startup_settings)

	content_errors.append_array(loader.errors)
	return content_registry != null


func _validate_loot(data: Dictionary) -> String:
	if data.has("max_stack") and data["max_stack"] < 1:
		return "max_stack must be greater than zero."

	if data.has("weight") and data["weight"] < 0.0:
		return "weight cannot be negative."

	return ""
