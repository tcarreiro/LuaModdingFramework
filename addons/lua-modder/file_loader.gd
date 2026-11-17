
@tool
class_name FileLoader extends RefCounted

const JSON_MAX_MEMORY_BYTES := 4 * 1024 * 1024
const LUA_MAX_MEMORY_BYTES := 1 * 1024 * 1024

var errors: Array[String] = []
var warnings: Array[String] = []


func _load_json(state: State, manifest: ModManifest, path: String) -> bool:
	var json := LuaUtils.load_json(errors, path, JSON_MAX_MEMORY_BYTES)
	if json == null:
		return false

	var templates: Array = json.data
	for index in range(templates.size()):
		var value: Variant = templates[index]

		if typeof(value) != TYPE_DICTIONARY:
			errors.append("Invalid Template at index %d in '%s': expected an object." % [index, path])
			return false

		if not state.define_from_json(value, manifest.id):
			errors.append("Failed to register Template at index %d in '%s' (mod '%s')." % [
				index, path, manifest.id
			])
			return false

	return true


func _execute_lua(state: State, manifest: ModManifest, path: String) -> bool:
	var previous_error_count := errors.size()
	var source := LuaUtils.get_lua_content_file(errors, path, LUA_MAX_MEMORY_BYTES)

	if errors.size() > previous_error_count:
		return false

	if not state.execute(source, manifest.id, path):
		errors.append("Failed to execute '%s' (mod '%s')." % [path, manifest.id])
		return false

	return true


func _abort(state: State) -> void:
	errors.append_array(state.get_errors())
	warnings.append_array(state.get_warnings())
	state.close()


func _run_lua_round(state: State, mods: Array[ModManifest], filename: String) -> bool:
	for manifest in mods:
		var path := manifest.root_path.path_join(filename)

		if FileAccess.file_exists(path) and not _execute_lua(state, manifest, path):
			return false

	return true
