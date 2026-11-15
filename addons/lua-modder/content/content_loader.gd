@tool
class_name ContentLoader extends RefCounted

const CONTENT_DIRECTORY_NAME := "content"
const CONTENT_LUA_FILE_NAME := "content.lua"
const CONTENT_UPDATES_FILE_NAME := "content-updates.lua"
const CONTENT_FINAL_FIXES_FILE_NAME := "content-final-fixes.lua"

var errors: Array[String] = []

var _types: ContentTypeRegistry


func _init(content_types: ContentTypeRegistry) -> void:
	_types = content_types


func run(mods: Array[ModManifest], startup_settings: Dictionary = {}) -> ContentRegistry:
	errors.clear()

	if mods.is_empty():
		errors.append("Cannot run Content Stage without mods.")
		return null

	var mod_versions: Dictionary = {}

	for manifest in mods:
		mod_versions[manifest.id] = manifest.version

	var content_state := ContentState.new(_types)
	content_state.start(startup_settings, mod_versions)

	# Round 1: Definitions
	for manifest in mods:
		var content_path := manifest.root_path.path_join(CONTENT_DIRECTORY_NAME)

		if DirAccess.dir_exists_absolute(content_path):
			var json_paths: Array[String] = []

			if not _collect_json_files(content_path, json_paths):
				_abort(content_state)
				return null

			json_paths.sort()

			for json_path in json_paths:
				if not _load_json(content_state, manifest, json_path):
					_abort(content_state)
					return null

		var lua_path := manifest.root_path.path_join(CONTENT_LUA_FILE_NAME)

		if FileAccess.file_exists(lua_path):
			if not _execute_lua(content_state, manifest, lua_path):
				_abort(content_state)
				return null

	# Round 2: Updates
	for manifest in mods:
		var path := manifest.root_path.path_join(CONTENT_UPDATES_FILE_NAME)

		if FileAccess.file_exists(path):
			if not _execute_lua(content_state, manifest, path):
				_abort(content_state)
				return null

	# Round 3: Final Fixes
	for manifest in mods:
		var path := manifest.root_path.path_join(CONTENT_FINAL_FIXES_FILE_NAME)

		if FileAccess.file_exists(path):
			if not _execute_lua(content_state, manifest, path):
				_abort(content_state)
				return null

	var registry := content_state.finish()
	errors.append_array(content_state.get_errors())

	if registry == null and errors.is_empty():
		errors.append("Content Stage failed during finalization.")

	return registry


func _collect_json_files(path: String, result: Array[String]) -> bool:
	var directory := DirAccess.open(path)

	if directory == null:
		errors.append("Cannot open content directory: '%s'." % path)
		return false

	for file_name in directory.get_files():
		if file_name.get_extension().to_lower() == "json":
			result.append(path.path_join(file_name))

	for folder_name in directory.get_directories():
		var subdirectory := path.path_join(folder_name)

		if not _collect_json_files(subdirectory, result):
			return false

	return true


func _load_json(content_state: ContentState, manifest: ModManifest, path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	
	if file == null:
		errors.append("Cannot open content JSON: '%s'." % path)
		return false
	
	if file.get_length() > 4 * 1024 * 1024:
		errors.append("JSON file exceeds maximum allowed size: '%s'." % path)
		return false
	
	var json := JSON.new()
	var error := json.parse(file.get_as_text())

	if error != OK:
		errors.append("Invalid JSON in '%s' at line %d: %s" % [
			path,
			json.get_error_line(),
			json.get_error_message()
		])
		return false

	if typeof(json.data) != TYPE_ARRAY:
		errors.append("Content JSON must contain an array: '%s'." % path)
		return false

	var templates: Array = json.data

	for index in range(templates.size()):
		var value: Variant = templates[index]

		if typeof(value) != TYPE_DICTIONARY:
			errors.append("Invalid Template at index %d in '%s': expected an object." % [index, path])
			return false

		var template: Dictionary = value

		if not content_state.define_from_json(template, manifest.id):
			errors.append("Failed to register Template at index %d in '%s' (mod '%s')." % [
				index, path, manifest.id
			])
			return false

	return true


func _execute_lua(content_state: ContentState, manifest: ModManifest, path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		errors.append("Cannot open content Lua script: '%s'." % path)
		return false
	
	if file.get_length() > 1 * 1024 * 1024:
		errors.append("LUA file exceeds maximum allowed size: '%s'." % path)
		return false
	
	var source := file.get_as_text()

	if not content_state.execute(source, manifest.id, path):
		errors.append("Failed to execute '%s' (mod '%s')." % [path, manifest.id])
		return false

	return true


func _abort(content_state: ContentState) -> void:
	errors.append_array(content_state.get_errors())
	content_state.close()
