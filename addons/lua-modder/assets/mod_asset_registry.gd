class_name ModAssetRegistry extends RefCounted

const MAX_IMAGE_BYTES := 16 * 1024 * 1024
const MAX_AUDIO_BYTES := 24 * 1024 * 1024
const MAX_IMAGE_DIMENSION := 4096

const IMAGE_EXTENSIONS := ["png", "webp", "jpg", "jpeg"]
const AUDIO_EXTENSIONS := ["ogg", "wav", "mp3"]

var errors: Array[String] = []

var _roots: Dictionary[String, String] = {}
var _textures: Dictionary[String, Texture2D] = {}
var _sounds: Dictionary[String, AudioStream] = {}

func configure(mods: Array[ModManifest]) -> void:
	clear()
	for manifest in mods:
		_roots[manifest.id] = manifest.root_path


func get_texture(asset_id: String) -> Texture2D:
	errors.clear()
	if _textures.has(asset_id):
		return _textures[asset_id]
	var path := _resolve_path(asset_id, IMAGE_EXTENSIONS)
	if path.is_empty():
		return null
	var texture := _load_texture(path)
	if texture == null:
		errors.append("Cannot load texture '%s'." % asset_id)
		return null
	_textures[asset_id] = texture
	return texture


func get_sound(asset_id: String) -> AudioStream:
	errors.clear()
	if _sounds.has(asset_id):
		return _sounds[asset_id]
	var path := _resolve_path(asset_id, AUDIO_EXTENSIONS)
	if path.is_empty():
		return null
	var stream := _load_sound(path)
	if stream == null:
		errors.append("Cannot load sound '%s'." % asset_id)
		return null
	_sounds[asset_id] = stream
	return stream


func _resolve_path(asset_id: String, allowed_extensions: Array) -> String:
	var separator := asset_id.find(":")
	if separator <= 0 or separator >= asset_id.length() - 1:
		errors.append("Invalid asset ID '%s'." % asset_id)
		return ""
	var mod_id := asset_id.substr(0, separator)
	var relative := asset_id.substr(separator + 1)
	if not _roots.has(mod_id):
		errors.append("Asset '%s' belongs to an unavailable mod." % asset_id)
		return ""
	if not _valid_relative_path(relative, allowed_extensions):
		errors.append("Invalid asset path '%s'." % asset_id)
		return ""
	return _roots[mod_id].path_join("assets").path_join(relative)


func _valid_relative_path(path: String, extensions: Array) -> bool:
	if path.is_empty() or path.length() > 256:
		return false
	if path.begins_with("/") or path.contains("\\") or path.contains(":"):
		return false
	if path.get_extension().to_lower() not in extensions:
		return false
	for part in path.split("/", true):
		if part.is_empty() or part in [".", ".."]:
			return false
	return true


func _load_texture(path: String) -> Texture2D:
	if path.begins_with("res://"):
		var imported := ResourceLoader.load(path) as Texture2D
		if imported != null:
			return imported
	if not _check_file_size(path, MAX_IMAGE_BYTES):
		return null
	var image := Image.new()
	var result := image.load(path)
	if result != OK:
		errors.append("Image decoding failed: '%s'." % path)
		return null
	if image.get_width() <= 0 or image.get_height() <= 0:
		errors.append("Image has invalid dimensions: '%s'." % path)
		return null
	if image.get_width() > MAX_IMAGE_DIMENSION \
			or image.get_height() > MAX_IMAGE_DIMENSION:
		errors.append("Image exceeds allowed dimensions: '%s'." % path)
		return null
	return ImageTexture.create_from_image(image)


func _load_sound(path: String) -> AudioStream:
	if path.begins_with("res://"):
		var imported := ResourceLoader.load(path) as AudioStream
		if imported != null:
			return imported
	if not _check_file_size(path, MAX_AUDIO_BYTES):
		return null
	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
	return null


func _check_file_size(path: String, limit: int) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Cannot open asset file '%s'." % path)
		return false
	var file_size := file.get_length()
	file.close()
	if file_size <= 0 or file_size > limit:
		errors.append("Asset file exceeds size limits: '%s'." % path)
	return true


func clear() -> void:
	_textures.clear()
	_sounds.clear()
	_roots.clear()
	errors.clear()
