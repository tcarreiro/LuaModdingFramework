@tool
class_name UIAnimationRegistry extends Registry

var _definitions: Dictionary[String, UIAnimationDefinition] = {}
var _prepared: Dictionary[String, UIAnimationDefinition] = {}
var _finalized := false

var _channels: Dictionary = {
	"opacity": {"path": NodePath("modulate:a"), "type": TYPE_FLOAT},
	"scale": {"path": NodePath("scale"), "type": TYPE_VECTOR2},
	"position": {"path": NodePath("position"), "type": TYPE_VECTOR2},
	"rotation": {"path": NodePath("rotation"), "type": TYPE_FLOAT},
	"tint": {"path": NodePath("self_modulate"), "type": TYPE_COLOR}
}

func register_channel(name: String, property_path: NodePath, value_type: int) -> bool:
	if _finalized:
		errors.append("Animation Registry is finalized.")
		return false
	
	if name.strip_edges().is_empty() or _channels.has(name) or property_path.is_empty():
		errors.append("Invalid or duplicate animation channel '%s'." % name)
		return false
	
	if value_type not in [TYPE_INT, TYPE_FLOAT, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR]:
		errors.append("Unsupported animation channel type for '%s'." % name)
		return false
	
	_channels[name] = {"path": property_path, "type": value_type}
	return true


func register_animation(definition: UIAnimationDefinition) -> bool:
	if _finalized:
		errors.append("Animation Registry is finalized.")
		return false
	
	if definition == null or definition.id.strip_edges().is_empty():
		errors.append("Invalid animation definition.")
		return false
	
	if _definitions.has(definition.id):
		errors.append("Duplicate animation '%s'." % definition.id)
		return false
	
	if not definition.owner_mod_id.is_empty() \
			and not definition.id.begins_with(definition.owner_mod_id + ":"):
		errors.append("Animation '%s' has an invalid owner namespace." % definition.id)
		return false
	
	_definitions[definition.id] = definition.copy()
	return true


func finalize() -> bool:
	if _finalized:
		return true
	
	if not errors.is_empty():
		return false
	
	for id in _definitions:
		var compiled := _compile(_definitions[id])
		if compiled == null:
			return false
		_prepared[id] = compiled
	
	_finalized = true
	return true


func has_animation(id: String) -> bool:
	return _definitions.has(id)


func is_finalized() -> bool:
	return _finalized


func get_definition(id: String) -> UIAnimationDefinition:
	return _definitions[id].copy() if _definitions.has(id) else null


func _get_compiled(id: String, trusted: bool) -> UIAnimationDefinition:
	if not _finalized or not _prepared.has(id):
		errors.append("Animation '%s' is unavailable." % id)
		return null
	
	var definition := _prepared[id]
	if not trusted and not definition.exposed_to_mods:
		errors.append("Animation '%s' is not exposed to mods." % id)
		return null
	return definition


#region Compilation
func _compile(definition: UIAnimationDefinition) -> UIAnimationDefinition:
	if not _validate_configuration(definition):
		return null
	
	var tracks: Dictionary = {}
	var previous_time := -1.0
	for index in range(definition.keyframes.size()):
		var frame: Dictionary = definition.keyframes[index]
		var at: float = frame["time"]
		if at <= previous_time:
			return _compile_error(definition.id, "Keyframe times must be strictly increasing.")
		previous_time = at
		var values: Dictionary = frame["values"]
		for property_name in values:
			if not _validate_value(definition.id, property_name, values[property_name]):
				return null
			if not tracks.has(property_name):
				tracks[property_name] = []
			tracks[property_name].append({
				"time": at,
				"value": values[property_name]
			})
	var compiled := definition.copy()
	for property_name in tracks:
		var frames: Array = tracks[property_name]
		if frames.size() < 2 \
				or not is_equal_approx(frames[0]["time"], 0.0) \
				or not is_equal_approx(frames[-1]["time"], 1.0):
			return _compile_error(definition.id, "Property '%s' requires keyframes at 0 and 1." % property_name)
		compiled.compiled_tracks[property_name] = {
			"path": _channels[property_name]["path"],
			"frames": frames
		}
	return compiled


func _validate_configuration(definition: UIAnimationDefinition) -> bool:
	if not is_finite(definition.duration) or definition.duration <= 0:
		errors.append("Animation '%s' requires a positive duration." % definition.id)
		return false
	
	if definition.trans < Tween.TRANS_LINEAR or definition.trans > Tween.TRANS_SPRING:
		errors.append("Invalid transition type for '%s'." % definition.id)
		return false
	
	if definition.ease < Tween.EASE_IN or definition.ease > Tween.EASE_OUT_IN:
		errors.append("Invalid easing for '%s'." % definition.id)
		return false
	
	if typeof(definition.iterations) == TYPE_STRING:
		if definition.iterations != "infinite":
			errors.append("Invalid iteration count for '%s'." % definition.id)
			return false
	elif typeof(definition.iterations) != TYPE_INT or definition.iterations < 1:
		errors.append("Invalid iteration count for '%s'." % definition.id)
		return false
	
	if definition.keyframes.size() < 2:
		errors.append("Animation '%s' requires at least two keyframes." % definition.id)
		return false
	
	for index in range(definition.keyframes.size()):
		var frame: Dictionary = definition.keyframes[index]
		var at: Variant = frame.get("time")
		var values: Variant = frame.get("values")
	
		if typeof(at) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(at)) or at < 0 or at > 1 \
				or not values is Dictionary or values.is_empty():
			errors.append("Invalid keyframe %d in '%s'." % [index, definition.id])
			return false
	
	if not is_equal_approx(float(definition.keyframes[0]["time"]), 0.0) \
			or not is_equal_approx(float(definition.keyframes[-1]["time"]), 1.0):
		errors.append("Animation '%s' must start at 0 and end at 1." % definition.id)
		return false
	
	return true


func _validate_value(animation_id: String, name: String, value: Variant) -> bool:
	if not _channels.has(name):
		errors.append("Unknown animation channel '%s' in '%s'." % [name, animation_id])
		return false
	
	var expected: int = _channels[name]["type"]
	var actual := typeof(value)
	if actual != expected and not (expected == TYPE_FLOAT and actual == TYPE_INT):
		errors.append("Invalid value type for '%s.%s'." % [animation_id, name])
		return false
	
	if name == "opacity" and (value < 0 or value > 1):
		errors.append("Opacity must be between 0 and 1.")
		return false
	
	if actual == TYPE_FLOAT and not is_finite(value):
		errors.append("Non-finite animation value for '%s.%s'." % [animation_id, name])
		return false
	
	return true


func _compile_error(animation_id: String, message: String) -> UIAnimationDefinition:
	errors.append("Animation '%s': %s" % [animation_id, message])
	return null
#endregion


func clear() -> void:
	_definitions.clear()
	_prepared.clear()
	_finalized = false
	errors.clear()
	warnings.clear()
