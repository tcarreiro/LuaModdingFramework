extends GutTest

var styles: UIStyleRegistry
var components: UIComponentRegistry


func before_each() -> void:
	styles = UIStyleRegistry.new()
	components = UIComponentRegistry.new()
	components.style_registry = styles
	var catalog := UIPremadeCatalog.new()
	assert_true(catalog.install(components, styles), str(catalog.errors))
	assert_true(styles.finalize(), str(styles.errors))
	assert_true(components.finalize(), str(components.errors))


func _make(id: String, props: Dictionary = {}) -> UIComponentInstance:
	var instance := components.instantiate_component(id, props)
	assert_not_null(instance, str(components.errors))
	return instance


func _release(instance: UIComponentInstance) -> void:
	if instance == null:
		return
	instance.clear_callbacks()
	if is_instance_valid(instance.root):
		instance.root.free()


func test_all_six_are_discovered_automatically() -> void:
	for id in [UIBuiltinIds.TEXT_AREA, UIBuiltinIds.RICH_TEXT, UIBuiltinIds.ACCORDION, UIBuiltinIds.SPLIT_CONTAINER, UIBuiltinIds.TEXTURE_BUTTON, UIBuiltinIds.FILE_DIALOG]:
		assert_true(components.has_component(id), id)


func test_text_area_text_update() -> void:
	var instance := _make(UIBuiltinIds.TEXT_AREA, {"text": "A\nB", "placeholder": "Escreva"})
	if instance == null:
		return
	var control := instance.content_root as UIComponentTextArea
	assert_eq(control.text, "A\nB")
	assert_eq(control.placeholder_text, "Escreva")
	assert_true(instance.update({"text": "Atualizado"}))
	assert_eq(control.text, "Atualizado")
	_release(instance)


func test_rich_text_bbcode_and_update() -> void:
	var instance := _make(UIBuiltinIds.RICH_TEXT, {"text": "[b]Olá[/b]", "bbcode": true})
	if instance == null:
		return
	var control := instance.content_root as UIComponentRichText
	assert_true(control.bbcode_enabled)
	assert_eq(control.text, "[b]Olá[/b]")
	assert_true(instance.update({"text": "Novo texto"}))
	assert_eq(control.text, "Novo texto")
	_release(instance)


func test_accordion_content_slot_and_expand() -> void:
	var instance := _make(UIBuiltinIds.ACCORDION, {"title": "Avançado", "expanded": false})
	if instance == null:
		return
	var control := instance.content_root as UIComponentAccordion
	assert_not_null(instance.get_slot())
	assert_false(instance.get_slot().visible)
	var events: Array = []
	instance.on_event(&"toggled", func(event: Dictionary) -> void: events.append(event["arguments"][0]))
	control.set_expanded(true)
	assert_true(instance.get_slot().visible)
	assert_eq(events, [true])
	_release(instance)


func test_split_container_two_named_slots() -> void:
	var instance := _make(UIBuiltinIds.SPLIT_CONTAINER, {"split_offset": 20})
	if instance == null:
		return
	assert_not_null(instance.get_slot("first"))
	assert_not_null(instance.get_slot("second"))
	assert_ne(instance.get_slot("first"), instance.get_slot("second"))
	assert_eq((instance.content_root as UIComponentSplitContainer).split_offset, 20)
	_release(instance)


func test_texture_button_no_texture_still_has_minimum_size() -> void:
	var instance := _make(UIBuiltinIds.TEXTURE_BUTTON, {"disabled": true})
	if instance == null:
		return
	var control := instance.content_root as UIComponentTextureButton
	assert_true(control.disabled)
	assert_gt(control.custom_minimum_size.x, 0.0)
	assert_true(instance.update({"disabled": false}))
	assert_false(control.disabled)
	_release(instance)


func test_file_dialog_defaults_to_user_data_and_forwards_settings() -> void:
	var instance := _make(UIBuiltinIds.FILE_DIALOG, {"file_mode": "open_files", "filters": ["*.png ; PNG"]})
	if instance == null:
		return
	var dialog := instance.content_root.get_node("Dialog") as FileDialog
	assert_eq(dialog.access, FileDialog.ACCESS_USERDATA)
	assert_eq(dialog.file_mode, FileDialog.FILE_MODE_OPEN_FILES)
	assert_eq(dialog.filters.size(), 1)
	_release(instance)


func test_default_sizes() -> void:
	for id in [UIBuiltinIds.TEXT_AREA, UIBuiltinIds.RICH_TEXT, UIBuiltinIds.ACCORDION]:
		var instance := _make(id)
		if instance == null:
			continue
		assert_eq(instance.root.size_flags_horizontal, Control.SIZE_EXPAND_FILL, id)
		assert_eq(instance.root.size_flags_vertical, Control.SIZE_SHRINK_BEGIN, id)
		_release(instance)
	var split := _make(UIBuiltinIds.SPLIT_CONTAINER)
	if split != null:
		assert_eq(split.root.size_flags_horizontal, Control.SIZE_EXPAND_FILL)
		assert_eq(split.root.size_flags_vertical, Control.SIZE_EXPAND_FILL)
		_release(split)
	for id in [UIBuiltinIds.TEXTURE_BUTTON, UIBuiltinIds.FILE_DIALOG]:
		var instance := _make(id)
		if instance == null:
			continue
		assert_eq(instance.root.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN, id)
		assert_eq(instance.root.size_flags_vertical, Control.SIZE_SHRINK_BEGIN, id)
		_release(instance)
