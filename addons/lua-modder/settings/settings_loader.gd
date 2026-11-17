class_name SettingsLoader extends FileLoader

const SETTINGS_JSON_FILE_NAME := "settings.json"
const SETTINGS_LUA_FILE_NAME := "settings.lua"
const SETTINGS_UPDATES_FILE_NAME := "settings-updates.lua"
const SETTINGS_FINAL_FIXES_FILE_NAME := "settings-final-fixes.lua"

func run(mods: Array[ModManifest], initial_data: Dictionary = {}) -> SettingsRegistry:
	errors.clear()
	warnings.clear()
	if mods.is_empty():
		errors.append("Cannot run Settings Stage without mods.")
		return null

	var state := SettingsState.new()
	state.start()
	if not _load_definitions(state, mods) \
			or not _run_lua_round(state, mods, SETTINGS_UPDATES_FILE_NAME) \
			or not _run_lua_round(state, mods, SETTINGS_FINAL_FIXES_FILE_NAME):
		_abort(state)
		return null

	var registry := state.finish()
	errors.append_array(state.get_errors())
	warnings.append_array(state.get_warnings())
	if registry == null and errors.is_empty():
		errors.append("Settings Stage failed during finalization.")
	return registry


#region private methods
func _load_definitions(state: SettingsState, mods: Array[ModManifest]) -> bool:
	for manifest in mods:
		var json_path := manifest.root_path.path_join(SETTINGS_JSON_FILE_NAME)
		if FileAccess.file_exists(json_path) and not _load_json(state, manifest, json_path):
			return false
		var lua_path := manifest.root_path.path_join(SETTINGS_LUA_FILE_NAME)
		if FileAccess.file_exists(lua_path) and not _execute_lua(state, manifest, lua_path):
			return false
	return true
#endregion
