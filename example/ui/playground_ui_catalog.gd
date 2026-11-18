class_name PlaygroundUiCatalog extends RefCounted

var errors: Array[String] = []
var style_registry: UIStyleRegistry
var component_registry: UIComponentRegistry

func build() -> bool:
	errors.clear()
	style_registry = UIStyleRegistry.new()
	component_registry = UIComponentRegistry.new()
	component_registry.style_registry = style_registry

	if not style_registry.register_style(_create_button_style()):
		errors.append_array(style_registry.errors)
		return false
	if not style_registry.finalize():
		errors.append_array(style_registry.errors)
		return false

	var definition := UIComponentDefinition.from_scene(
		"core:playground-button",
		_create_button_scene(),
		Callable(self, "_apply_button"),
		{
			"label": {"type": TYPE_STRING, "default": "Botão Lua", "mod_editable": true},
			"disabled": {"type": TYPE_BOOL, "default": false, "mod_editable": true},
			"style": {"type": TYPE_STRING, "default": "core:playground-button", "mod_editable": false}
		}
	)
	definition.events = [&"pressed"]
	definition.event_sources = {
		&"pressed": {"path": NodePath("."), "signal": &"pressed"}
	}

	if not component_registry.register_scene(definition):
		errors.append_array(component_registry.errors)
		return false
	if not component_registry.finalize():
		errors.append_array(component_registry.errors)
		return false

	return true


func _create_button_scene() -> PackedScene:
	var button := Button.new()
	button.name = "ModButton"
	button.focus_mode = Control.FOCUS_ALL
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(240, 48)
	var scene := PackedScene.new()
	var result := scene.pack(button)
	button.free()
	if result != OK:
		errors.append("Não foi possível criar a cena nativa de botão: %s" % error_string(result))
	return scene


func _create_button_style() -> UIStyleDefinition:
	var style := UIStyleDefinition.new()
	style.id = "core:playground-button"
	style.exposed_to_mods = true

	style.styleboxes = {
		"normal": _flat_box(Color("#27354a"), Color("#506684")),
		"hover": _flat_box(Color("#354963"), Color("#83bbda")),
		"pressed": _flat_box(Color("#1c3249"), Color("#a2dcef")),
		"hover_pressed": _flat_box(Color("#2c4560"), Color("#a2dcef")),
		"disabled": _flat_box(Color("#242c39"), Color("#414c5f")),
		"focus": _focus_box()
	}
	style.colors = {
		"font_color": Color("#edf5ff"),
		"font_hover_color": Color.WHITE,
		"font_pressed_color": Color.WHITE,
		"font_hover_pressed_color": Color.WHITE,
		"font_disabled_color": Color("#8693a6")
	}
	style.font_sizes = {"font_size": 16}
	style.layout = {
		"min_size": Vector2(240, 48),
		"padding": Vector4(14, 9, 14, 9),
		"stretch_x": "expand_fill"
	}
	style.states = {
		"normal": {"scale": Vector2.ONE},
		"hover": {"scale": Vector2(1.02, 1.02)},
		"pressed": {"scale": Vector2(0.98, 0.98)},
		"hover_pressed": {"scale": Vector2(0.98, 0.98)},
		"disabled": {"opacity": 0.65}
	}
	style.transition = {
		"properties": ["background_color", "scale", "opacity"],
		"duration": 0.15,
		"trans": Tween.TRANS_CUBIC,
		"ease": Tween.EASE_OUT,
		"iterations": 1
	}
	# O mod pode alterar o texto/estado; não pode substituir as cores e bordas.
	style.mod_overrides = ["layout.padding", "layout.stretch_x"]
	return style


func _flat_box(background: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	return box


func _focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = Color("#89d1ee")
	box.set_border_width_all(2)
	box.set_corner_radius_all(9)
	return box


func _apply_button(control: Control, values: Dictionary) -> void:
	var button := control as Button
	if values.has("label"):
		button.text = values["label"]
	if values.has("disabled"):
		button.disabled = values["disabled"]
