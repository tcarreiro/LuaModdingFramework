@tool
class_name SettingsLoader extends RefCounted

const SETTINGS_JSON_FILE_NAME := "settings.json"
const SETTINGS_LUA_FILE_NAME := "settings.lua"
const SETTINGS_UPDATES_FILE_NAME := "settings-updates.lua"
const SETTINGS_FINAL_FIXES_FILE_NAME := "settings-final-fixes.lua"

var errors: Array[String] = []
var warnings: Array[String] = []


func run(mods: Array[ModManifest]) -> ModSettingsRegistry:
	errors.clear()
	warnings.clear()

	if mods.is_empty():
		errors.append("Cannot run Settings Stage without mods.")
		return null

	var settings_state := SettingsState.new()
	settings_state.start()

	# Round 1: Definitions
	for manifest in mods:
		var json_path := manifest.root_path.path_join(SETTINGS_JSON_FILE_NAME)
		if FileAccess.file_exists(json_path):
			if not _load_json(settings_state, manifest, json_path):
				_abort(settings_state)
				return null

		var lua_path := manifest.root_path.path_join(SETTINGS_LUA_FILE_NAME)
		if FileAccess.file_exists(lua_path):
			if not _execute_lua(settings_state, manifest, lua_path):
				_abort(settings_state)
				return null

	# Round 2: Updates
	for manifest in mods:
		var path := manifest.root_path.path_join(SETTINGS_UPDATES_FILE_NAME)
		if FileAccess.file_exists(path):
			if not _execute_lua(settings_state, manifest, path):
				_abort(settings_state)
				return null

	# Round 3: Final Fixes
	for manifest in mods:
		var path := manifest.root_path.path_join(SETTINGS_FINAL_FIXES_FILE_NAME)
		if FileAccess.file_exists(path):
			if not _execute_lua(settings_state, manifest, path):
				_abort(settings_state)
				return null

	var registry := settings_state.finish()

	errors.append_array(settings_state.get_errors())
	warnings.append_array(settings_state.get_warnings())

	if registry == null and errors.is_empty():
		errors.append("Settings Stage failed during finalization.")

	return registry


func _load_json(settings_state: SettingsState, manifest: ModManifest, path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Cannot open settings JSON: '%s'." % path)
		return false

	var json := JSON.new()
	var error := json.parse(file.get_as_text())

	if error != OK:
		errors.append("Invalid JSON in '%s' at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return false

	if typeof(json.data) != TYPE_ARRAY:
		errors.append("Settings JSON must contain an array: '%s'." % path)
		return false

	var definitions: Array = json.data

	for index in range(definitions.size()):
		var definition: Variant = definitions[index]

		if typeof(definition) != TYPE_DICTIONARY:
			errors.append("Invalid definition at index %d in '%s': expected an object." % [index, path])
			return false

		if not settings_state.define_from_json(definition, manifest.id):
			errors.append("Failed to register setting at index %d in '%s' (mod '%s')." % [index, path, manifest.id])
			return false

	return true


func _execute_lua(settings_state: SettingsState, manifest: ModManifest, path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Cannot open settings Lua script: '%s'." % path)
		return false

	var source := file.get_as_text()

	if not settings_state.execute(source, manifest.id, path):
		errors.append("Failed to execute '%s' (mod '%s')." % [path, manifest.id])
		return false

	return true


func _abort(settings_state: SettingsState) -> void:
	errors.append_array(settings_state.get_errors())
	warnings.append_array(settings_state.get_warnings())
	settings_state.close()
