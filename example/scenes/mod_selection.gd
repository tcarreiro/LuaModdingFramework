extends MarginContainer

@onready var mods_list: VBoxContainer = %ModsList
@onready var clear_button: Button = %ClearButton
@onready var ok_button: Button = %OkButton
@onready var feedback: Label = %Feedback

var _checkboxes: Dictionary[String, CheckBox] = {}
var _explicit_selected_ids: Array[String] = []

func _ready() -> void:
	clear_button.pressed.connect(_on_clear_pressed)
	ok_button.pressed.connect(_on_ok_pressed)
	_populate_mods()


func _populate_mods() -> void:
	_checkboxes.clear()

	var available_mods: Array[ModManifest] = GameMods.get_available_mods()

	for manifest in available_mods:
		var checkbox := CheckBox.new()
		checkbox.text = "%s (%s) - v%s" % [manifest.display_name, manifest.id, manifest.version]
		checkbox.tooltip_text = manifest.description
		checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		checkbox.toggled.connect(_on_mod_toggled.bind(manifest.id))
		mods_list.add_child(checkbox)

		_checkboxes[manifest.id] = checkbox

	if available_mods.is_empty():
		feedback.text = "Nenhum mod encontrado."
		return
	
	_explicit_selected_ids = GameMods.selected_mod_ids.duplicate()
	_refresh_selection()


func _on_mod_toggled(pressed: bool, id: String) -> void:
	if pressed:
		if not _explicit_selected_ids.has(id):
			_explicit_selected_ids.append(id)
	else:
		_explicit_selected_ids.erase(id)
	
	_refresh_selection()


func _refresh_selection() -> void:
	var resolved_mods: Array[ModManifest] = GameMods.mod_manager.resolve(_explicit_selected_ids)
	var resolved_ids: Dictionary[String, bool] = {}

	for manifest in resolved_mods:
		resolved_ids[manifest.id] = true

	var has_errors: bool = not GameMods.mod_manager.resolution_errors.is_empty()

	for id in _checkboxes:
		var checkbox := _checkboxes[id]
		var is_explicit := _explicit_selected_ids.has(id)
		var is_resolved := resolved_ids.has(id)
		var is_core := id == ModManager.CORE_MOD_ID

		var should_be_checked := is_explicit or is_resolved or is_core

		checkbox.set_pressed_no_signal(should_be_checked)
		checkbox.disabled = is_core or (not has_errors and is_resolved and not is_explicit)

	if has_errors:
		_show_resolution_errors()
	else:
		feedback.text = ""


func _on_clear_pressed() -> void:
	_explicit_selected_ids.clear()
	_refresh_selection()
	
	if GameMods.mod_manager.resolution_errors.is_empty():
		feedback.text = "Seleção limpa."




func _on_ok_pressed() -> void:
	if not GameMods.prepare_new_game(_explicit_selected_ids):
		feedback.text = "Erro ao preparar o jogo:\n%s" % "\n".join(PackedStringArray(GameMods.prepare_errors))
		return

	for warning in GameMods.prepare_warnings:
		push_warning("[SettingsState] %s" % warning)

	get_tree().change_scene_to_file("res://example/scenes/new_game_settings.tscn")


func _show_resolution_errors() -> void:
	var errors: Array[String] = GameMods.mod_manager.resolution_errors
	feedback.text = "Erro ao preparar os mods:\n%s" % "\n".join(PackedStringArray(errors))
