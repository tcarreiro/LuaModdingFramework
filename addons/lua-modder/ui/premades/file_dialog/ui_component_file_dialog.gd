class_name UIComponentFileDialog extends HBoxContainer

signal file_selected(path: String)
signal files_selected(paths_json: String)
signal dir_selected(path: String)
signal canceled

var _dialog: FileDialog


func _ready() -> void:
	_dialog = get_node("Dialog") as FileDialog
	_dialog.file_selected.connect(func(path: String) -> void: file_selected.emit(path))
	_dialog.files_selected.connect(func(paths: PackedStringArray) -> void: files_selected.emit(JSON.stringify(Array(paths))))
	_dialog.dir_selected.connect(func(path: String) -> void: dir_selected.emit(path))
	_dialog.canceled.connect(func() -> void: canceled.emit())
	(get_node("Open") as Button).pressed.connect(open_dialog)


func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(UIBuiltinIds.FILE_DIALOG, {
		"label": UIPremadeContract.property(TYPE_STRING, "Selecionar arquivo"),
		"title": UIPremadeContract.property(TYPE_STRING, "Selecionar arquivo"),
		"file_mode": UIPremadeContract.property(TYPE_STRING, "open_file"),
		"access": UIPremadeContract.property(TYPE_STRING, "user_data"),
		"filters": UIPremadeContract.property(TYPE_ARRAY, []),
		"current_dir": UIPremadeContract.property(TYPE_STRING, ""),
		"disabled": UIPremadeContract.property(TYPE_BOOL, false)
	}, "", [&"file_selected", &"files_selected", &"dir_selected", &"canceled", &"mouse_entered", &"mouse_exited"])


func apply_premade_properties(values: Dictionary) -> void:
	var dialog := get_node("Dialog") as FileDialog
	if values.has("label"):
		(get_node("Open") as Button).text = values["label"]
	if values.has("title"):
		dialog.title = values["title"]
	if values.has("file_mode"):
		match values["file_mode"]:
			"open_files": dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
			"open_dir": dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
			"open_any": dialog.file_mode = FileDialog.FILE_MODE_OPEN_ANY
			"save_file": dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
			_: dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	if values.has("access"):
		match values["access"]:
			"resources": dialog.access = FileDialog.ACCESS_RESOURCES
			"filesystem": dialog.access = FileDialog.ACCESS_FILESYSTEM
			_: dialog.access = FileDialog.ACCESS_USERDATA
	if values.has("filters"):
		var filters := PackedStringArray()
		for entry in values["filters"]:
			filters.append(str(entry))
		dialog.filters = filters
	if values.has("current_dir") and not String(values["current_dir"]).is_empty():
		dialog.current_dir = values["current_dir"]
	if values.has("disabled"):
		(get_node("Open") as Button).disabled = values["disabled"]
	UIPremadeContract.apply_common(self, values)


func open_dialog() -> void:
	if _dialog == null:
		_dialog = get_node("Dialog") as FileDialog
	_dialog.popup_centered_ratio(0.65)


func close_dialog() -> void:
	if _dialog == null:
		_dialog = get_node("Dialog") as FileDialog
	_dialog.hide()
