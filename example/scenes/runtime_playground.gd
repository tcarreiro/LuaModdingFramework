
extends Control

@onready var mod_ui_root: VBoxContainer = %ModUIRoot
@onready var active_mods: Label = %ActiveMods
@onready var template_count: Label = %TemplateCount
@onready var status_label: Label = %StatusLabel
@onready var tick_button: Button = %TickButton
@onready var reload_button: Button = %ReloadButton
@onready var menu_button: Button = %MenuButton
@onready var log_output: RichTextLabel = %LogOutput

@onready var work_area: BoxContainer = %WorkArea
@onready var actions: BoxContainer = %Actions
@onready var action_spacer: Control = %ActionSpacer
@onready var mod_panel: PanelContainer = $OuterMargin/Body/WorkArea/ModPanel
@onready var log_panel: PanelContainer = $OuterMargin/Body/WorkArea/LogPanel


func _ready() -> void:
	tick_button.pressed.connect(_on_tick_pressed)
	reload_button.pressed.connect(_on_reload_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	GameMods.runtime_log_changed.connect(_on_runtime_log_changed)

	resized.connect(_update_responsive_layout)
	_update_responsive_layout()

	var names: Array[String] = []
	for manifest in GameMods.selected_mods:
		names.append(manifest.id)

	active_mods.text = "Mods: %s" % ", ".join(PackedStringArray(names))

	var total := 0
	if GameMods.content_registry != null:
		var catalog: Dictionary = GameMods.content_registry.get_catalog()
		for type_id in catalog:
			total += (catalog[type_id] as Dictionary).size()

	template_count.text = "Templates: %d" % total

	if not GameMods.attach_ui_mount(mod_ui_root):
		_show_failure()
		return

	if not GameMods.start_new_runtime():
		_show_failure()
		return

	_update_view("Runtime ativo. Teste os botões criados pelos mods em Lua.")


func _exit_tree() -> void:
	GameMods.stop_runtime()
	GameMods.detach_ui_mount(mod_ui_root)


func _update_responsive_layout() -> void:
	# Em janelas estreitas, os quadros ficam um abaixo do outro.
	var stack_panels := size.x < 960.0

	if work_area.vertical != stack_panels:
		work_area.vertical = stack_panels

	mod_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL if stack_panels else Control.SIZE_FILL
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL if stack_panels else Control.SIZE_FILL

	# Em larguras menores, os botões de ação ocupam linhas separadas.
	var stack_actions := size.x < 620.0

	if actions.vertical != stack_actions:
		actions.vertical = stack_actions

	action_spacer.visible = not stack_actions


func _on_tick_pressed() -> void:
	if not GameMods.advance_tick():
		_show_failure()
		return

	_update_view("on_tick emitido: %d" % GameMods.world_time)


func _on_reload_pressed() -> void:
	if not GameMods.save_and_restore_runtime():
		_show_failure()
		return

	_update_view("Storage restaurado. A UI Lua foi recriada após on_load().")


func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://example/scenes/main_menu.tscn")


func _update_view(message: String) -> void:
	status_label.text = message
	tick_button.disabled = not GameMods.is_runtime_active()
	reload_button.disabled = not GameMods.is_runtime_active()
	_render_log()


func _show_failure() -> void:
	status_label.text = "Falha na inicialização/execução do Runtime."
	tick_button.disabled = true
	reload_button.disabled = true

	for error in GameMods.runtime_errors:
		push_error("[PlaygroundRuntime] %s" % error)

	_render_log()


func _on_runtime_log_changed(_message: String) -> void:
	_render_log()


func _render_log() -> void:
	var lines: Array[String] = []

	for message in GameMods.runtime_log:
		lines.append(message)

	for error in GameMods.runtime_errors:
		lines.append("ERRO: %s" % error)

	log_output.text = "\n".join(PackedStringArray(lines))
