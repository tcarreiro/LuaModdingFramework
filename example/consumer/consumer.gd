extends Control

const STORE_SCRIPT := preload("res://example/consumer/consumer_store.gd")
const CATALOG_SCRIPT := preload("res://example/consumer/consumer_catalog.gd")

@onready var _ui_root: UIRootHost = $UIRoot
@onready var _screen_mount: Control = $ScreenMount
@onready var _modal_backdrop: ColorRect = $ModalBackdrop
@onready var _modal_mount: CenterContainer = $ModalMount
@onready var _hud_mount: Control = $HudMount
@onready var _loading_layer: ColorRect = $LoadingLayer
@onready var _loading_mount: CenterContainer = $LoadingLayer/LoadingMount
@onready var _world_view: SubViewportContainer = $WorldViewportContainer
@onready var _world: Node3D = $WorldViewportContainer/WorldViewport/World

var _catalog: ConsumerCatalog
var _store: ConsumerStore
var _runtime: RuntimeManager
var _instances: Array[UIComponentInstance] = []
var _page: UIComponentInstance
var _dialog: UIComponentInstance
var _dialog_content: UIComponentInstance
var _hud: UIComponentInstance
var _screen_name := ""
var _dialog_name := ""
var _option_tab := "audio"
var _options_draft: Dictionary = {}
var _selected_slot := 1
var _slot_has_save := false
var _selected_mod_ids: Array[String] = []
var _draft_mod_ids: Array[String] = []
var _temp_mod_ids: Array[String] = []
var _inspected_mod := ""
var _selected_owner := "core"
var _settings_registry: SettingsRegistry
var _settings_draft: Dictionary = {}
var _game_active := false
var _loading_game := false
var _active_mod_ids: Array[String] = []
var _active_settings: Dictionary = {}
var _play_seconds := 0.0
var _inventory: Array = []
var _selected_inventory_slot := -1
var _load_payload: Dictionary = {}
var _pending_delete := -1


func _ready() -> void:
	set_meta(UIRootHost.ROOT_META, weakref(_ui_root))
	_catalog = CATALOG_SCRIPT.new()
	_store = STORE_SCRIPT.new()
	_store.changed.connect(_on_store_changed)
	if not _catalog.initialize():
		_show_fatal("Falha na inicialização do consumidor:\n" + "\n".join(PackedStringArray(_catalog.errors)))
		return
	_store.options = ConsumerStore.DEFAULT_OPTIONS.duplicate(true)
	_show_menu()


func _process(delta: float) -> void:
	if _game_active and _dialog_name == "" and not _loading_game:
		_play_seconds += delta


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if _loading_game:
		return
	if event.is_action_pressed("ui_inventory") and _game_active:
		if _dialog_name == "inventory":
			_close_dialog()
		elif _dialog_name == "":
			_open_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if not _dialog_name.is_empty():
			_cancel_dialog()
		elif _game_active:
			_open_pause()
		elif _screen_name != "menu":
			_show_menu()
		get_viewport().set_input_as_handled()


func _show_fatal(message: String) -> void:
	push_error(message)
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_color_override(&"font_color", Color("#FFD0C7"))
	_screen_mount.add_child(label)


func _instantiate(id: String, properties: Dictionary = {}) -> UIComponentInstance:
	var instance := _catalog.components.instantiate_component(id, properties, true)
	if instance == null:
		push_error("Consumer UI '%s': %s" % [id, str(_catalog.components.errors)])
		return null
	_instances.append(instance)
	return instance


func _add(parent: Control, id: String, properties: Dictionary = {}) -> UIComponentInstance:
	var instance := _instantiate(id, properties)
	if instance != null and parent != null:
		parent.add_child(instance.root)
	return instance


func _named(instance: UIComponentInstance, p_name: String) -> UIComponentInstance:
	if instance == null:
		return null
	return instance._named_children.get(p_name) as UIComponentInstance


func _slot(instance: UIComponentInstance, p_name: String) -> Control:
	var child := _named(instance, p_name)
	return child.get_slot() if child != null else null


func _on(instance: UIComponentInstance, event: String, handler: Callable) -> void:
	if instance != null and not instance.on_event(StringName(event), handler):
		push_error("Cannot bind UI event '%s' for '%s': %s" % [event, instance.component_id, str(instance.interaction.errors)])


func _remove_children(control: Control) -> void:
	if control == null:
		return
	for child in control.get_children():
		control.remove_child(child)
		child.queue_free()


func _mount_screen(id: String, props: Dictionary = {}) -> UIComponentInstance:
	_remove_children(_screen_mount)
	_page = _add(_screen_mount, id, props)
	if _page != null:
		_page.root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return _page


func _show_menu() -> void:
	_game_active = false
	_loading_game = false
	_world_view.visible = false
	_hud_mount.visible = false
	_screen_mount.visible = true
	_close_dialog()
	_screen_name = "menu"
	var page := _mount_screen("core:main-menu", {"version": "v%s" % ConsumerCatalog.GAME_VERSION})
	var image := _named(page, "logo")
	if image != null and image.content_root is TextureRect:
		(image.content_root as TextureRect).stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_on(page, "play", func(_event: Dictionary) -> void: _show_saves())
	_on(page, "settings", func(_event: Dictionary) -> void: _show_options())
	_on(page, "exit", func(_event: Dictionary) -> void: _confirm_application_exit())


func _show_options() -> void:
	_screen_name = "options"
	_option_tab = "audio"
	_options_draft = _store.options.duplicate(true)
	var page := _mount_screen("core:options-screen")
	_on(page, "audio", func(_event: Dictionary) -> void: _select_option_tab("audio"))
	_on(page, "graphics", func(_event: Dictionary) -> void: _select_option_tab("graphics"))
	_on(page, "game", func(_event: Dictionary) -> void: _select_option_tab("game"))
	_on(page, "controls", func(_event: Dictionary) -> void: _select_option_tab("controls"))
	_on(page, "back", func(_event: Dictionary) -> void: _show_menu())
	_on(page, "restore", func(_event: Dictionary) -> void: _reset_options())
	_on(page, "apply", func(_event: Dictionary) -> void: _apply_options())
	_render_options()


func _select_option_tab(tab: String) -> void:
	_option_tab = tab
	_render_options()


func _render_options() -> void:
	if _screen_name != "options":
		return
	var content := _slot(_page, "options")
	_remove_children(content)
	var definitions: Array[Dictionary] = []
	match _option_tab:
		"audio":
			definitions = [
				{"id": "master_volume", "label": "Volume principal", "kind": "range"},
				{"id": "music_volume", "label": "Música", "kind": "range"},
				{"id": "effects_volume", "label": "Efeitos sonoros", "kind": "range"},
				{"id": "spatial_audio", "label": "Áudio espacial", "kind": "bool"}
			]
		"graphics":
			definitions = [
				{"id": "resolution", "label": "Resolução", "kind": "choice", "choices": ["1280 × 720", "1920 × 1080", "2560 × 1440"]},
				{"id": "quality", "label": "Qualidade", "kind": "choice", "choices": ["Baixa", "Média", "Alta", "Ultra"]},
				{"id": "vsync", "label": "Sincronização vertical", "kind": "bool"}
			]
		"game":
			definitions = [
				{"id": "language", "label": "Idioma", "kind": "choice", "choices": ["Português", "English", "Español"]},
				{"id": "auto_save", "label": "Salvamento automático (mock)", "kind": "bool"},
				{"id": "subtitles", "label": "Legendas", "kind": "bool"}
			]
		"controls":
			definitions = [
				{"id": "mouse_sensitivity", "label": "Sensibilidade do mouse", "kind": "range"},
				{"id": "invert_y", "label": "Inverter eixo vertical", "kind": "bool"}
			]
	for entry in definitions:
		var id: String = entry["id"]
		var kind: String = entry["kind"]
		var props: Dictionary = {"label": entry["label"]}
		if kind == "bool":
			props["checked"] = bool(_options_draft[id])
		elif kind == "choice":
			props["options"] = entry["choices"]
			props["selected"] = entry["choices"].find(_options_draft[id])
		else:
			props["value"] = float(_options_draft[id])
			props["minimum"] = 0.0
			props["maximum"] = 100.0
		var widget := _add(content, "core:option-%s" % ("range" if kind == "range" else "choice" if kind == "choice" else "bool"), props)
		_on(widget, "changed", Callable(self, "_on_option_changed").bind(id, kind, entry.get("choices", [])))


func _on_option_changed(event: Dictionary, id: String, kind: String, choices: Array) -> void:
	var arguments: Array = event.get("arguments", [])
	if arguments.is_empty():
		return
	var value: Variant = arguments[0]
	if kind == "choice":
		var index := int(value)
		if index < 0 or index >= choices.size():
			return
		value = choices[index]
	_options_draft[id] = value


func _reset_options() -> void:
	_options_draft = ConsumerStore.DEFAULT_OPTIONS.duplicate(true)
	_render_options()


func _apply_options() -> void:
	for key in _options_draft:
		_store.set_option(key, _options_draft[key])
	_show_menu()


func _show_saves() -> void:
	_screen_name = "saves"
	var page := _mount_screen("core:save-screen")
	_on(page, "back", func(_event: Dictionary) -> void: _show_menu())
	var cards := _slot(page, "cards")
	if cards is BoxContainer:
		(cards as BoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	_render_save_cards()


func _render_save_cards() -> void:
	if _screen_name != "saves":
		return
	var container := _slot(_page, "cards")
	_remove_children(container)
	if container == null:
		return
	var width := get_viewport_rect().size.x * 0.26
	var height := get_viewport_rect().size.y * 0.65
	for index in range(1, 4):
		var save := _store.get_slot(index)
		var has_save := not save.is_empty()
		var label := "- Novo Jogo -"
		if has_save:
			var duration := int(save.get("duration_secs", 0))
			label = "EXPEDIÇÃO %d\n\nTempo de jogo:\n%02d:%02d\n\nÚltima vez jogado:\n%s" % [
				index, duration / 3600.0, int(duration / 60.0) % 60, save.get("last_played", "--/--/----")]
		var card := _add(container, "core:save-card", {"text": label, "has_save": has_save})
		if card == null:
			continue
		card.root.custom_minimum_size = Vector2(width, height)
		var choose := _named(card, "choose")
		if choose != null:
			choose.root.custom_minimum_size = Vector2(width, height)
			if has_save and choose.content_root is Button:
				(choose.content_root as Button).alignment = HORIZONTAL_ALIGNMENT_LEFT
		var delete := _named(card, "delete")
		if delete != null:
			delete.root.custom_minimum_size = Vector2(50, 48)
		_on(card, "choose", Callable(self, "_select_save_slot").bind(index))
		_on(card, "delete", Callable(self, "_request_delete_slot").bind(index))


func _select_save_slot(_event: Dictionary, index: int) -> void:
	_selected_slot = index
	var save := _store.get_slot(index)
	_slot_has_save = not save.is_empty()
	_load_payload = save
	_draft_mod_ids = _selected_mod_ids.duplicate()
	if _slot_has_save:
		for saved_id in save.get("mods", []):
			var mod_id := str(saved_id)
			if mod_id != "core" and mod_id not in _draft_mod_ids:
				_draft_mod_ids.append(mod_id)
	_present_dialog("action")


func _request_delete_slot(_event: Dictionary, index: int) -> void:
	_pending_delete = index
	_present_dialog("confirm_delete")


func _on_store_changed(section: String, _key: String, _value: Variant) -> void:
	if section == "saves" and _screen_name == "saves":
		_render_save_cards()

#region One reusable modal with interchangeable Lua-authored content
func _ensure_dialog() -> bool:
	if _dialog != null and is_instance_valid(_dialog.root):
		return true
	_dialog = _add(_modal_mount, "ui:modal", {
		"title": "", "draggable": false, "closeable": false, "style": "core:modal"
	})
	return _dialog != null


func _present_dialog(kind: String) -> void:
	if not _ensure_dialog():
		return
	_dialog_name = kind
	_modal_backdrop.visible = true
	_modal_mount.visible = true
	_dialog.root.visible = true
	var viewport_size := get_viewport_rect().size
	var wide := kind in ["mods", "mod_settings", "inventory"]
	_dialog.root.custom_minimum_size = Vector2(
		viewport_size.x * (0.86 if wide else 0.40),
		viewport_size.y * (0.85 if wide else 0.47)
	)
	var heading := {
		"action": "Expedição",
		"mods": "Mods da expedição",
		"mod_settings": "Configurações da expedição",
		"confirm_delete": "Excluir save",
		"inventory": "Inventário",
		"pause": "Pausa",
		"confirm_pause_exit": "Sair do jogo",
		"confirm_application_exit": "Sair do aplicativo"
	}
	_dialog.update({"title": str(heading.get(kind, "")), "draggable": false, "closeable": false})
	var root := _dialog.get_slot()
	if root != null:
		root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_remove_children(root)
	_dialog_content = null
	match kind:
		"action":
			_render_action_dialog(root)
		"mods":
			_render_mods_dialog(root)
		"mod_settings":
			_render_mod_settings_dialog(root)
		"confirm_delete":
			_render_confirmation(root, "Excluir esta expedição?", "O arquivo .save será excluído permanentemente.", "delete")
		"confirm_pause_exit":
			_render_confirmation(root, "Sair da expedição?", "Progresso não salvo será perdido.", "exit_game")
		"confirm_application_exit":
			_render_confirmation(root, "Fechar o aplicativo?", "Tem certeza de que deseja sair?", "exit_app")
		"inventory":
			_render_inventory_dialog(root)
		"pause":
			_render_pause_dialog(root)
	_world.process_mode = Node.PROCESS_MODE_DISABLED if _game_active else Node.PROCESS_MODE_INHERIT


func _close_dialog() -> void:
	_dialog_name = ""
	_modal_backdrop.visible = false
	_modal_mount.visible = false
	if _dialog != null and is_instance_valid(_dialog.root):
		_dialog.root.visible = false
	_world.process_mode = Node.PROCESS_MODE_INHERIT


func _cancel_dialog() -> void:
	match _dialog_name:
		"mods":
			_temp_mod_ids.clear()
			_present_dialog("action")
		"mod_settings":
			_settings_draft.clear()
			_present_dialog("action")
		"confirm_pause_exit":
			_present_dialog("pause")
		"confirm_delete", "action", "confirm_application_exit", "inventory", "pause":
			_close_dialog()
		_:
			_close_dialog()


func _render_action_dialog(parent: Control) -> void:
	_dialog_content = _add(parent, "core:action-modal", {
		"title": "Continuar expedição" if _slot_has_save else "Nova expedição"
	})
	_on(_dialog_content, "start", func(_event: Dictionary) -> void: _action_play())
	_on(_dialog_content, "mods", func(_event: Dictionary) -> void: _open_mod_selector())
	_on(_dialog_content, "cancel", func(_event: Dictionary) -> void: _close_dialog())


func _render_confirmation(parent: Control, title: String, description: String, action: String) -> void:
	_dialog_content = _add(parent, "core:confirm-modal", {"title": title, "description": description})
	_on(_dialog_content, "yes", Callable(self, "_confirm_action").bind(action))
	_on(_dialog_content, "no", func(_event: Dictionary) -> void: _cancel_dialog())


func _confirm_action(_event: Dictionary, action: String) -> void:
	match action:
		"delete":
			var index := _pending_delete
			_pending_delete = -1
			if not _store.delete_slot(index):
				push_error("Failed to delete save slot %d." % index)
			_close_dialog()
		"exit_game":
			_end_game()
		"exit_app":
			get_tree().quit()


func _confirm_application_exit() -> void:
	_present_dialog("confirm_application_exit")


func _action_play() -> void:
	if _slot_has_save:
		_start_loading_saved_game()
	else:
		_open_mod_settings()


#region Mods dialog: resolve required dependencies in the real ModManager
func _open_mod_selector() -> void:
	_temp_mod_ids = _draft_mod_ids.duplicate()
	_inspected_mod = ""
	_present_dialog("mods")


func _render_mods_dialog(parent: Control) -> void:
	_dialog_content = _add(parent, "core:mods-panel")
	_on(_dialog_content, "back", func(_event: Dictionary) -> void: _cancel_dialog())
	_on(_dialog_content, "restore", func(_event: Dictionary) -> void: _reset_mod_selection())
	_on(_dialog_content, "ok", func(_event: Dictionary) -> void: _commit_mod_selection())
	_render_mod_rows()


func _render_mod_rows() -> void:
	if _dialog_name != "mods":
		return
	var panel := _dialog_content
	var list := _slot(panel, "list")
	_remove_children(list)
	for manifest in _catalog.installed_mods:
		if manifest.id == "core":
			continue
		var selected := _temp_mod_ids.has(manifest.id)
		var row := _add(list, "core:mod-row", {
			"title": "%s    v%s" % [manifest.display_name, manifest.version],
			"checked": selected
		})
		_on(row, "changed", Callable(self, "_on_mod_toggled").bind(manifest.id))
		_on(row, "inspect", Callable(self, "_inspect_mod").bind(manifest.id))
	if _inspected_mod.is_empty():
		for manifest in _catalog.installed_mods:
			if manifest.id != "core":
				_inspected_mod = manifest.id
				break
	_show_mod_details()


func _on_mod_toggled(event: Dictionary, mod_id: String) -> void:
	var arguments: Array = event.get("arguments", [])
	if arguments.is_empty():
		return
	var enabled := bool(arguments[0])
	if enabled:
		if mod_id not in _temp_mod_ids:
			_temp_mod_ids.append(mod_id)
		var resolved := _catalog.mod_manager.resolve(_temp_mod_ids)
		if resolved.is_empty():
			push_warning("Incompatible mod selection: " + str(_catalog.mod_manager.resolution_errors))
			_temp_mod_ids.erase(mod_id)
		else:
			_temp_mod_ids.clear()
			for manifest in resolved:
				if manifest.id != "core":
					_temp_mod_ids.append(manifest.id)
	else:
		_temp_mod_ids.erase(mod_id)
		var changed := true
		while changed:
			changed = false
			for current_id in _temp_mod_ids.duplicate():
				var manifest := _catalog.mod_manager.get_manifest(current_id)
				if manifest == null:
					continue
				for dependency in manifest.dependencies:
					if dependency.is_required() and dependency.id not in _temp_mod_ids and dependency.id != "core":
						_temp_mod_ids.erase(current_id)
						changed = true
						break
	_render_mod_rows()


func _inspect_mod(_event: Dictionary, mod_id: String) -> void:
	_inspected_mod = mod_id
	_show_mod_details()


func _show_mod_details() -> void:
	var label := _named(_dialog_content, "details")
	var manifest := _catalog.mod_manager.get_manifest(_inspected_mod)
	if label == null or manifest == null:
		return
	var dependencies: Array[String] = []
	for dependency in manifest.dependencies:
		dependencies.append("%s (%s)" % [dependency.id, "obrigatório" if dependency.is_required() else "opcional"])
	var description := "%s\n\nID: %s\nVersão: %s\nAutor: %s\n\n%s\n\nDependências:\n%s" % [
		manifest.display_name, manifest.id, manifest.version, manifest.author,
		manifest.description, "\n".join(PackedStringArray(dependencies)) if not dependencies.is_empty() else "Nenhuma"
	]
	label.update({"text": description})


func _reset_mod_selection() -> void:
	_temp_mod_ids.clear()
	_render_mod_rows()


func _commit_mod_selection() -> void:
	_draft_mod_ids = _temp_mod_ids.duplicate()
	_selected_mod_ids = _draft_mod_ids.duplicate()
	_present_dialog("action")
#endregion


#region Settings Stage: owner attribution and reactive draft values
func _open_mod_settings() -> void:
	_settings_registry = _catalog.settings_for(_draft_mod_ids)
	if _settings_registry == null:
		push_error("Cannot load Settings Stage: " + str(_catalog.errors))
		return
	_settings_draft.clear()
	for setting in _settings_registry.get_all_settings():
		_settings_draft[setting.id] = setting.get_effective_value()
	_selected_owner = "core"
	_present_dialog("mod_settings")


func _render_mod_settings_dialog(parent: Control) -> void:
	_dialog_content = _add(parent, "core:mod-settings-panel")
	_on(_dialog_content, "back", func(_event: Dictionary) -> void: _cancel_dialog())
	_on(_dialog_content, "restore", func(_event: Dictionary) -> void: _restore_mod_settings())
	_on(_dialog_content, "ok", func(_event: Dictionary) -> void: _commit_mod_settings())
	_render_mod_owner_list()
	_render_owner_settings()


func _render_mod_owner_list() -> void:
	var container := _slot(_dialog_content, "owners")
	_remove_children(container)
	var ids: Array[String] = ["core"]
	ids.append_array(_draft_mod_ids)
	for id in ids:
		var manifest := _catalog.mod_manager.get_manifest(id)
		if manifest == null:
			continue
		var prefix := "◆ " if id == _selected_owner else "◇ "
		var button := _add(container, "ui:button", {"label": prefix + manifest.display_name, "style": "core:button-tab"})
		_on(button, "pressed", Callable(self, "_choose_mod_owner").bind(id))


func _choose_mod_owner(_event: Dictionary, owner_id: String) -> void:
	_selected_owner = owner_id
	_render_mod_owner_list()
	_render_owner_settings()


func _render_owner_settings() -> void:
	if _settings_registry == null:
		return
	var title := _named(_dialog_content, "owner_name")
	var manifest := _catalog.mod_manager.get_manifest(_selected_owner)
	if title != null and manifest != null:
		title.update({"text": manifest.display_name})
	var container := _slot(_dialog_content, "settings")
	_remove_children(container)
	for setting in _settings_registry.get_visible_settings():
		if setting.owner_mod_id != _selected_owner:
			continue
		var value: Variant = _settings_draft.get(setting.id, setting.get_effective_value())
		var widget: UIComponentInstance
		match setting.value_type:
			ModSetting.BOOL:
				widget = _add(container, "core:option-bool", {"label": setting.display_name, "checked": bool(value)})
				_on(widget, "changed", Callable(self, "_on_mod_setting_changed").bind(setting.id, "bool", []))
			ModSetting.INT, ModSetting.DOUBLE:
				var min_value := float(setting.minimum_value) if setting.minimum_value != null else 0.0
				var max_value := float(setting.maximum_value) if setting.maximum_value != null else 100.0
				widget = _add(container, "core:option-range", {
					"label": setting.display_name, "minimum": min_value,
					"maximum": max_value, "value": float(value)
				})
				_on(widget, "changed", Callable(self, "_on_mod_setting_changed").bind(setting.id, setting.value_type, []))
			ModSetting.STRING:
				if not setting.allowed_values.is_empty():
					widget = _add(container, "core:option-choice", {"label": setting.display_name,
						"options": setting.allowed_values, "selected": setting.allowed_values.find(value)})
					_on(widget, "changed", Callable(self, "_on_mod_setting_changed").bind(setting.id, "choice", setting.allowed_values))
				else:
					_add(container, "ui:label", {"text": setting.display_name + ": " + str(value), "style": "core:text"})
			_:
				_add(container, "ui:label", {"text": setting.display_name + " (não editável neste exemplo)", "style": "core:text-muted"})


func _on_mod_setting_changed(event: Dictionary, id: String, value_type: String, choices: Array) -> void:
	var arguments: Array = event.get("arguments", [])
	if arguments.is_empty() or _settings_registry == null:
		return
	var value: Variant = arguments[0]
	if value_type == "choice":
		var index := int(value)
		if index < 0 or index >= choices.size():
			return
		value = choices[index]
	elif value_type == ModSetting.INT:
		value = roundi(float(value))
	elif value_type == ModSetting.DOUBLE:
		value = float(value)
	var failure := _settings_registry.validate_player_value(id, value)
	if not failure.is_empty():
		push_warning("Setting %s: %s" % [id, failure])
		return
	_settings_draft[id] = value


func _restore_mod_settings() -> void:
	if _settings_registry == null:
		return
	for setting in _settings_registry.get_all_settings():
		_settings_draft[setting.id] = setting.get_effective_value()
	_render_owner_settings()


func _commit_mod_settings() -> void:
	_active_mod_ids = _draft_mod_ids.duplicate()
	_active_settings = _settings_draft.duplicate(true)
	_load_payload.clear()
	_slot_has_save = false
	_initialize_inventory()
	_start_runtime()
#endregion

#region Runtime lifecycle, save files and placeholder 3D scene
func _start_loading_saved_game() -> void:
	var selected := _draft_mod_ids.duplicate()
	_settings_registry = _catalog.settings_for(selected)
	if _settings_registry == null:
		push_error("Settings Stage failed while loading a save: " + str(_catalog.errors))
		return
	_active_mod_ids = selected
	_active_settings.clear()
	var saved_settings: Dictionary = _load_payload.get("settings", {})
	for setting in _settings_registry.get_all_settings():
		var saved_value: Variant = saved_settings.get(setting.id, setting.get_effective_value())
		if setting.is_forced():
			_active_settings[setting.id] = setting.get_effective_value()
		elif _settings_registry.validate_player_value(setting.id, saved_value).is_empty():
			_active_settings[setting.id] = saved_value
		else:
			_active_settings[setting.id] = setting.get_effective_value()
	_play_seconds = float(_load_payload.get("duration_secs", 0))
	var items: Variant = _load_payload.get("inventory", [])
	if items is Array and items.size() == 28:
		_inventory = items.duplicate(true)
	else:
		_initialize_inventory()
	_start_runtime()


func _initialize_inventory() -> void:
	_inventory.clear()
	_inventory.resize(28)
	for index in range(28):
		_inventory[index] = {}
	var configured_equipment := str(_active_settings.get("core:starting_equipment", "Manopla de Bronze"))
	if configured_equipment != "Manopla de Bronze":
		return
	_inventory[0] = {
		"id": "bronze_gauntlet",
		"name": "Manopla de Bronze",
		"quantity": 1,
		"description": "Uma manopla resistente, dotada de um socket para datashards.\nProteção básica para uma nova expedição.",
		"texture": "core:gauntlet.png"
	}
	_play_seconds = 0.0


func _start_runtime() -> void:
	if _loading_game:
		return
	_loading_game = true
	_close_dialog()
	_loading_layer.visible = true
	_loading_layer.modulate.a = 1.0
	_remove_children(_loading_mount)
	var loading := _add(_loading_mount, "core:loading-panel", {"message": "Inicializando Runtime Stage..."})
	if loading != null:
		loading.root.custom_minimum_size = Vector2(480, 240)
	await get_tree().process_frame

	if _runtime != null:
		_runtime.close()
	_runtime = RuntimeManager.new()
	var resolved := _catalog.resolve(_active_mod_ids)
	if resolved.is_empty() or not _runtime.prepare(resolved):
		_runtime_failed("Runtime preparation failed: " + str(_runtime.errors) + "\n" + str(_catalog.errors))
		return

	var saved_mod_ids: Array[String] = []
	var saved_storage: Dictionary = {}
	if not _load_payload.is_empty():
		for mod_id in _load_payload.get("mods", []):
			saved_mod_ids.append(str(mod_id))
		saved_storage = _load_payload.get("runtime_storage", {})
	if not _runtime.activate({}, saved_mod_ids, null, saved_storage):
		_runtime_failed("Runtime activation failed: " + str(_runtime.errors))
		return

	_game_active = true
	_screen_name = "game"
	_screen_mount.visible = false
	_world_view.visible = true
	_hud_mount.visible = true
	_render_game_hud()
	var tween := create_tween()
	tween.tween_property(_loading_layer, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween.finished
	_loading_layer.visible = false
	_loading_game = false


func _runtime_failed(reason: String) -> void:
	_loading_layer.visible = false
	_loading_game = false
	push_error(reason)
	_show_menu()
	push_warning("Consumer runtime failed. See the output panel for details.")


func _render_game_hud() -> void:
	_remove_children(_hud_mount)
	_hud = _add(_hud_mount, "core:game-hud", {"health": 100.0})
	if _hud == null:
		return
	_hud.root.anchor_left = 0.0
	_hud.root.anchor_right = 0.0
	_hud.root.anchor_top = 1.0
	_hud.root.anchor_bottom = 1.0
	_hud.root.offset_left = 28.0
	_hud.root.offset_top = -120.0
	_hud.root.offset_right = 340.0
	_hud.root.offset_bottom = -20.0


func _end_game() -> void:
	if _runtime != null:
		_runtime.close()
		_runtime = null
	_load_payload.clear()
	_close_dialog()
	_show_menu()


func _save_current_game() -> void:
	if _runtime == null or not _game_active:
		return
	var runtime_data := _runtime.snapshot_storage()
	if not _runtime.errors.is_empty():
		push_error("Cannot snapshot runtime storage: " + str(_runtime.errors))
		return
	var payload := {
		"mods": _active_mod_ids.duplicate(),
		"settings": _active_settings.duplicate(true),
		"duration_secs": floori(_play_seconds),
		"inventory": _inventory.duplicate(true),
		"runtime_storage": runtime_data
	}
	if not _store.save_slot(_selected_slot, payload):
		push_error("Cannot save slot %d." % _selected_slot)
	else:
		_print_save_feedback()


func _print_save_feedback() -> void:
	print("Consumer Demo: saved slot %d to %s/slot_%d.save" % [
		_selected_slot, ConsumerStore.SAVE_ROOT, _selected_slot
	])
#endregion


#region Inventory: 28 draggable cells; 1 bronze gauntlet on new runs
func _open_inventory() -> void:
	_selected_inventory_slot = -1
	_present_dialog("inventory")


func _render_inventory_dialog(parent: Control) -> void:
	_dialog_content = _add(parent, "core:inventory-panel")
	_on(_dialog_content, "close", func(_event: Dictionary) -> void: _close_dialog())
	_render_inventory_cells()


func _render_inventory_cells() -> void:
	if _dialog_name != "inventory" or _dialog_content == null:
		return
	var container := _slot(_dialog_content, "slots")
	_remove_children(container)
	for index in range(28):
		var item: Dictionary = _inventory[index] if _inventory[index] is Dictionary else {}
		var filled := not item.is_empty()
		var cell := _add(container, "core:inventory-cell", {
			"quantity": str(item.get("quantity", "")) if filled else "",
			"texture": str(item.get("texture", "")) if filled else ""
		})
		if cell == null:
			continue
		cell.root.custom_minimum_size = Vector2(76, 76)
		var drag_component := cell._root_component
		if drag_component != null:
			drag_component.update({
				"can_drag": filled,
				"can_receive": true,
				"payload": {"source_slot": index, "label": str(item.get("name", ""))} if filled else {}
			})
			var native_drag := drag_component.content_root as UIComponentDragContainer
			if native_drag != null:
				native_drag.item_dropped.connect(Callable(self, "_on_inventory_drop").bind(index))
		_on(cell, "select", Callable(self, "_select_inventory_slot").bind(index))
	_render_inventory_details()


func _select_inventory_slot(_event: Dictionary, index: int) -> void:
	_selected_inventory_slot = index
	_render_inventory_details()


func _render_inventory_details() -> void:
	if _dialog_name != "inventory" or _dialog_content == null:
		return
	var container := _slot(_dialog_content, "description")
	_remove_children(container)
	if _selected_inventory_slot < 0 or _selected_inventory_slot >= _inventory.size():
		return
	var item: Dictionary = _inventory[_selected_inventory_slot] if _inventory[_selected_inventory_slot] is Dictionary else {}
	if item.is_empty():
		return
	var picture := _add(container, "ui:sprite", {"texture": str(item.get("texture", "")), "playing": false})
	if picture != null:
		picture.root.custom_minimum_size = Vector2(170, 170)
	_add(container, "ui:label", {"text": str(item.get("name", "")), "style": "core:heading"})
	_add(container, "ui:label", {"text": "Quantidade: %s" % str(item.get("quantity", 1)), "style": "core:text-gold"})
	_add(container, "ui:label", {"text": str(item.get("description", "")), "style": "core:text", "autowrap": true})


func _on_inventory_drop(payload: Variant, destination: int) -> void:
	if not payload is Dictionary:
		return
	var origin := int(payload.get("source_slot", -1))
	if origin < 0 or origin >= 28 or destination < 0 or destination >= 28 or origin == destination:
		return
	var previous: Variant = _inventory[destination]
	_inventory[destination] = _inventory[origin]
	_inventory[origin] = previous
	_selected_inventory_slot = destination
	call_deferred("_render_inventory_cells")
#endregion


#region Pause / quit dialogs and input behavior
func _open_pause() -> void:
	_present_dialog("pause")


func _render_pause_dialog(parent: Control) -> void:
	_dialog_content = _add(parent, "core:pause-panel")
	_on(_dialog_content, "resume", func(_event: Dictionary) -> void: _close_dialog())
	_on(_dialog_content, "save", func(_event: Dictionary) -> void: _save_current_game())
	_on(_dialog_content, "exit", func(_event: Dictionary) -> void: _present_dialog("confirm_pause_exit"))
#endregion
