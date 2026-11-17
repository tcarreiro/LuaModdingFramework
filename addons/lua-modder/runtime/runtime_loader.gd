
class_name RuntimeLoader extends RefCounted

const CONTROL_FILE_NAME := "control.lua"
const MAX_CONTROL_FILE_BYTES := 1 * 1024 * 1024

var errors: Array[String] = []


func has_control(manifest: ModManifest) -> bool:
	return FileAccess.file_exists(get_control_path(manifest))


func get_control_path(manifest: ModManifest) -> String:
	return manifest.root_path.path_join(CONTROL_FILE_NAME)


func read_control(manifest: ModManifest) -> String:
	errors.clear()
	var path := get_control_path(manifest)
	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		errors.append("Cannot open control.lua for mod '%s': '%s'." % [manifest.id, path])
		return ""

	if file.get_length() > MAX_CONTROL_FILE_BYTES:
		errors.append("control.lua exceeds the %d-byte limit for mod '%s': '%s'." % [
			MAX_CONTROL_FILE_BYTES, manifest.id, path
		])
		return ""

	var source := file.get_as_text()
	if file.get_error() != OK and file.get_error() != ERR_FILE_EOF:
		errors.append("Cannot read control.lua for mod '%s': '%s'." % [manifest.id, path])
		return ""

	return source
