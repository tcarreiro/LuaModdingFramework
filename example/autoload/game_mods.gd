extends Node

const GAME_VERSION := "0.1.0"

var mod_manager: ModManager
var selected_mods: Array[ModManifest] = []
var selected_mod_ids: Array[String] = []
var settings_registry: ModSettingsRegistry
var selected_settings: Dictionary[String, Variant] = {}

var prepare_errors: Array[String] = []
var prepare_warnings: Array[String] = []


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
