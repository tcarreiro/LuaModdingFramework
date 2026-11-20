class_name UIComponentSprite extends TextureRect

signal frame_changed(frame: int)
signal finished

var _assets: ModAssetRegistry

var _settings: Dictionary = {}

var _source_id := ""
var _source: Texture2D
var _atlas := AtlasTexture.new()

var _hframes := 1
var _vframes := 1
var _frame_count := 1
var _frame := 0
var _elapsed := 0.0

var _playing := false
var _loop := true
var _ended := false


func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	_refresh_processing()


func get_premade_definition() -> UIComponentDefinition:
	return UIPremadeContract.create_definition(
		UIBuiltinIds.SPRITE,
		{
			UIKeys.PROP_TEXTURE: UIPremadeContract.property(TYPE_STRING, ""),
			UIKeys.PROP_HFRAMES: UIPremadeContract.property(TYPE_INT, 1),
			UIKeys.PROP_VFRAMES: UIPremadeContract.property(TYPE_INT, 1),
			UIKeys.PROP_FRAME_COUNT: UIPremadeContract.property(TYPE_INT, 0),
			UIKeys.PROP_FRAME: UIPremadeContract.property(TYPE_INT, 0),
			UIKeys.PROP_FPS: UIPremadeContract.property(TYPE_FLOAT, 12.0),
			UIKeys.PROP_DURATION: UIPremadeContract.property(TYPE_FLOAT, 0.0),
			UIKeys.PROP_LOOP: UIPremadeContract.property(TYPE_BOOL, true),
			UIKeys.PROP_PLAYING: UIPremadeContract.property(TYPE_BOOL, true),
			UIKeys.PROP_FILTER_MODE: UIPremadeContract.property(TYPE_STRING, UIKeys.VAL_INHERIT),
			UIKeys.PROP_REPEAT: UIPremadeContract.property(TYPE_STRING, UIKeys.VAL_INHERIT)
		},
		"",
		[
			UIKeys.EVENT_FRAME_CHANGED,
			UIKeys.EVENT_FINISHED,
			UIKeys.EVENT_MOUSE_ENTERED,
			UIKeys.EVENT_MOUSE_EXITED
		]
	)


func set_asset_registry(registry: ModAssetRegistry) -> void:
	_assets = registry


func apply_premade_properties(values: Dictionary) -> void:
	var resolver := Callable()
	if _assets != null:
		resolver = Callable(_assets, "get_texture")
	configure(values, resolver)
	UIPremadeContract.apply_common(self, values)


func configure(values: Dictionary, texture_resolver: Callable) -> void:
	var rebuild := _needs_rebuild(values)
	_settings.merge(values, true)
	if rebuild:
		_rebuild(texture_resolver)
	if values.has("fps") or values.has("duration"):
		_elapsed = float(_frame) * _seconds_per_frame()
	if values.has("frame"):
		set_frame(int(values["frame"]))
	if values.has("loop"):
		_loop = bool(values["loop"])
	if values.has("filter_mode"):
		_apply_filter_mode(values["filter_mode"])
	if values.has("repeat"):
		_apply_repeat(values["repeat"])
	if values.has("playing"):
		if bool(values["playing"]):
			play()
		else:
			pause()


func _needs_rebuild(changes: Dictionary) -> bool:
	for name in ["texture", "hframes", "vframes", "frame_count"]:
		if changes.has(name) and changes[name] != _settings.get(name):
			return true
	return false


func _rebuild(texture_resolver: Callable) -> void:
	var requested_id := String(_settings.get("texture", ""))
	if requested_id != _source_id:
		_source_id = requested_id
		_source = null
		if not requested_id.is_empty():
			if texture_resolver.is_valid():
				_source = texture_resolver.call(requested_id) as Texture2D
			if _source == null:
				push_warning(
					"[UIComponentSprite] Cannot load texture '%s'." % requested_id
				)
	_hframes = maxi(1, int(_settings.get("hframes", 1)))
	_vframes = maxi(1, int(_settings.get("vframes", 1)))
	var available_frames := _hframes * _vframes
	var declared_frames := int(_settings.get("frame_count", 0))
	_frame_count = (
		clampi(declared_frames, 1, available_frames)
		if declared_frames > 0
		else available_frames
	)
	_atlas.atlas = _source
	texture = _atlas if _source != null else null
	_elapsed = 0.0
	_ended = false
	_frame = -1
	_set_frame_internal(
		clampi(int(_settings.get("frame", 0)), 0, _frame_count - 1)
	)
	_refresh_processing()


func _set_frame_internal(index: int) -> void:
	if _frame == index:
		return
	_frame = index
	if _source != null:
		var cell_size := _source.get_size() / Vector2(_hframes, _vframes)
		var column := index % _hframes
		var row := floori(float(index) / float(_hframes))
		_atlas.region = Rect2(
			Vector2(column, row) * cell_size,
			cell_size
		)
	frame_changed.emit(index)


func _seconds_per_frame() -> float:
	var duration := float(_settings.get("duration", 0.0))
	if duration > 0.0:
		return duration / float(_frame_count)
	return 1.0 / maxf(0.001, float(_settings.get("fps", 12.0)))


func _refresh_processing() -> void:
	set_process(
		_playing
		and _source != null
		and _frame_count > 1
	)


func _process(delta: float) -> void:
	var seconds := _seconds_per_frame()
	var previous_step := floori(_elapsed / seconds)
	_elapsed += delta
	var current_step := floori(_elapsed / seconds)
	if not _loop and current_step >= _frame_count:
		_set_frame_internal(_frame_count - 1)
		_ended = true
		pause()
		finished.emit()
		return
	if _loop:
		var current:= floori(float(current_step)/float(_frame_count))
		var previous:= floori(float(previous_step)/float(_frame_count))
		if current > previous:
			finished.emit()
		_set_frame_internal(current_step % _frame_count)
	else:
		_set_frame_internal(current_step)


func play() -> void:
	if _ended:
		_ended = false
		set_frame(0)
	_playing = true
	_refresh_processing()


func pause() -> void:
	_playing = false
	_refresh_processing()


func stop() -> void:
	_playing = false
	_ended = false
	_elapsed = 0.0
	set_frame(0)
	_refresh_processing()


func set_frame(index: int) -> void:
	var target := clampi(index, 0, _frame_count - 1)
	_ended = false
	_elapsed = float(target) * _seconds_per_frame()
	_set_frame_internal(target)



func _apply_filter_mode(mode: String) -> void:
	match mode:
		UIKeys.VAL_INHERIT:
			texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
		"nearest":
			texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		"linear":
			texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		"nearest_mipmap":
			texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		"linear_mipmap":
			texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		"nearest_mipmap_anisotropic":
			texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
		"linear_mipmap_anisotropic":
			texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_:
			push_warning("[UIComponentSprite] Unknown filter_mode '%s'." % mode)


func _apply_repeat(mode: String) -> void:
	match mode:
		UIKeys.VAL_INHERIT:
			texture_repeat = CanvasItem.TEXTURE_REPEAT_PARENT_NODE
		"disabled":
			texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
		"enabled":
			texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		"mirror":
			texture_repeat = CanvasItem.TEXTURE_REPEAT_MIRROR
		_:
			push_warning("[UIComponentSprite] Unknown repeat '%s'." % mode)
