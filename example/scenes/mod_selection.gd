extends Control

@onready var mods_list: VBoxContainer = %ModsList
@onready var clear_button: Button = %ClearButton
@onready var ok_button: Button = %OkButton
@onready var back_button: Button = %BackButton
@onready var feedback: Label = %Feedback
@onready var description: Label = %Description

var _checkboxes: Dictionary[String, CheckBox] = {}
var _explicit_selected_ids: Array[String] = []


func _ready() -> void:
	clear_button.pressed.connect(_on_clear_pressed)
	ok_button.pressed.connect(_on_ok_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_populate_mods()


func _populate_mods() -> void:
	_checkboxes.clear()
	_explicit_selected_ids = GameMods.selected_mod_ids.duplicate()

	var available_mods: Array[ModManifest] = GameMods.get_available_mods()
	for manifest in available_mods:
		var checkbox := CheckBox.new()
		checkbox.text = "%s  ·  %s  ·  v%s" % [manifest.display_name, manifest.id, manifest.version]
		checkbox.tooltip_text = manifest.description
		checkbox.custom_minimum_size = Vector2(0, 42)
		checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		checkbox.toggled.connect(_on_mod_toggled.bind(manifest.id))
		mods_list.add_child(checkbox)
		_checkboxes[manifest.id] = checkbox

	if available_mods.is_empty():
		description.text = "Nenhum mod encontrado. O Core continuará disponível se estiver instalado."
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

	var has_errors := not GameMods.mod_manager.resolution_errors.is_empty()
	for id in _checkboxes:
		var checkbox := _checkboxes[id]
		var is_explicit := _explicit_selected_ids.has(id)
		var is_resolved := resolved_ids.has(id)
		var is_core := id == ModManager.CORE_MOD_ID
		checkbox.set_pressed_no_signal(is_explicit or is_resolved or is_core)
		checkbox.disabled = is_core or (not has_errors and is_resolved and not is_explicit)

	ok_button.disabled = has_errors
	if has_errors:
		feedback.text = "Dependências inválidas:\n%s" % "\n".join(PackedStringArray(GameMods.mod_manager.resolution_errors))
	else:
		var ids: Array[String] = []
		for manifest in resolved_mods:
			ids.append(manifest.id)
		feedback.text = "Serão carregados: %s" % ", ".join(PackedStringArray(ids))


func _on_clear_pressed() -> void:
	_explicit_selected_ids.clear()
	_refresh_selection()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://example/scenes/main_menu.tscn")


func _on_ok_pressed() -> void:
	if not GameMods.prepare_new_game(_explicit_selected_ids):
		feedback.text = "Erro ao preparar o jogo:\n%s" % "\n".join(PackedStringArray(GameMods.prepare_errors))
		return

	for warning in GameMods.prepare_warnings:
		push_warning("[SettingsState] %s" % warning)

	get_tree().change_scene_to_file("res://example/scenes/new_game_settings.tscn")
