@tool
class_name ModManager extends RefCounted

const BUILTIN_MODS_PATH := "res://mods"
const USER_MODS_PATH := "user://game/mods"
const MANIFEST_FILE_NAME := "manifest.json"
const CORE_MOD_ID := "core"

const NOT_VISITED := 0
const IN_ANALYSIS := 1
const RESOLVED := 2

var game_version: String
var builtin_mods_path: String
var user_mods_path: String

var discovery_errors: Array[String] = []
var resolution_errors: Array[String] = []

var _manifests: Dictionary[String, ModManifest] = {}
var _duplicated_ids: Dictionary[String, bool] = {}

func _init(current_game_version: String, builtin_path: String = BUILTIN_MODS_PATH, user_path: String = USER_MODS_PATH) -> void:
	game_version = current_game_version
	builtin_mods_path = builtin_path
	user_mods_path = user_path


func discover() -> void:
	_manifests.clear()
	_duplicated_ids.clear()
	discovery_errors.clear()
	resolution_errors.clear()
	
	_scan_root(builtin_mods_path)
	_scan_root(user_mods_path)
	
	if not _manifests.has(CORE_MOD_ID):
		discovery_errors.append("Required core mod was not found in res://mods")


func _scan_root(root_path: String) -> void:
	var directory := DirAccess.open(root_path)
	if directory == null:
		push_warning("[ModManager] - '%s' directory not found"%[root_path])
		return
	
	for folder_name in directory.get_directories():
		if folder_name.begins_with("."):
			continue
		
		var mod_path:= root_path.path_join(folder_name)
		var manifest_path:= mod_path.path_join(MANIFEST_FILE_NAME)
		
		if not FileAccess.file_exists(manifest_path):
			push_warning("[ModManager] - Manifest '%s' not found"%[manifest_path])
			continue
		
		var manifest := _read_manifest(manifest_path, mod_path)
		if manifest == null:
			continue
		
		var expected_folder := "%s_%s" % [manifest.id, manifest.version]
		# mod folder's name should either be {mod-id} or {mod-id}_{mod-version}
		if folder_name != manifest.id and folder_name != expected_folder:
			discovery_errors.append("Invalid folder name '%s'. Expected '%s' or '%s'." % [folder_name, manifest.id, expected_folder])
			continue
		
		if manifest.id == CORE_MOD_ID and root_path != builtin_mods_path:
			discovery_errors.append("The core mod cannot be loaded from user://mods.")
			continue
		
		if _manifests.has(manifest.id):
			_duplicated_ids[manifest.id] = true
			discovery_errors.append("Duplicated mod ID '%s': '%s'"%[manifest.id, mod_path])
			continue
		
		_manifests[manifest.id] = manifest


func _read_manifest(path: String, root_path: String) -> ModManifest:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		discovery_errors.append("Cannot open manifest: %s" % path)
		return null
	if file.get_length() > 4 * 1024 * 1024:
		discovery_errors.append("JSON file exceeds maximum allowed size: '%s'." % path)
		return null

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		discovery_errors.append("Invalid JSON in '%s' at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	if typeof(json.data) != TYPE_DICTIONARY:
		discovery_errors.append("Manifest must contain a JSON object: %s" % path)
		return null
	return _parse_manifest_data(json.data, path, root_path)


func _parse_manifest_data(data: Dictionary, path: String, root_path: String) -> ModManifest:
	var id_value: Variant = data.get("id", "")
	var id := String(id_value).strip_edges()
	var version_value: Variant = data.get("version", "")
	var game_version_value: Variant = data.get("game_version", "")
	if typeof(id_value) != TYPE_STRING or not ModDependency.is_valid_mod_id(id_value):
		discovery_errors.append("Invalid or missing mod ID: %s" % path)
		return null
	if typeof(version_value) != TYPE_STRING or not ModVersion.is_valid(version_value):
		discovery_errors.append("Invalid or missing mod version: %s" % path)
		return null
	if typeof(game_version_value) != TYPE_STRING or not ModVersion.is_compatibility_line(game_version_value):
		discovery_errors.append("Invalid game_version in %s" % path)
		return null
	if id.contains("/") or id.contains("\\") or id.contains(":"):
		discovery_errors.append("Invalid characters in mod ID '%s'." % id)
		return null
	var dependency_values: Variant = data.get("dependencies", [])
	if typeof(dependency_values) != TYPE_ARRAY:
		discovery_errors.append("Dependencies must be an Array: %s." % path)
		return null
	var manifest := ModManifest.new()
	manifest.id = id
	manifest.version = version_value
	manifest.game_version = game_version_value
	manifest.display_name = String(data.get("display_name", id))
	manifest.description = String(data.get("description", ""))
	manifest.author = String(data.get("author", ""))
	manifest.root_path = root_path
	if not _parse_dependencies(manifest, dependency_values, path):
		return null
	return manifest


func _parse_dependencies(manifest: ModManifest, dependency_values: Array, path: String) -> bool:
	for entry in dependency_values:
		if typeof(entry) != TYPE_STRING:
			discovery_errors.append("Invalid dependency in %s" % path)
			return false
		var dependency := ModDependency.parse(entry)
		if dependency == null:
			discovery_errors.append("Invalid dependency '%s' in '%s'" % [entry, path])
			return false
		if not manifest.dependencies.has(dependency):
			manifest.dependencies.append(dependency)
	return true


func get_available_mods() -> Array[ModManifest]:
	var result: Array[ModManifest] = []
	for manifest in _manifests.values():
		result.append(manifest)
	result.sort_custom(func(a: ModManifest, b: ModManifest) -> bool:
		return a.id.naturalcasecmp_to(b.id) < 0
	)
	return result


func get_manifest(id: String) -> ModManifest:
	return _manifests.get(id)


func resolve(requested_ids: Array[String]) -> Array[ModManifest]:
	resolution_errors.clear()
	var ordered: Array[ModManifest] = []
	if not ModVersion.is_valid(game_version):
		resolution_errors.append("Invalid current game version: %s" % game_version)
		return ordered
	var enabled := _collect_enabled_mods(requested_ids)
	if not resolution_errors.is_empty():
		return ordered
	if not _validate_enabled_mods(enabled):
		return ordered
	return _sort_enabled_mods(enabled)


func _collect_enabled_mods(requested_ids: Array[String]) -> Dictionary[String, bool]:
	var enabled: Dictionary[String, bool] = {}
	var queue: Array[String] = [CORE_MOD_ID]
	for id in requested_ids:
		if not queue.has(id):
			queue.append(id)
	var index := 0
	while index < queue.size():
		var id := queue[index]
		index += 1
		if enabled.has(id):
			continue
		if _duplicated_ids.has(id):
			resolution_errors.append("Mod '%s' has a duplicated ID." % id)
			return enabled
		var manifest := get_manifest(id)
		if manifest == null:
			var required_by := queue.back() if not queue.is_empty() else "mod selection"
			resolution_errors.append("Mod '%s' was not found (required by '%s')." % [id, required_by])
			return enabled
		enabled[id] = true
		for dependency in manifest.dependencies:
			if dependency.is_required() and not enabled.has(dependency.id):
				if not queue.has(dependency.id):
					queue.append(dependency.id)
	return enabled


func _validate_enabled_mods(enabled: Dictionary[String, bool]) -> bool:
	for id in enabled:
		var manifest := _manifests[id]
		if not ModVersion.matches_game_version(game_version, manifest.game_version):
			resolution_errors.append("Mod '%s' targets game compatibility line %s, but the current game version is %s." % [id, manifest.game_version, game_version])
		for dependency in manifest.dependencies:
			_validate_dependency(manifest, dependency, enabled)
		if not resolution_errors.is_empty():
			return false
	return true


func _sort_enabled_mods(enabled: Dictionary[String, bool]) -> Array[ModManifest]:
	var ordered: Array[ModManifest] = []
	var states: Dictionary[String, int] = {}
	var depths: Dictionary[String, int] = {}
	var chain: Array[String] = []
	for id in enabled:
		if _calculate_depth(id, enabled, states, depths, chain) < 0:
			return ordered
	for id in enabled:
		ordered.append(_manifests[id])
	ordered.sort_custom(func(a: ModManifest, b: ModManifest) -> bool:
		if depths[a.id] != depths[b.id]:
			return depths[a.id] < depths[b.id]
		return a.id.naturalcasecmp_to(b.id) < 0
	)
	return ordered


func _validate_dependency(manifest: ModManifest, dependency: ModDependency,
							enabled: Dictionary[String, bool]) -> void:
	var exists := enabled.has(dependency.id)
	if dependency.type == ModDependency.Type.INCOMPATIBLE:
		if exists:
			resolution_errors.append("Mod '%s' is incompatible with '%s'."%[manifest.id, dependency.id])
		return
	
	if not exists:
		if dependency.is_required():
			resolution_errors.append("Mod '%s' requires '%s'." % [manifest.id, dependency.id])
		return
		
	var target := _manifests[dependency.id]
	if not ModVersion.satisfies(target.version, dependency.operator, dependency.version):
		resolution_errors.append("Mod '%s' requires '%s %s %s', but found %s." % [
			manifest.id, dependency.id, dependency.operator, dependency.version, target.version
		])


func _calculate_depth(id: String, enabled: Dictionary[String, bool], states: Dictionary[String, int],
						depths: Dictionary[String, int], chain: Array[String]) -> int:
	var state: int = states.get(id, NOT_VISITED)
	
	if state == RESOLVED:
		return depths[id]
	
	if state == IN_ANALYSIS:
		var cycle := chain.duplicate()
		cycle.append(id)
		resolution_errors.append("Circular dependency: %s"%[" -> ".join(PackedStringArray(cycle))])
		return -1
	
	states[id] = IN_ANALYSIS
	chain.append(id)
	
	var depth := 0
	var manifest := _manifests[id]
	
	for dependency:ModDependency in manifest.dependencies:
		if not dependency.affects_load_order() or not enabled.has(dependency.id):
			continue
		
		var dependency_depth := _calculate_depth(dependency.id, enabled, states, depths, chain)
		if dependency_depth < 0:
			return -1
		depth = maxi(depth, dependency_depth + 1)
	
	if id != CORE_MOD_ID:
		var core_depth := _calculate_depth(CORE_MOD_ID, enabled, states, depths, chain)
		if core_depth < 0:
			return -1
		depth = maxi(depth, core_depth + 1)
	
	chain.pop_back()
	states[id] = RESOLVED
	depths[id] = depth
	return depth
