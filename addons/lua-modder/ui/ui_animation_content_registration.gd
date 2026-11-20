class_name UIAnimationContentRegistration extends RefCounted

const MAX_KEYFRAMES := 64
const MAX_CHANNELS_PER_KEYFRAME := 16

var errors: Array[String] = []
var _registry: UIAnimationRegistry


func _init(registry: UIAnimationRegistry) -> void:
	_registry = registry


func register(owner_id: String, animation_id: Variant, descriptor: Variant) -> bool:
	errors.clear()
	if owner_id.is_empty() or typeof(animation_id) != TYPE_STRING or not animation_id.begins_with(owner_id + ":") or animation_id.length() > 128:
		return _fail("Animation ID must belong to the active mod.")
	if _registry.is_finalized():
		return _fail("Animations cannot be defined after finalization.")
	if not descriptor is LuaTable:
		return _fail("UI.define_animation expects a Lua table.")

	var raw := (descriptor as LuaTable).to_dictionary()
	for key in raw:
		if key not in ["duration", "timing_function", "iterations", "keyframes", "exposed_to_mods"]:
			return _fail("Unknown UI animation property '%s'." % str(key))

	var animation := UIAnimationDefinition.new()
	animation.id = animation_id
	animation.owner_mod_id = owner_id
	animation.exposed_to_mods = false

	if raw.has("exposed_to_mods"):
		if typeof(raw["exposed_to_mods"]) != TYPE_BOOL:
			return _fail("exposed_to_mods must be boolean.")
		animation.exposed_to_mods = raw["exposed_to_mods"]
	if raw.has("duration"):
		if typeof(raw["duration"]) not in [TYPE_INT, TYPE_FLOAT]:
			return _fail("Animation duration must be numeric.")
		animation.duration = float(raw["duration"])
	if raw.has("iterations"):
		animation.iterations = raw["iterations"]
	if raw.has("timing_function"):
		var function_name: Variant = raw["timing_function"]
		if typeof(function_name) != TYPE_STRING or not UIStyleContentRegistration.TWEEN_NAMES.has(function_name):
			return _fail("Unknown animation timing_function '%s'." % str(function_name))
		var timing: Vector2i = UIStyleContentRegistration.TWEEN_NAMES[function_name]
		animation.trans = timing.x
		animation.ease = timing.y

	if not raw.get("keyframes") is LuaTable:
		return _fail("Animation keyframes must be a Lua array.")
	var frames: Dictionary = (raw["keyframes"] as LuaTable).to_dictionary()
	if frames.size() < 2 or frames.size() > MAX_KEYFRAMES:
		return _fail("Animations require 2 to %d keyframes." % MAX_KEYFRAMES)

	for index in range(1, frames.size() + 1):
		if not frames.has(index) or not frames[index] is LuaTable:
			return _fail("Animation keyframes must be a sequential array of tables.")
		var frame: Dictionary = (frames[index] as LuaTable).to_dictionary()
		if frame.size() != 2 or not frame.has("time") or not frame.has("values"):
			return _fail("Keyframe %d requires time and values." % index)
		if typeof(frame["time"]) not in [TYPE_INT, TYPE_FLOAT] or not frame["values"] is LuaTable:
			return _fail("Invalid types in keyframe %d." % index)
		var raw_values: Dictionary = (frame["values"] as LuaTable).to_dictionary()
		if raw_values.is_empty() or raw_values.size() > MAX_CHANNELS_PER_KEYFRAME:
			return _fail("Invalid channel count in keyframe %d." % index)
		var values: Dictionary = {}
		for channel in raw_values:
			if typeof(channel) != TYPE_STRING:
				return _fail("Animation channels must have string names.")
			var converted: Variant = _channel_value(channel, raw_values[channel])
			if not errors.is_empty():
				return false
			values[channel] = converted
		animation.keyframes.append({"time": float(frame["time"]), "values": values})

	if not _registry.register_animation(animation):
		errors.append_array(_registry.errors)
		return false
	return true


func _channel_value(channel: String, source: Variant) -> Variant:
	match channel:
		"scale", "position":
			if source is LuaTable:
				var data: Dictionary = (source as LuaTable).to_dictionary()
				if data.size() == 2 and typeof(data.get("x")) in [TYPE_INT, TYPE_FLOAT] and typeof(data.get("y")) in [TYPE_INT, TYPE_FLOAT]:
					return Vector2(data["x"], data["y"])
			_fail("Animation channel '%s' requires {x, y}." % channel)
			return null
		"tint":
			if typeof(source) == TYPE_STRING and Color.html_is_valid(source):
				return Color.html(source)
			_fail("Animation tint must be an HTML color.")
			return null
		"opacity", "rotation":
			if typeof(source) in [TYPE_INT, TYPE_FLOAT]:
				return float(source)
			_fail("Animation channel '%s' requires a number." % channel)
			return null
		_:
			_fail("Unknown animation channel '%s'." % channel)
			return null


func _fail(message: String) -> bool:
	errors.append(message)
	return false
