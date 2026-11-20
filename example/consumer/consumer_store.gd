class_name ConsumerStore extends RefCounted

signal changed(section: String, key: String, value: Variant)

const SAVE_ROOT := "user://consumer/saves"

const DEFAULT_OPTIONS := {
	"master_volume": 80.0,
	"music_volume": 65.0,
	"effects_volume": 90.0,
	"spatial_audio": true,
	"resolution": "1920 × 1080",
	"quality": "Alta",
	"vsync": true,
	"language": "Português",
	"auto_save": true,
	"subtitles": true,
	"invert_y": false,
	"mouse_sensitivity": 50.0
}

var options: Dictionary = DEFAULT_OPTIONS.duplicate(true)


func set_option(key: String, value: Variant) -> void:
	if not options.has(key) or options[key] == value:
		return
	options[key] = value
	changed.emit("options", key, value)


func reset_options() -> void:
	for key in DEFAULT_OPTIONS:
		set_option(key, DEFAULT_OPTIONS[key])


func get_slot(index: int) -> Dictionary:
	if index < 1 or index > 3:
		return {}
	var path := _slot_path(index)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var content: Variant = JSON.parse_string(file.get_as_text())
	if not content is Dictionary or int(content.get("format", 0)) != 1:
		return {}
	return content


func save_slot(index: int, content: Dictionary) -> bool:
	if index < 1 or index > 3:
		return false
	if DirAccess.make_dir_recursive_absolute(SAVE_ROOT) != OK:
		return false
	var file := FileAccess.open(_slot_path(index), FileAccess.WRITE)
	if file == null:
		return false
	var data := content.duplicate(true)
	data["format"] = 1
	var date := Time.get_date_dict_from_system()
	data["last_played"] = "%02d/%02d/%04d" % [date.day, date.month, date.year]
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	changed.emit("saves", str(index), data)
	return true


func delete_slot(index: int) -> bool:
	var path := _slot_path(index)
	if not FileAccess.file_exists(path):
		return true
	var ok := DirAccess.remove_absolute(path) == OK
	if ok:
		changed.emit("saves", str(index), {})
	return ok


func _slot_path(index: int) -> String:
	return SAVE_ROOT.path_join("slot_%d.save" % index)
