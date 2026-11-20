class_name UIComponentTextureButton extends TextureButton

var _assets: ModAssetRegistry


func set_asset_registry(registry: ModAssetRegistry) -> void:
	_assets = registry


func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(UIBuiltinIds.TEXTURE_BUTTON, {
		"texture": UIPremadeContract.property(TYPE_STRING, ""),
		"texture_hover": UIPremadeContract.property(TYPE_STRING, ""),
		"texture_pressed": UIPremadeContract.property(TYPE_STRING, ""),
		"texture_disabled": UIPremadeContract.property(TYPE_STRING, ""),
		"texture_focused": UIPremadeContract.property(TYPE_STRING, ""),
		"disabled": UIPremadeContract.property(TYPE_BOOL, false),
		"ignore_texture_size": UIPremadeContract.property(TYPE_BOOL, false),
		"stretch_mode": UIPremadeContract.property(TYPE_STRING, "keep_aspect")
	}, "", [&"pressed", &"button_down", &"button_up", &"toggled", &"mouse_entered", &"mouse_exited", &"focus_entered", &"focus_exited"])


func apply_premade_properties(values: Dictionary) -> void:
	if values.has("texture"):
		texture_normal = _resolve(values["texture"])
	if values.has("texture_hover"):
		texture_hover = _resolve(values["texture_hover"])
	if values.has("texture_pressed"):
		texture_pressed = _resolve(values["texture_pressed"])
	if values.has("texture_disabled"):
		texture_disabled = _resolve(values["texture_disabled"])
	if values.has("texture_focused"):
		texture_focused = _resolve(values["texture_focused"])
	if values.has("disabled"):
		disabled = values["disabled"]
	if values.has("ignore_texture_size"):
		ignore_texture_size = values["ignore_texture_size"]
	if values.has("stretch_mode"):
		match values["stretch_mode"]:
			"scale": stretch_mode = TextureButton.STRETCH_SCALE
			"tile": stretch_mode = TextureButton.STRETCH_TILE
			"keep": stretch_mode = TextureButton.STRETCH_KEEP
			"keep_centered": stretch_mode = TextureButton.STRETCH_KEEP_CENTERED
			"keep_aspect_centered": stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			"keep_aspect_covered": stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
			_: stretch_mode = TextureButton.STRETCH_KEEP_ASPECT
	UIPremadeContract.apply_common(self, values)


func _resolve(asset_id: String) -> Texture2D:
	if asset_id.is_empty() or _assets == null:
		return null
	return _assets.get_texture(asset_id)
