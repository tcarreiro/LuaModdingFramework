class_name ContentLoader extends FileLoader

const CONTENT_DIRECTORY_NAME := "content"
const CONTENT_LUA_FILE_NAME := "content.lua"
const CONTENT_UPDATES_FILE_NAME := "content-updates.lua"
const CONTENT_FINAL_FIXES_FILE_NAME := "content-final-fixes.lua"

var _types: ContentTypeRegistry

func _init(content_types: ContentTypeRegistry) -> void:
	_types = content_types


func run(mods: Array[ModManifest], startup_settings: Dictionary = {}, ui_components: UIComponentRegistry = null, style_registration_mods: Array[String] = ["core"]) -> ContentRegistry:
	errors.clear()
	warnings.clear()
	if mods.is_empty():
		errors.append("Cannot run Content Stage without mods.")
		return null
	
	# Mod versions check
	var mod_versions: Dictionary = {}
	for manifest in mods:
		mod_versions[manifest.id] = manifest.version
	var state := ContentState.new(_types, ui_components, style_registration_mods)
	state.start(startup_settings, mod_versions)
	if not _load_definitions(state, mods) \
			or not _run_lua_round(state, mods, CONTENT_UPDATES_FILE_NAME) \
			or not _run_lua_round(state, mods, CONTENT_FINAL_FIXES_FILE_NAME):
		_abort(state)
		return null
	var registry := state.finish()
	errors.append_array(state.get_errors())
	if registry == null and errors.is_empty():
		errors.append("Content Stage failed during finalization.")
	return registry


func _load_definitions(state: ContentState, mods: Array[ModManifest]) -> bool:
	for manifest in mods:
		if not _load_mod_definitions(state, manifest):
			return false
	return true


func _load_mod_definitions(state: ContentState, manifest: ModManifest) -> bool:
	var content_path := manifest.root_path.path_join(CONTENT_DIRECTORY_NAME)
	if DirAccess.dir_exists_absolute(content_path):
		var json_paths: Array[String] = []
		if not _collect_json_files(content_path, json_paths):
			return false
		json_paths.sort()
		for json_path in json_paths:
			if not _load_json(state, manifest, json_path):
				return false
	var lua_path := manifest.root_path.path_join(CONTENT_LUA_FILE_NAME)
	if FileAccess.file_exists(lua_path):
		return _execute_lua(state, manifest, lua_path)
	return true


# each mod folder should place all .lua content files inside subfolder /content
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
