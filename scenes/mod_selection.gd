
extends MarginContainer

@onready var mods_list: VBoxContainer = %ModsList
@onready var clear_button: Button = %ClearButton
@onready var ok_button: Button = %OkButton
@onready var feedback: Label = %Feedback

var _checkboxes: Dictionary[String, CheckBox] = {}

func _ready() -> void:
	clear_button.pressed.connect(_on_clear_pressed)
	ok_button.pressed.connect(_on_ok_pressed)
	_populate_mods()


func _populate_mods() -> void:
	_checkboxes.clear()

	var available_mods := GameMods.get_available_mods()

	for manifest in available_mods:
		var checkbox := CheckBox.new()
		checkbox.text = "%s (%s) - v%s" % [manifest.display_name, manifest.id, manifest.version]
		checkbox.tooltip_text = manifest.description
		checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		if manifest.id == ModManager.CORE_MOD_ID:
			checkbox.button_pressed = true
			checkbox.disabled = true

		checkbox.toggled.connect(_on_mod_toggled)
		mods_list.add_child(checkbox)

		_checkboxes[manifest.id] = checkbox

	if available_mods.is_empty():
		feedback.text = "Nenhum mod encontrado."


func _on_mod_toggled(_pressed: bool) -> void:
	feedback.text = ""


func _on_clear_pressed() -> void:
	for id in _checkboxes:
		if id == ModManager.CORE_MOD_ID:
			continue

		_checkboxes[id].button_pressed = false

	feedback.text = "Seleção limpa."


func _on_ok_pressed() -> void:
	var selected_ids: Array[String] = []

	for id in _checkboxes:
		if id == ModManager.CORE_MOD_ID:
			continue

		if _checkboxes[id].button_pressed:
			selected_ids.append(id)

	if not GameMods.prepare_new_game(selected_ids):
		_show_resolution_errors()
		return

	var resolved_ids: Array[String] = []

	for manifest in GameMods.selected_mods:
		resolved_ids.append(manifest.id)

	feedback.text = "Mods preparados: %s" % ", ".join(PackedStringArray(resolved_ids))

	print("[ModSelection] Mods prepared successfully:")
	for manifest in GameMods.selected_mods:
		print(" - %s (%s)" % [manifest.id, manifest.version])


func _show_resolution_errors() -> void:
	var errors := GameMods.mod_manager.resolution_errors
	feedback.text = "Erro ao preparar os mods:\n%s" % "\n".join(PackedStringArray(errors))
