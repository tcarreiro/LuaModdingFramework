extends MarginContainer

@onready var active_mods: Label = %ActiveMods
@onready var settings_list: VBoxContainer = %SettingsList
@onready var back_button: Button = %BackButton
@onready var reset_button: Button = %ResetButton
@onready var confirm_button: Button = %ConfirmButton
@onready var feedback: Label = %Feedback

var _inputs: Dictionary[String, Control] = {}

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)

	_build_settings()


func _build_settings() -> void:
	var registry = GameMods.settings_registry

	if registry == null:
		feedback.text = "No settings registry available."
		confirm_button.disabled = true
		return

	var mod_ids: Array[String] = []
	for manifest in GameMods.selected_mods:
		mod_ids.append(manifest.id)

	active_mods.text = "Mods ativos: %s" % ", ".join(PackedStringArray(mod_ids))

	for setting in registry.get_visible_settings():
		_add_setting(setting)

	if _inputs.is_empty():
		feedback.text = "Nenhuma configuração disponível para o jogador."


func _add_setting(setting: ModSetting) -> void:
	var panel := PanelContainer.new()
	var content := VBoxContainer.new()
	var header := HBoxContainer.new()
	var label := Label.new()
	var input := _create_input(setting)

	label.text = setting.display_name if not setting.display_name.is_empty() else setting.id
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	input.custom_minimum_size = Vector2(220, 0)
	input.tooltip_text = setting.description

	header.add_child(label)
	header.add_child(input)
	content.add_child(header)

	if not setting.description.is_empty():
		var description := Label.new()
		description.text = setting.description
		description.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(description)

	panel.add_child(content)
	settings_list.add_child(panel)

	_inputs[setting.id] = input


func _create_input(setting: ModSetting) -> Control:
	var value: Variant = GameMods.selected_settings.get(setting.id, setting.get_effective_value())

	if not setting.allowed_values.is_empty():
		var options := OptionButton.new()

		for option in setting.allowed_values:
			options.add_item(str(option))
			var index := options.item_count - 1
			options.set_item_metadata(index, option)

			if option == value:
				options.select(index)

		return options

	match setting.value_type:
		ModSetting.BOOL:
			var checkbox := CheckBox.new()
			checkbox.button_pressed = value
			return checkbox

		ModSetting.INT, ModSetting.DOUBLE:
			var input := LineEdit.new()
			input.text = str(value)
			input.placeholder_text = "Integer" if setting.value_type == ModSetting.INT else "Decimal"

			if setting.minimum_value != null or setting.maximum_value != null:
				input.tooltip_text = "Min: %s | Max: %s" % [str(setting.minimum_value), str(setting.maximum_value)]

			return input

		ModSetting.COLOR:
			var picker := ColorPickerButton.new()
			picker.color = value
			return picker

		ModSetting.STRING:
			var input := LineEdit.new()
			input.text = str(value)
			return input

	return Control.new()


func _read_value(setting: ModSetting, input: Control) -> Variant:
	if input is OptionButton:
		var options := input as OptionButton
		return options.get_selected_metadata()

	if input is CheckBox:
		var checkbox := input as CheckBox
		return checkbox.button_pressed

	if input is ColorPickerButton:
		var picker := input as ColorPickerButton
		return picker.color

	if input is LineEdit:
		var field := input as LineEdit
		var text := field.text.strip_edges()

		match setting.value_type:
			ModSetting.INT:
				if not text.is_valid_int():
					return null
				return text.to_int()

			ModSetting.DOUBLE:
				if not text.is_valid_float():
					return null

				var number := text.to_float()
				if not is_finite(number):
					return null

				return number

			ModSetting.STRING:
				return field.text

	return null


func _set_input_value(input: Control, value: Variant) -> void:
	if input is OptionButton:
		var options := input as OptionButton

		for i in range(options.item_count):
			if options.get_item_metadata(i) == value:
				options.select(i)
				return

	elif input is CheckBox:
		var checkbox := input as CheckBox
		checkbox.button_pressed = value

	elif input is ColorPickerButton:
		var picker := input as ColorPickerButton
		picker.color = value

	elif input is LineEdit:
		var field := input as LineEdit
		field.text = str(value)


func _on_reset_pressed() -> void:
	for setting in GameMods.settings_registry.get_visible_settings():
		if _inputs.has(setting.id):
			_set_input_value(_inputs[setting.id], setting.default_value)

	feedback.text = "Valores padrão restaurados."


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://example/scenes/mod_selection.tscn")


func _on_confirm_pressed() -> void:
	var registry = GameMods.settings_registry
	var selected_values: Dictionary[String, Variant] = {}

	for setting in registry.get_all_settings():
		var value: Variant = setting.get_effective_value()

		if not setting.hidden:
			var input = _inputs.get(setting.id)
			if input == null:
				feedback.text = "Missing input for '%s'." % setting.id
				return

			value = _read_value(setting, input)

			if value == null:
				feedback.text = "Invalid value for '%s'." % setting.display_name
				input.grab_focus()
				return

			var error = registry.validate_player_value(setting.id, value)
			if not error.is_empty():
				feedback.text = "Invalid value for '%s': %s" % [setting.display_name, error]
				input.grab_focus()
				return

		selected_values[setting.id] = value

	GameMods.selected_settings = selected_values
	
	if not GameMods.run_content_stage():
		feedback.text = "Erro ao carregar o Content Stage. Consulte o Output."

		for error in GameMods.content_errors:
			push_error("[ContentStage] %s" % error)

		return

	var catalog = GameMods.content_registry.get_catalog()
	var template_count := 0

	for type_id in catalog:
		var templates: Dictionary = catalog[type_id]
		template_count += templates.size()

	feedback.text = "Configurações confirmadas! %d Templates carregados." % template_count

	print("\n[ContentStage] Finalized catalog:")

	for type_id in catalog:
		print("Type: %s" % type_id)

		var templates: Dictionary = catalog[type_id]

		for template_id in templates:
			var template: Dictionary = templates[template_id]
			var metadata = GameMods.content_registry.get_metadata(type_id, template_id)

			print("  - %s: %s" % [template_id, str(template)])
			print("    Owner: %s | Last modified by: %s" % [
				metadata["owner_mod_id"],
				metadata["last_modified_by"]
			])
	
	print("\n[ContentStage] Loot family:")

	var content_registry = GameMods.content_registry
	
	var loot_family = content_registry.get_templates_in_family("loot")

	for template_id in loot_family:
		var template: Dictionary = loot_family[template_id]
		print("  - %s [%s]" % [template_id, template["type"]])

	print("\n[ContentStage] Exact loot bucket:")
	print(content_registry.get_templates("loot").keys())

	print("\n[ContentStage] Polymorphic lookup:")
	print(content_registry.get_template_in_family("loot", "training_gauntlet"))
