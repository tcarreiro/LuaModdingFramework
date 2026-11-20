class_name ConsumerCatalog extends RefCounted

const PAGES_PATH := "res://example/consumer/pages"
const MODS_PATH := "res://example/consumer/mods"
const GAME_VERSION := "1.0.0"

var errors: Array[String] = []
var mod_manager: ModManager
var assets: ModAssetRegistry
var styles: UIStyleRegistry
var animations: UIAnimationRegistry
var components: UIComponentRegistry
var premades: UIPremadeCatalog
var content: ContentRegistry
var installed_mods: Array[ModManifest] = []


func initialize() -> bool:
	errors.clear()
	mod_manager = ModManager.new(GAME_VERSION, MODS_PATH, "user://consumer/mods")
	mod_manager.discover()
	if not mod_manager.discovery_errors.is_empty():
		errors.append_array(mod_manager.discovery_errors)
		return false
	installed_mods = mod_manager.get_available_mods()
	assets = ModAssetRegistry.new()
	assets.configure(installed_mods)
	styles = UIStyleRegistry.new()
	styles.texture_resolver = Callable(assets, "get_texture")
	styles.sound_resolver = Callable(assets, "get_sound")
	components = UIComponentRegistry.new()
	components.style_registry = styles
	animations = UIAnimationRegistry.new()
	components.animation_registry = animations
	premades = UIPremadeCatalog.new(assets)
	if not premades.install(components, styles):
		errors.append_array(premades.errors)
		return false

	var versions: Dictionary = {}
	for manifest in installed_mods:
		versions[manifest.id] = manifest.version
	var state := ContentState.new(ContentTypeRegistry.new(), components, ["core"])
	state.start({}, versions)
	var paths: Array[String] = []
	var directory := DirAccess.open(PAGES_PATH)
	if directory == null:
		errors.append("Cannot read consumer pages folder: " + PAGES_PATH)
		return false
	for file_name in directory.get_files():
		if file_name.ends_with(".lua") and file_name != "main_menu.lua":
			paths.append(PAGES_PATH.path_join(file_name))
	paths.sort()
	paths.push_front(PAGES_PATH.path_join("main_menu.lua"))
	for path in paths:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			errors.append("Cannot read Lua page: " + path)
			state.close()
			return false
		if not state.execute(file.get_as_text(), "core", path):
			errors.append_array(state.get_errors())
			state.close()
			return false
	content = state.finish()
	if content == null:
		errors.append_array(state.get_errors())
		return false
	if not styles.finalize():
		errors.append_array(styles.errors)
		return false
	if not animations.finalize():
		errors.append_array(animations.errors)
		return false
	if not components.finalize():
		errors.append_array(components.errors)
		return false
	return true


func resolve(requested: Array[String]) -> Array[ModManifest]:
	var result := mod_manager.resolve(requested)
	if not mod_manager.resolution_errors.is_empty():
		errors.append_array(mod_manager.resolution_errors)
	return result


func settings_for(requested: Array[String]) -> SettingsRegistry:
	var resolved := resolve(requested)
	if resolved.is_empty():
		return null
	var loader := SettingsLoader.new()
	var registry := loader.run(resolved)
	if registry == null:
		errors.append_array(loader.errors)
	return registry
