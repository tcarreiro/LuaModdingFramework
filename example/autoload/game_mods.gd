extends Node

const GAME_VERSION := "0.1.0"
var mod_manager: ModManager
var selected_mods: Array[ModManifest] = []

func _ready() -> void:
	mod_manager = ModManager.new(GAME_VERSION, "res://example/mods")
	mod_manager.discover()
	
	for error in mod_manager.discovery_errors:
		push_warning("[GameMods] %s" % error)


func get_available_mods() -> Array[ModManifest]:
	return mod_manager.get_available_mods()


func prepare_new_game(mod_ids: Array[String]) -> bool:
	selected_mods.clear()
	
	var resolved_mods := mod_manager.resolve(mod_ids)
	
	if not mod_manager.resolution_errors.is_empty():
		for error in mod_manager.resolution_errors:
			push_error("[GameMods] - %s" % error)
		return false
	
	selected_mods = resolved_mods
	
	return true
