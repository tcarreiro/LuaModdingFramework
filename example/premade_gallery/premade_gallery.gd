extends Control

const ASSET_ROOT := "user://premade_gallery"
const ASSET_DIRECTORY := ASSET_ROOT + "/assets/ui"

var _assets: ModAssetRegistry
var _styles: UIStyleRegistry
var _components: UIComponentRegistry
var _catalog: UIPremadeCatalog
var _host: UIRootHost

var _content: VBoxContainer
var _status: UIComponentInstance
var _instances: Array[UIComponentInstance] = []

var _modal_instance: UIComponentInstance
var _modal_wrapper: Control
var _modal_children: Array[UIComponentInstance] = []


func _ready() -> void:
	if not _create_demo_assets():
		return
	if not _initialize_catalog():
		return

	_host = UIRootHost.new()
	add_child(_host)

	_create_page()
	_create_examples()


func _initialize_catalog() -> bool:
	var manifest := ModManifest.new()
	manifest.id = "gallery"
	manifest.root_path = ASSET_ROOT

	var manifests: Array[ModManifest] = [manifest]

	_assets = ModAssetRegistry.new()
	_assets.configure(manifests)

	_styles = UIStyleRegistry.new()
	_styles.texture_resolver = Callable(_assets, "get_texture")
	_styles.sound_resolver = Callable(_assets, "get_sound")

	_components = UIComponentRegistry.new()
	_components.style_registry = _styles

	_catalog = UIPremadeCatalog.new(_assets)

	if not _catalog.install(_components, _styles):
		push_error(str(_catalog.errors))
		return false

	if not PremadeGalleryStyles.register(_styles):
		return false

	if not _styles.finalize():
		push_error(str(_styles.errors))
		return false

	if not _components.finalize():
		push_error(str(_components.errors))
		return false

	return true


func _create_page() -> void:
	var background := ColorRect.new()
	background.color = Color("#0B1019")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var page_scroll := ScrollContainer.new()
	page_scroll.name = "GalleryScroll"
	add_child(page_scroll)
	page_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_scroll.offset_left = 24
	page_scroll.offset_top = 20
	page_scroll.offset_right = -24
	page_scroll.offset_bottom = -20

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override(&"separation", 16)
	page_scroll.add_child(_content)

	_add(_content, UIBuiltinIds.LABEL, {
		UIKeys.PROP_TEXT: "Framework Lua Modder — Premades",
		UIKeys.PROP_STYLE: "gallery:heading"
	})

	_add(_content, UIBuiltinIds.LABEL, {
		UIKeys.PROP_TEXT: "Galeria independente de componentes, estilos e interações.",
		UIKeys.PROP_STYLE: "gallery:subtitle"
	})

	_status = _add(_content, UIBuiltinIds.LABEL, {
		UIKeys.PROP_TEXT: "Interaja com os componentes abaixo.",
		UIKeys.PROP_STYLE: "gallery:subtitle"
	})


func _create_examples() -> void:
	_demo_label()
	_demo_div()
	_demo_button()
	_demo_checkbox()
	_demo_dropdown()
	_demo_sprite()
	_demo_grid()
	_demo_stack()
	_demo_scroll()
	_demo_text_input()
	_demo_modal()
	_demo_slider()
	_demo_progress_bar()
	_demo_toggle()
	_demo_separator()
	_demo_radio_button()
	_demo_tabs()
	_demo_tooltip()
	_demo_list()
	_demo_drag_container()
	_demo_context_menu()
	_demo_color_picker()
	_demo_spin_box()
	_demo_tree()
	_demo_text_area()
	_demo_rich_text()
	_demo_accordion()
	_demo_split_container()
	_demo_texture_button()
	_demo_file_dialog()


func _add(parent: Control, id: String, properties: Dictionary = {}) -> UIComponentInstance:
	if parent == null:
		push_error("Gallery: parent is null for '%s'." % id)
		return null

	var instance := _components.instantiate_component(id, properties)

	if instance == null:
		push_error("Gallery: %s: %s" % [id, str(_components.errors)])
		return null

	parent.add_child(instance.root)
	_instances.append(instance)
	return instance


func _section(title: String, description: String) -> Control:
	var card := _add(_content, UIBuiltinIds.DIV, {
		UIKeys.PROP_STYLE: "gallery:card"
	})

	if card == null:
		return _content

	card.root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var content := card.get_slot()
	if content == null:
		return _content

	content.add_theme_constant_override(&"separation", 12)

	_add(content, UIBuiltinIds.LABEL, {
		UIKeys.PROP_TEXT: title,
		UIKeys.PROP_STYLE: "gallery:heading"
	})

	_add(content, UIBuiltinIds.LABEL, {
		UIKeys.PROP_TEXT: description,
		UIKeys.PROP_STYLE: "gallery:subtitle"
	})

	return content


func _row(parent: Control) -> Control:
	var stack := _add(parent, UIBuiltinIds.STACK, {
		UIKeys.PROP_DIRECTION: "horizontal",
		UIKeys.PROP_STYLE: "gallery:stack"
	})

	return stack.get_slot() if stack != null else parent


func _set_status(message: String) -> void:
	if _status != null and is_instance_valid(_status.root):
		_status.update({UIKeys.PROP_TEXT: message})


# ------------------------------------------------------------
# Label
# ------------------------------------------------------------

func _demo_label() -> void:
	var content := _section(
		"Label",
		"Texto, alinhamento e transição de hover."
	)

	var label := _add(content, UIBuiltinIds.LABEL, {
		UIKeys.PROP_TEXT: "Este Label reage ao hover",
		UIKeys.PROP_STYLE: "gallery:hover-label"
	})

	if label != null:
		label.on_event(UIKeys.EVENT_MOUSE_ENTERED, func(_event: Dictionary) -> void:
			_set_status("Label: mouse_entered.")
		)

		label.on_event(UIKeys.EVENT_MOUSE_EXITED, func(_event: Dictionary) -> void:
			_set_status("Label: mouse_exited.")
		)

	_add(content, UIBuiltinIds.LABEL, {
		UIKeys.PROP_TEXT: "Texto centralizado",
		UIKeys.PROP_ALIGN: "center",
		UIKeys.PROP_STYLE: "gallery:subtitle"
	})


# ------------------------------------------------------------
# Div
# ------------------------------------------------------------

func _demo_div() -> void:
	var content := _section(
		"Div",
		"Composição, 9-slice, padding e mudança de cor no hover."
	)

	var div := _add(content, UIBuiltinIds.DIV, {
		UIKeys.PROP_STYLE: "gallery:card",
		UIKeys.PROP_DIRECTION: "vertical"
	})

	if div != null:
		_add(div.get_slot(), UIBuiltinIds.LABEL, {
			UIKeys.PROP_TEXT: "Este painel utiliza background_image e 9-slice.",
			UIKeys.PROP_STYLE: "gallery:subtitle"
		})

	var hover_div := _add(content, UIBuiltinIds.DIV, {
		UIKeys.PROP_STYLE: "gallery:hover-div"
	})

	if hover_div != null:
		_add(hover_div.get_slot(), UIBuiltinIds.LABEL, {
			UIKeys.PROP_TEXT: "Passe o cursor sobre este painel.",
			UIKeys.PROP_STYLE: "gallery:subtitle"
		})

		hover_div.on_event(UIKeys.EVENT_MOUSE_ENTERED, func(_event: Dictionary) -> void:
			_set_status("Div: hover iniciado.")
		)


# ------------------------------------------------------------
# Button
# ------------------------------------------------------------

func _demo_button() -> void:
	var content := _section(
		"Button",
		"Ícone, alinhamento, clique, estados e botão desabilitado."
	)

	var row := _row(content)

	var button := _add(row, UIBuiltinIds.BUTTON, {
		UIKeys.PROP_LABEL: "Confirmar",
		UIKeys.PROP_ICON: "gallery:ui/icon.png",
		UIKeys.PROP_ICON_ALIGNMENT: "left"
	})

	if button != null:
		button.on_event(UIKeys.EVENT_PRESSED, func(_event: Dictionary) -> void:
			_set_status("Button: pressed.")
		)

	_add(row, UIBuiltinIds.BUTTON, {
		UIKeys.PROP_LABEL: "Desabilitado",
		UIKeys.PROP_DISABLED: true
	})

	var second_row := _row(content)

	var icon_right := _add(second_row, UIBuiltinIds.BUTTON, {
		UIKeys.PROP_LABEL: "Ícone à direita",
		UIKeys.PROP_ICON: "gallery:ui/icon.png",
		UIKeys.PROP_ICON_ALIGNMENT: "right"
	})

	if icon_right != null:
		icon_right.on_event(UIKeys.EVENT_PRESSED, func(_event: Dictionary) -> void:
			_set_status("Button: ícone à direita.")
		)


# ------------------------------------------------------------
# Checkbox
# ------------------------------------------------------------

func _demo_checkbox() -> void:
	var content := _section(
		"Checkbox",
		"Seleção booleana, evento toggled e estado disabled."
	)

	var row := _row(content)

	var checkbox := _add(row, UIBuiltinIds.CHECKBOX, {
		UIKeys.PROP_LABEL: "Ativar efeitos",
		UIKeys.PROP_CHECKED: true
	})

	if checkbox != null:
		checkbox.on_event(UIKeys.EVENT_TOGGLED, func(event: Dictionary) -> void:
			var arguments: Array = event.get("arguments", [])
			if not arguments.is_empty():
				_set_status("Checkbox: %s" % str(arguments[0]))
		)

	_add(row, UIBuiltinIds.CHECKBOX, {
		UIKeys.PROP_LABEL: "Bloqueado",
		UIKeys.PROP_CHECKED: true,
		UIKeys.PROP_DISABLED: true
	})
	
	_add(row, UIBuiltinIds.CHECKBOX, {
		UIKeys.PROP_LABEL: "Desmarcado",
		UIKeys.PROP_CHECKED: false
	})


# ------------------------------------------------------------
# Dropdown
# ------------------------------------------------------------

func _demo_dropdown() -> void:
	var content := _section(
		"Dropdown",
		"Lista de opções, seleção e evento item_selected."
	)

	var dropdown := _add(content, UIBuiltinIds.DROPDOWN, {
		UIKeys.PROP_OPTIONS: ["Baixo", "Médio", "Alto", "Ultra"],
		UIKeys.PROP_SELECTED: 1
	})

	if dropdown != null:
		dropdown.on_event(UIKeys.EVENT_ITEM_SELECTED, func(event: Dictionary) -> void:
			var arguments: Array = event.get("arguments", [])
			if not arguments.is_empty():
				_set_status("Dropdown: índice %s" % str(arguments[0]))
		)

	_add(content, UIBuiltinIds.DROPDOWN, {
		UIKeys.PROP_OPTIONS: ["Opção indisponível"],
		UIKeys.PROP_SELECTED: 0,
		UIKeys.PROP_DISABLED: true
	})


# ------------------------------------------------------------
# Sprite
# ------------------------------------------------------------

func _demo_sprite() -> void:
	var content := _section(
		"Sprite",
		"Sprite sheet animada, filtragem nearest, repeat e controle de reprodução."
	)

	var row := _row(content)

	var sprite := _add(row, UIBuiltinIds.SPRITE, {
		UIKeys.PROP_TEXTURE: "gallery:ui/sprite_sheet.png",
		UIKeys.PROP_HFRAMES: 4,
		UIKeys.PROP_VFRAMES: 1,
		UIKeys.PROP_FRAME_COUNT: 4,
		UIKeys.PROP_FPS: 4.0,
		UIKeys.PROP_FILTER_MODE: "nearest",
		UIKeys.PROP_REPEAT: "disabled",
		UIKeys.PROP_LOOP: true,
		UIKeys.PROP_PLAYING: true,
		UIKeys.PROP_STYLE: "gallery:sprite"
	})

	var button := _add(row, UIBuiltinIds.BUTTON, {
		UIKeys.PROP_LABEL: "Pausar"
	})

	if sprite != null and button != null:
		var playing := [true]

		button.on_event(UIKeys.EVENT_PRESSED, func(_event: Dictionary) -> void:
			playing[0] = not playing[0]

			sprite.update({
				UIKeys.PROP_PLAYING: playing[0]
			})

			button.update({
				UIKeys.PROP_LABEL: "Pausar" if playing[0] else "Continuar"
			})

			_set_status("Sprite: reproduzindo." if playing[0] else "Sprite: pausado.")
		)

	var second_row := _row(content)

	_add(second_row, UIBuiltinIds.SPRITE, {
		UIKeys.PROP_TEXTURE: "gallery:ui/icon.png",
		UIKeys.PROP_PLAYING: false,
		UIKeys.PROP_FILTER_MODE: "linear",
		UIKeys.PROP_REPEAT: "inherit",
		UIKeys.PROP_STYLE: "gallery:sprite"
	})

	_add(second_row, UIBuiltinIds.LABEL, {
		UIKeys.PROP_TEXT: "Imagem estática com filtro linear.",
		UIKeys.PROP_STYLE: "gallery:subtitle"
	})


# ------------------------------------------------------------
# Grid
# ------------------------------------------------------------

func _demo_grid() -> void:
	var content := _section(
		"Grid",
		"Grade de quatro colunas, espaçamento via estilo e botões interativos."
	)

	var grid := _add(content, UIBuiltinIds.GRID, {
		UIKeys.PROP_COLUMNS: 4,
		UIKeys.PROP_STYLE: "gallery:grid"
	})

	if grid == null:
		return

	for index in range(8):
		var button := _add(grid.get_slot(), UIBuiltinIds.BUTTON, {
			UIKeys.PROP_LABEL: str(index + 1)
		})

		if button != null:
			button.on_event(
				UIKeys.EVENT_PRESSED,
				Callable(self, "_on_grid_pressed").bind(index)
			)


func _on_grid_pressed(_event: Dictionary, index: int) -> void:
	_set_status("Grid: célula %d." % (index + 1))


# ------------------------------------------------------------
# Stack
# ------------------------------------------------------------

func _demo_stack() -> void:
	var content := _section(
		"Stack",
		"Distribuição horizontal e vertical com gap definido por estilo."
	)

	var row := _row(content)

	for text_value in ["Primeiro", "Segundo", "Terceiro"]:
		_add(row, UIBuiltinIds.LABEL, {
			UIKeys.PROP_TEXT: text_value,
			UIKeys.PROP_STYLE: "gallery:hover-label"
		})

	var vertical := _add(content, UIBuiltinIds.STACK, {
		UIKeys.PROP_DIRECTION: "vertical",
		UIKeys.PROP_STYLE: "gallery:stack"
	})

	if vertical != null:
		for text_value in ["Linha A", "Linha B", "Linha C"]:
			_add(vertical.get_slot(), UIBuiltinIds.LABEL, {
				UIKeys.PROP_TEXT: text_value,
				UIKeys.PROP_STYLE: "gallery:subtitle"
			})


# ------------------------------------------------------------
# Scroll
# ------------------------------------------------------------

func _demo_scroll() -> void:
	var content := _section(
		"Scroll",
		"Área rolável com tamanho limitado, padding interno e conteúdo extenso."
	)

	var viewport := Control.new()
	viewport.name = "ScrollDemoViewport"
	viewport.custom_minimum_size = Vector2(0, 200)
	viewport.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(viewport)

	var scroll := _add(viewport, UIBuiltinIds.SCROLL, {
		UIKeys.PROP_VERTICAL_SCROLL: "auto",
		UIKeys.PROP_HORIZONTAL_SCROLL: "disabled",
		UIKeys.PROP_STYLE: "gallery:scroll"
	})

	if scroll == null:
		return

	scroll.root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	for index in range(16):
		_add(scroll.get_slot(), UIBuiltinIds.LABEL, {
			UIKeys.PROP_TEXT: "Linha rolável %02d" % (index + 1),
			UIKeys.PROP_STYLE: "gallery:subtitle"
		})


# ------------------------------------------------------------
# TextInput
# ------------------------------------------------------------

func _demo_text_input() -> void:
	var content := _section(
		"TextInput",
		"Texto, senha, números inteiros, decimais, limites min/max e validação."
	)

	var row := _row(content)

	var input := _add(row, UIBuiltinIds.TEXT_INPUT, {
		UIKeys.PROP_PLACEHOLDER: "Digite e pressione Enter...",
		UIKeys.PROP_CLEAR_BUTTON: true,
		UIKeys.PROP_STYLE: "gallery:text-input"
	})

	if input != null:
		input.on_event(UIKeys.EVENT_TEXT_SUBMITTED, func(event: Dictionary) -> void:
			var arguments: Array = event.get("arguments", [])
			if not arguments.is_empty():
				_set_status("TextInput: %s" % str(arguments[0]))
		)

	_add(row, UIBuiltinIds.TEXT_INPUT, {
		UIKeys.PROP_PLACEHOLDER: "Senha",
		UIKeys.PROP_SECRET: true,
		UIKeys.PROP_STYLE: "gallery:text-input"
	})

	var number_row := _row(content)

	var integer_field := _add(number_row, UIBuiltinIds.TEXT_INPUT, {
		UIKeys.PROP_PLACEHOLDER: "Inteiro de 1 a 99",
		UIKeys.PROP_VALIDATION: "integer",
		UIKeys.PROP_ALLOW_NEGATIVE: false,
		UIKeys.PROP_ALLOW_EMPTY: false,
		UIKeys.PROP_MIN: 1,
		UIKeys.PROP_MAX: 99,
		UIKeys.PROP_STYLE: "gallery:text-input"
	})

	var decimal_field := _add(number_row, UIBuiltinIds.TEXT_INPUT, {
		UIKeys.PROP_PLACEHOLDER: "Decimal de 0 a 100",
		UIKeys.PROP_VALIDATION: "decimal",
		UIKeys.PROP_DECIMAL_SEPARATOR: "both",
		UIKeys.PROP_ALLOW_NEGATIVE: false,
		UIKeys.PROP_ALLOW_EMPTY: false,
		UIKeys.PROP_MIN: 0.0,
		UIKeys.PROP_MAX: 100.0,
		UIKeys.PROP_STYLE: "gallery:text-input"
	})

	for field in [integer_field, decimal_field]:
		if field == null:
			continue
		
		field.on_event(UIKeys.EVENT_TEXT_CHANGED,
			Callable(self, "_on_numeric_text_changed").bind(field.content_root))

		field.on_event(UIKeys.EVENT_VALUE_SUBMITTED, func(event: Dictionary) -> void:
			var arguments: Array = event.get("arguments", [])
			if not arguments.is_empty():
				_set_status("TextInput: valor válido = %s" % str(arguments[0]))
		)

		field.on_event(UIKeys.EVENT_VALIDATION_FAILED, func(event: Dictionary) -> void:
			var arguments: Array = event.get("arguments", [])
			var value := str(arguments[0]) if not arguments.is_empty() else ""
			_set_status("TextInput: valor inválido ou fora dos limites: '%s'." % value)
		)

	_add(content, UIBuiltinIds.LABEL, {
		UIKeys.PROP_TEXT: "Teste enviar 0, 100 ou 12.5 no campo inteiro, e 120 no decimal.",
		UIKeys.PROP_STYLE: "gallery:subtitle"
	})


func _on_numeric_text_changed(_event: Dictionary, field: UIComponentTextInput) -> void:
	if not field.is_value_valid():
		_set_status("TextInput: valor incompleto.")
		return
	_set_status("TextInput: valor atual = %s" % str(field.get_value()))
# ------------------------------------------------------------
# Modal
# ------------------------------------------------------------

func _demo_modal() -> void:
	var content := _section(
		"Modal",
		"Janela flutuante, backdrop, fechamento e arraste pelo cabeçalho."
	)

	var row := _row(content)

	var button := _add(row, UIBuiltinIds.BUTTON, {
		UIKeys.PROP_LABEL: "Abrir modal"
	})

	if button != null:
		button.on_event(UIKeys.EVENT_PRESSED, func(_event: Dictionary) -> void:
			_open_modal()
		)


func _open_modal() -> void:
	if _modal_wrapper != null and is_instance_valid(_modal_wrapper):
		return

	_modal_instance = _components.instantiate_component(UIBuiltinIds.MODAL, {
		UIKeys.PROP_TITLE: "Modal de demonstração",
		UIKeys.PROP_DRAGGABLE: true,
		UIKeys.PROP_CLOSEABLE: true
	})

	if _modal_instance == null:
		push_error("Gallery modal: %s" % str(_components.errors))
		return

	_instances.append(_modal_instance)

	var description := _add(_modal_instance.get_slot(), UIBuiltinIds.LABEL, {
		UIKeys.PROP_TEXT: "Arraste pelo título e feche usando o botão X.",
		UIKeys.PROP_STYLE: "gallery:subtitle"
	})

	if description != null:
		_modal_children.append(description)

	var close_button := _add(_modal_instance.get_slot(), UIBuiltinIds.BUTTON, {
		UIKeys.PROP_LABEL: "Fechar"
	})

	if close_button != null:
		_modal_children.append(close_button)

		close_button.on_event(UIKeys.EVENT_PRESSED, func(_event: Dictionary) -> void:
			_close_modal()
		)

	_modal_instance.on_event(UIKeys.EVENT_CLOSE_REQUESTED, func(_event: Dictionary) -> void:
		_close_modal()
	)

	_modal_wrapper = _host.mount_component(
		_modal_instance.root,
		"modal",
		true,
		null,
		Control.MOUSE_FILTER_STOP
	)

	if _modal_wrapper == null:
		push_error("Gallery modal mount: %s" % str(_host.errors))
		_close_modal()
		_set_status("Falha ao abrir modal.")
		return

	_set_status("Modal aberto.")


func _close_modal() -> void:
	if _modal_instance == null and _modal_wrapper == null:
		return

	var modal_root: Control = null

	if _modal_instance != null:
		modal_root = _modal_instance.root

	for instance in _modal_children:
		if instance != null:
			instance.clear_callbacks()
			_instances.erase(instance)

	_modal_children.clear()

	if _modal_instance != null:
		_modal_instance.clear_callbacks()
		_instances.erase(_modal_instance)
		_modal_instance = null

	if _modal_wrapper != null and is_instance_valid(_modal_wrapper):
		_modal_wrapper.queue_free()
	elif modal_root != null and is_instance_valid(modal_root):
		modal_root.queue_free()

	_modal_wrapper = null
	_set_status("Modal fechado.")


# ------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------

func _exit_tree() -> void:
	for instance in _instances:
		if instance != null:
			instance.clear_callbacks()

	_instances.clear()
	_modal_children.clear()


# ------------------------------------------------------------
# Assets
# ------------------------------------------------------------

func _create_demo_assets() -> bool:
	var directory := ProjectSettings.globalize_path(ASSET_DIRECTORY)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("Cannot create gallery asset directory.")
		return false
	
	# Sprite sheet with 4 frames
	var sheet := Image.create_empty(128, 32, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	var frame_colors := [
		Color("#77C8FF"),
		Color("#A38AFF"),
		Color("#FFD178"),
		Color("#77E3AD")
	]
	for index in range(4):
		sheet.fill_rect(Rect2i(index * 32 + 4, 4, 24, 24), frame_colors[index])
	
	# 9-slice texture.
	var frame := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	frame.fill(Color("#162236"))
	var border := Color("#668BAF")
	frame.fill_rect(Rect2i(0, 0, 64, 8), border)
	frame.fill_rect(Rect2i(0, 56, 64, 8), border)
	frame.fill_rect(Rect2i(0, 0, 8, 64), border)
	frame.fill_rect(Rect2i(56, 0, 8, 64), border)
	
	# Icon.
	var icon := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	icon.fill(Color.TRANSPARENT)
	icon.fill_rect(Rect2i(4, 4, 24, 24), Color("#88C9F0"))
	icon.fill_rect(Rect2i(10, 10, 12, 12), Color("#1A304A"))
	var images := {
		"sprite_sheet.png": sheet,
		"frame.png": frame,
		"icon.png": icon
	}

	for filename in images:
		var path := ASSET_DIRECTORY.path_join(filename)
		var result: Error = images[filename].save_png(path)
		if result != OK:
			push_error("Cannot save gallery asset '%s'." % path)
			return false
	
	return true


# ------------------------------------------------------------
# Additional premades
# ------------------------------------------------------------

func _demo_slider() -> void:
	var content := _section("Slider", "Controle nativo de valores com step e eventos.")
	var slider := _add(content, UIBuiltinIds.SLIDER, {
		UIKeys.PROP_MIN: 0.0, UIKeys.PROP_MAX: 100.0,
		UIKeys.PROP_VALUE: 35.0, UIKeys.PROP_STEP: 5.0
	})
	if slider != null:
		slider.on_event(UIKeys.EVENT_VALUE_CHANGED, func(event: Dictionary) -> void:
			_set_status("Slider: %s" % str(event["arguments"][0]))
		)


func _demo_progress_bar() -> void:
	var content := _section("ProgressBar", "Valor atual e porcentagem.")
	_add(content, UIBuiltinIds.PROGRESS_BAR, {
		UIKeys.PROP_MIN: 0.0, UIKeys.PROP_MAX: 100.0,
		UIKeys.PROP_VALUE: 67.0
	})


func _demo_toggle() -> void:
	var content := _section("Toggle", "Interruptor booleano com sinal toggled.")
	var toggle := _add(content, UIBuiltinIds.TOGGLE, {
		UIKeys.PROP_LABEL: "Habilitar áudio", UIKeys.PROP_CHECKED: true
	})
	if toggle != null:
		toggle.on_event(UIKeys.EVENT_TOGGLED, func(event: Dictionary) -> void:
			_set_status("Toggle: %s" % str(event["arguments"][0]))
		)


func _demo_separator() -> void:
	var content := _section("Separator", "Divisor horizontal com cor e espessura configuráveis.")
	_add(content, UIBuiltinIds.SEPARATOR, {
		UIKeys.PROP_THICKNESS: 2.0,
		UIKeys.PROP_COLOR: Color("#79E6A3")
	})


func _demo_radio_button() -> void:
	var content := _section("RadioButton", "Seleção exclusiva entre irmãos do mesmo grupo.")
	var row := _row(content)
	for index in range(3):
		var radio := _add(row, UIBuiltinIds.RADIO_BUTTON, {
			UIKeys.PROP_LABEL: "Opção %d" % (index + 1),
			UIKeys.PROP_GROUP: "gallery-options",
			UIKeys.PROP_CHECKED: index == 0
		})
		if radio != null:
			radio.on_event(UIKeys.EVENT_TOGGLED, func(event: Dictionary) -> void:
				_set_status("RadioButton: %s" % str(event["arguments"][0]))
			)


func _demo_tabs() -> void:
	var content := _section("Tabs", "Cada filho Control representa uma aba.")
	var tabs := _add(content, UIBuiltinIds.TABS, {
		UIKeys.PROP_TABS: ["Geral", "Avançado"],
		UIKeys.PROP_SELECTED_TAB: 0
	})
	if tabs == null:
		return
	for title in ["Geral", "Avançado"]:
		var panel := _add(tabs.get_slot(), UIBuiltinIds.DIV, {})
		if panel != null:
			panel.root.name = title
			_add(panel.get_slot(), UIBuiltinIds.LABEL, {UIKeys.PROP_TEXT: "Conteúdo: " + title})
	tabs.on_event(UIKeys.EVENT_TAB_CHANGED, func(event: Dictionary) -> void:
		_set_status("Tabs: aba %d" % event["arguments"][0])
	)


func _demo_tooltip() -> void:
	var content := _section("Tooltip", "Texto nativo exibido ao passar o cursor pelo conteúdo.")
	var tooltip := _add(content, UIBuiltinIds.TOOLTIP, {
		UIKeys.PROP_TEXT: "Tooltip fornecido pelo LuaModdingFramework."
	})
	if tooltip != null:
		_add(tooltip.get_slot(), UIBuiltinIds.BUTTON, {
			UIKeys.PROP_LABEL: "Passe o cursor aqui"
		})


func _demo_list() -> void:
	var content := _section("List", "Seleção simples com ItemList nativo.")
	var instance := _add(content, UIBuiltinIds.LIST, {"options": ["Espada", "Escudo", "Poção"], "selected": 1})
	if instance != null:
		instance.root.custom_minimum_size = Vector2(200, 96)
		instance.on_event(&"item_selected", func(event: Dictionary) -> void:
			_set_status("List: item %s" % str(event.get("arguments", [])))
		)


func _demo_drag_container() -> void:
	var content := _section("DragContainer", "Arraste o primeiro painel para o segundo.")
	var row := _row(content)
	var source := _add(row, UIBuiltinIds.DRAG_CONTAINER, {"payload": {"id": "demo-payload"}, "can_receive": false})
	var target := _add(row, UIBuiltinIds.DRAG_CONTAINER, {"can_drag": false})
	if source == null or target == null:
		return
	for instance in [source, target]:
		instance.root.custom_minimum_size = Vector2(140, 65)
	_add(source.get_slot(), UIBuiltinIds.LABEL, {"text": "Arraste daqui"})
	_add(target.get_slot(), UIBuiltinIds.LABEL, {"text": "Solte aqui"})
	target.on_event(&"item_dropped", func(event: Dictionary) -> void:
		_set_status("DragContainer: %s" % str(event.get("arguments", [])))
	)


func _demo_context_menu() -> void:
	var content := _section("ContextMenu", "Clique no botão para abrir abaixo ou clique com botão direito para abrir no cursor.")
	var trigger := _add(content, UIBuiltinIds.BUTTON, {"label": "Abrir menu ancorado"})
	var instance := _add(_host.overlay_root, UIBuiltinIds.CONTEXT_MENU, {"options": ["Editar", "Duplicar", "Excluir"], "close_on_select": true})
	if instance == null or trigger == null:
		return
	var menu := instance.content_root as UIComponentContextMenu
	trigger.on_event(&"pressed", func(_event: Dictionary) -> void:
		menu.open_anchored(trigger.root, "bottom", "start", Vector2(0, 8), true)
	)
	trigger.root.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			menu.open_at_mouse()
	)
	instance.on_event(&"item_selected", func(event: Dictionary) -> void:
		_set_status("ContextMenu: %s" % str(event.get("arguments", [])))
	)


func _demo_color_picker() -> void:
	var content := _section("ColorPicker", "Seletor de cores com popup nativo.")
	var instance := _add(content, UIBuiltinIds.COLOR_PICKER, {"color": Color("#E6A759")})
	if instance != null:
		instance.on_event(&"color_changed", func(event: Dictionary) -> void:
			_set_status("ColorPicker: %s" % str(event.get("arguments", [])))
		)


func _demo_spin_box() -> void:
	var content := _section("SpinBox", "Entrada numérica com intervalo e incremento.")
	var instance := _add(content, UIBuiltinIds.SPIN_BOX, {"min": 0.0, "max": 100.0, "step": 5.0, "value": 25.0, "suffix": "%"})
	if instance != null:
		instance.on_event(UIKeys.EVENT_VALUE_CHANGED, func(event: Dictionary) -> void:
			_set_status("SpinBox: %s" % str(event.get("arguments", [])))
		)


func _demo_tree() -> void:
	var content := _section("Tree", "Árvore hierárquica construída a partir de dados.")
	var instance := _add(content, UIBuiltinIds.TREE, {"items": [
		{"id": "gear", "label": "Equipamentos", "children": ["Espada", "Escudo"]},
		{"id": "items", "label": "Consumíveis", "children": ["Poção", "Elixir"]}
	]})
	if instance != null:
		instance.root.custom_minimum_size = Vector2(220, 130)


# ------------------------------------------------------------
# TextArea, RichText, Accordion, SplitContainer, TextureButton, FileDialog
# ------------------------------------------------------------

func _demo_text_area() -> void:
	var content := _section("TextArea", "Texto multilinha, quebra de linha e edição.")
	var instance := _add(content, UIBuiltinIds.TEXT_AREA, {
		"text": "Escreva suas notas aqui...\nUma linha por vez.",
		"placeholder": "Digite um texto", "wrap": true
	})
	if instance != null:
		instance.on_event(&"text_changed", func(_event: Dictionary) -> void:
			_set_status("TextArea: texto modificado.")
		)


func _demo_rich_text() -> void:
	var content := _section("RichText", "Texto com BBCode, cores e links clicáveis.")
	var instance := _add(content, UIBuiltinIds.RICH_TEXT, {
		"text": "[b]Título em negrito[/b]  [color=#79E6A3]Cor[/color]\n[url=https://godotengine.org]Godot Engine[/url]",
		"bbcode": true, "fit_content": true
	})
	if instance != null:
		instance.on_event(&"meta_clicked", func(event: Dictionary) -> void:
			_set_status("RichText: link %s" % str(event.get("arguments", [])))
		)


func _demo_accordion() -> void:
	var content := _section("Accordion", "Clique no título para expandir ou recolher seu conteúdo.")
	var instance := _add(content, UIBuiltinIds.ACCORDION, {
		"title": "Detalhes da seção", "expanded": true
	})
	if instance == null:
		return
	_add(instance.get_slot(), UIBuiltinIds.LABEL, {"text": "Conteúdo dentro do slot default."})
	_add(instance.get_slot(), UIBuiltinIds.BUTTON, {"label": "Botão dentro do accordion"})
	instance.on_event(&"toggled", func(event: Dictionary) -> void:
		_set_status("Accordion: expanded = %s" % str(event.get("arguments", [])))
	)


func _demo_split_container() -> void:
	var content := _section("SplitContainer", "Arraste o divisor para redimensionar os dois painéis.")
	var instance := _add(content, UIBuiltinIds.SPLIT_CONTAINER, {"split_offset": 0})
	if instance == null:
		return
	instance.root.custom_minimum_size = Vector2(260, 130)
	_add(instance.get_slot("first"), UIBuiltinIds.DIV, {"style": "gallery:card"})
	_add(instance.get_slot("second"), UIBuiltinIds.DIV, {"style": "gallery:card"})
	instance.on_event(&"dragged", func(event: Dictionary) -> void:
		_set_status("SplitContainer: %s" % str(event.get("arguments", [])))
	)


func _demo_texture_button() -> void:
	var content := _section("TextureButton", "Botão com texturas de estados resolvidas pelo registry de assets.")
	var instance := _add(content, UIBuiltinIds.TEXTURE_BUTTON, {
		"texture": "gallery:ui/icon.png", "texture_hover": "gallery:ui/icon.png"
	})
	if instance != null:
		instance.root.custom_minimum_size = Vector2(64, 64)
		instance.on_event(&"pressed", func(_event: Dictionary) -> void:
			_set_status("TextureButton: pressionado.")
		)


func _demo_file_dialog() -> void:
	var content := _section("FileDialog", "Seleciona um arquivo de user:// por padrão.")
	var instance := _add(content, UIBuiltinIds.FILE_DIALOG, {
		"label": "Selecionar arquivo", "title": "Arquivo do usuário",
		"access": "user_data", "file_mode": "open_file"
	})
	if instance != null:
		instance.on_event(&"file_selected", func(event: Dictionary) -> void:
			_set_status("FileDialog: %s" % str(event.get("arguments", [])))
		)
