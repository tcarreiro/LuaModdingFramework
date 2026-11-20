class_name UIAnimationPlayer extends RefCounted

signal animation_finished(animation_id: String)
signal animation_interrupted(animation_id: String)

var errors: Array[String] = []
var current_animation: String = ""

var _registry: UIAnimationRegistry
var _target: Control
var _trusted := false
var _tween: Tween
var _generation := 0

func setup(registry: UIAnimationRegistry, target: Control, trusted: bool) -> void:
	_registry = registry
	_target = target
	_trusted = trusted


func play(animation_id: String) -> bool:
	errors.clear()
	if _registry == null:
		errors.append("No Animation Registry configured.")
		return false
	
	if _target == null or not is_instance_valid(_target) or not _target.is_inside_tree():
		errors.append("Animation target must be inside the SceneTree.")
		return false
	
	var definition := _registry._get_compiled(animation_id, _trusted)
	if definition == null:
		errors.append_array(_registry.errors)
		return false
	
	if not _validate_target(definition):
		return false
	stop()
	_apply_initial_values(definition)
	current_animation = animation_id
	_generation += 1
	var generation := _generation
	_tween = _target.create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(definition.trans)
	_tween.set_ease(definition.ease)
	_tween.set_loops(0 if typeof(definition.iterations) == TYPE_STRING and definition.iterations == "infinite" else int(definition.iterations))
	_build_tween(definition)
	_tween.finished.connect(_on_finished.bind(generation, animation_id))
	return true


func stop() -> void:
	var previous := current_animation
	_generation += 1
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	current_animation = ""
	if not previous.is_empty():
		animation_interrupted.emit(previous)


func is_playing() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


#region Execution
func _validate_target(definition: UIAnimationDefinition) -> bool:
	for property_name in definition.compiled_tracks:
		var track: Dictionary = definition.compiled_tracks[property_name]
		var path: NodePath = track["path"]
		var frames: Array = track["frames"]
		var current: Variant = _target.get_indexed(path)
		var expected: Variant = frames[0]["value"]
		if current == null:
			errors.append("Animation property '%s' is unavailable on this Control." % property_name)
			return false
		if typeof(current) != typeof(expected) \
				and not (typeof(current) == TYPE_FLOAT and typeof(expected) == TYPE_INT):
			errors.append("Incompatible animation property '%s' on this Control." % property_name)
			return false
	return true


func _apply_initial_values(definition: UIAnimationDefinition) -> void:
	for property_name in definition.compiled_tracks:
		var track: Dictionary = definition.compiled_tracks[property_name]
		var frames: Array = track["frames"]
		_target.set_indexed(track["path"], frames[0]["value"])


func _build_tween(definition: UIAnimationDefinition) -> void:
	for property_name in definition.compiled_tracks:
		var track: Dictionary = definition.compiled_tracks[property_name]
		var path: NodePath = track["path"]
		var frames: Array = track["frames"]
		for index in range(1, frames.size()):
			var previous: Dictionary = frames[index - 1]
			var current: Dictionary = frames[index]
			var delay: float = float(previous["time"]) * definition.duration
			var duration: float = (float(current["time"]) - float(previous["time"])) * definition.duration
			_tween.tween_property(
				_target, path, current["value"], duration
			).from(previous["value"]).set_delay(delay)


func _on_finished(generation: int, animation_id: String) -> void:
	if generation != _generation:
		return
	_tween = null
	current_animation = ""
	animation_finished.emit(animation_id)
#endregion
