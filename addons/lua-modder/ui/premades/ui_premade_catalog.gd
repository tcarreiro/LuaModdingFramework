class_name UIPremadeCatalog extends RefCounted

const SCENES_PATH := "res://addons/lua-modder/ui/premades/"

var errors: Array[String] = []
var assets: ModAssetRegistry

func _init(asset_registry: ModAssetRegistry = null) -> void:
	assets = asset_registry


func install(components: UIComponentRegistry, styles: UIStyleRegistry) -> bool:
	errors.clear()
	if components.is_finalized() or styles.is_finalized():
		return _fail("Cannot install premades after finalization.")
	
	var paths: Array[String] = []
	_discover_scenes(SCENES_PATH, paths)
	paths.sort()
	if paths.is_empty():
		return _fail("No builtin UI scenes were found.")
	
	for path in paths:
		if not _install_scene(path, components, styles):
			return false
	
	return true


func _discover_scenes(directory: String, result: Array[String]) -> void:
	for entry in ResourceLoader.list_directory(directory):
		var path := directory.path_join(entry)
	
		if entry.ends_with("/"):
			_discover_scenes(path, result)
		elif entry.get_extension().to_lower() == "tscn":
			result.append(path)


func _install_scene(path: String, components: UIComponentRegistry,
		styles: UIStyleRegistry) -> bool:
	var scene := ResourceLoader.load(path, "PackedScene") as PackedScene
	
	if scene == null:
		return _fail("Cannot load builtin scene '%s'." % path)
	
	var root := scene.instantiate()
	if root == null:
		return _fail("Cannot instantiate builtin scene '%s'." % path)
	
	var installed := _register_premade(root, scene, path, components, styles)
	root.free()
	return installed


func _register_premade(root: Node, scene: PackedScene, path: String,
		components: UIComponentRegistry, styles: UIStyleRegistry) -> bool:
	if not root is Control:
		return _fail("Premade '%s' must have a Control root." % path)
	
	if root.get_script() == null:
		return _fail("Premade '%s' must have a root script." % path)
	
	if not root.has_method("get_premade_definition"):
		return _fail("Premade '%s' has no get_premade_definition()." % path)
	
	if not root.has_method("apply_premade_properties"):
		return _fail("Premade '%s' has no apply_premade_properties()." % path)
	
	var raw_definition: Variant = root.call("get_premade_definition")
	if not raw_definition is UIComponentDefinition:
		return _fail("Premade '%s' returned an invalid definition." % path)
	
	var definition := raw_definition as UIComponentDefinition
	if not definition.id.begins_with(UIBuiltinIds.NAMESPACE):
		return _fail("Invalid builtin component ID '%s'." % definition.id)
	
	if definition.kind != UIComponentDefinition.Kind.SCENE:
		return _fail("Premade '%s' must be a SCENE component." % definition.id)
	
	if root.has_method("get_premade_styles"):
		if not _register_styles(root, styles, path):
			return false
	
	definition.owner_mod_id = ""
	definition.scene = scene
	definition.apply_properties = UIPremadeCatalog._apply_properties.bind(assets)
	
	if not components.register_scene(definition):
		errors.append_array(components.errors)
		return false
	
	return true


func _register_styles(root: Node, registry: UIStyleRegistry, path: String) -> bool:
	var result: Variant = root.call("get_premade_styles")
	if not result is Array:
		return _fail("Premade '%s' must return an Array of styles." % path)
	
	for entry in result:
		if not entry is UIStyleDefinition:
			return _fail("Premade '%s' returned an invalid style." % path)
	
		var style := entry as UIStyleDefinition
		if not style.id.begins_with(UIBuiltinIds.NAMESPACE):
			return _fail("Invalid builtin style ID '%s'." % style.id)
	
		if not registry.register_style(style):
			errors.append_array(registry.errors)
			return false
	
	return true




static func _apply_properties(control: Control, values: Dictionary, registered_assets: ModAssetRegistry) -> void:
	if control.has_method("set_asset_registry"):
		control.call("set_asset_registry", registered_assets)
	control.call("apply_premade_properties", values)

func _fail(message: String) -> bool:
	errors.append(message)
	return false
