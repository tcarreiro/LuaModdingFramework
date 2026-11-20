class_name UIComponentRichText extends RichTextLabel

signal safe_meta_clicked(meta: String)
signal safe_meta_hover_started(meta: String)
signal safe_meta_hover_ended(meta: String)


func _ready() -> void:
	meta_clicked.connect(func(meta: Variant) -> void: safe_meta_clicked.emit(str(meta)))
	meta_hover_started.connect(func(meta: Variant) -> void: safe_meta_hover_started.emit(str(meta)))
	meta_hover_ended.connect(func(meta: Variant) -> void: safe_meta_hover_ended.emit(str(meta)))


func get_premade_default_size_flags() -> Vector2i:
	return Vector2i(Control.SIZE_EXPAND_FILL, Control.SIZE_SHRINK_BEGIN)


func get_premade_definition() -> UIComponentDefinition:
	var definition := UIPremadeContract.create_definition(UIBuiltinIds.RICH_TEXT, {
		"text": UIPremadeContract.property(TYPE_STRING, ""),
		"bbcode": UIPremadeContract.property(TYPE_BOOL, true),
		"fit_content": UIPremadeContract.property(TYPE_BOOL, true),
		"scroll_active": UIPremadeContract.property(TYPE_BOOL, false),
		"selection_enabled": UIPremadeContract.property(TYPE_BOOL, true),
		"autowrap": UIPremadeContract.property(TYPE_BOOL, true)
	}, "", [&"meta_clicked", &"meta_hover_started", &"meta_hover_ended", &"finished", &"mouse_entered", &"mouse_exited"])
	definition.event_sources[&"meta_clicked"]["signal"] = &"safe_meta_clicked"
	definition.event_sources[&"meta_hover_started"]["signal"] = &"safe_meta_hover_started"
	definition.event_sources[&"meta_hover_ended"]["signal"] = &"safe_meta_hover_ended"
	return definition


func apply_premade_properties(values: Dictionary) -> void:
	if values.has("bbcode"):
		bbcode_enabled = values["bbcode"]
	if values.has("text"):
		text = values["text"]
	if values.has("fit_content"):
		fit_content = values["fit_content"]
	if values.has("scroll_active"):
		scroll_active = values["scroll_active"]
	if values.has("selection_enabled"):
		selection_enabled = values["selection_enabled"]
	if values.has("autowrap"):
		autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if values["autowrap"] else TextServer.AUTOWRAP_OFF
	UIPremadeContract.apply_common(self, values)
