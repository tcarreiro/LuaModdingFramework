class_name UIStyleContentRegistration extends RefCounted

const MAX_ENTRIES := 128
const MAX_DEPTH := 8
const MAX_STRING_LENGTH := 4096

const LAYOUT_KEYS := UIStyleProperties.LAYOUT_KEYS
const COLOR_KEYS := UIStyleProperties.COLOR_KEYS
const SOUND_KEYS := UIStyleProperties.SOUND_KEYS
const TWEEN_NAMES := {
	"linear": Vector2i(Tween.TRANS_LINEAR, Tween.EASE_IN_OUT),
	"ease": Vector2i(Tween.TRANS_SINE, Tween.EASE_IN_OUT),
	"ease-in": Vector2i(Tween.TRANS_SINE, Tween.EASE_IN),
	"ease-out": Vector2i(Tween.TRANS_SINE, Tween.EASE_OUT),
	"ease-in-out": Vector2i(Tween.TRANS_SINE, Tween.EASE_IN_OUT)
}

var errors: Array[String] = []
var _registry: UIStyleRegistry


func _init(registry: UIStyleRegistry) -> void:
	_registry = registry


func register(owner_id: String, style_id: Variant, descriptor: Variant) -> bool:
	errors.clear()
	if owner_id.is_empty():
		return _fail("UI.define_style requires an active mod.")
	if typeof(style_id) != TYPE_STRING or style_id.length() > 128 or not style_id.begins_with(owner_id + ":"):
		return _fail("Style ID must belong to '%s'." % owner_id)
	if _registry.is_finalized():
		return _fail("Styles cannot be defined after finalization.")
	if not descriptor is LuaTable:
		return _fail("UI.define_style expects a Lua table.")
	
	var raw := (descriptor as LuaTable).to_dictionary()
	if raw.size() > MAX_ENTRIES:
		return _fail("Style contains too many properties.")
	
	var style := UIStyleDefinition.new()
	style.id = style_id
	style.owner_mod_id = owner_id
	style.exposed_to_mods = false
	for key in raw:
		if typeof(key) != TYPE_STRING:
			return _fail("Style property names must be strings.")
		var value: Variant = raw[key]
		match key:
			"parent":
				if typeof(value) != TYPE_STRING:
					return _fail("Style parent must be a string.")
				style.parent = value
			"exposed_to_mods":
				if typeof(value) != TYPE_BOOL:
					return _fail("exposed_to_mods must be boolean.")
				style.exposed_to_mods = value
			"mod_overrides":
				style.mod_overrides = _string_array(value, key)
			"states":
				style.states = _dictionary(value, key)
			"transition_property":
				style.transition["properties"] = _string_array(value, key)
			"transition_duration":
				style.transition["duration"] = _convert(value, key)
			"transition_delay":
				style.transition["delay"] = _convert(value, key)
			"transition_timing_function":
				if typeof(value) != TYPE_STRING or not TWEEN_NAMES.has(value):
					return _fail("Unknown transition_timing_function '%s'." % str(value))
				var timing: Vector2i = TWEEN_NAMES[value]
				style.transition["trans"] = timing.x
				style.transition["ease"] = timing.y
			"styleboxes", "fonts", "state_styleboxes":
				return _fail("Native '%s' resources are configured by the consumer in GDScript." % key)
			"layout", "visual", "colors", "font_sizes", "sounds", "transition":
				return _fail("The '%s' style group has been removed from Lua. Declare properties at the root." % key)
			_:
				if not UIStyleProperties.is_property(key):
					return _fail("Unknown UI style property '%s'." % key)
				var converted: Variant = _convert(value, key)
				if errors.is_empty() and not UIStyleProperties.assign(style, key, converted):
					return _fail("Unsupported UI style property '%s'." % key)
		if not errors.is_empty():
			return false
	
	if not _registry.register_style(style):
		errors.append_array(_registry.errors)
		return false
	return true


func convert_inline_value(value: Variant, name: String) -> Variant:
	errors.clear()
	return _convert(value, name)


func parse_inline(values: Dictionary) -> UIStyleDefinition:
	errors.clear()
	var style := UIStyleDefinition.new()
	for name in values:
		if typeof(name) != TYPE_STRING or not UIStyleProperties.is_property(name):
			_fail("Unsupported inline UI style property '%s'." % str(name))
			return null
		var value: Variant = values[name]
		match name:
			"states":
				style.states = _dictionary(value, name)
			"transition_property":
				style.transition["properties"] = _string_array(value, name)
			"transition_duration":
				style.transition["duration"] = _convert(value, name)
			"transition_delay":
				style.transition["delay"] = _convert(value, name)
			"transition_timing_function":
				if typeof(value) != TYPE_STRING or not TWEEN_NAMES.has(value):
					_fail("Unknown transition_timing_function '%s'." % str(value))
					return null
				var timing: Vector2i = TWEEN_NAMES[value]
				style.transition["trans"] = timing.x
				style.transition["ease"] = timing.y
			_:
				UIStyleProperties.assign(style, name, _convert(value, name))
		if not errors.is_empty():
			return null
	return style


func _dictionary(value: Variant, path: String, depth: int = 0) -> Dictionary:
	if depth > MAX_DEPTH or not value is LuaTable and not value is Dictionary:
		_fail("Style '%s' must be a Lua map within nesting limits." % path)
		return {}
	var result: Dictionary = {}
	var source: Dictionary = (value as LuaTable).to_dictionary() if value is LuaTable else value
	if source.size() > MAX_ENTRIES:
		_fail("Style '%s' has too many entries." % path)
		return {}
	for key in source:
		if typeof(key) != TYPE_STRING:
			_fail("Style '%s' requires string keys." % path)
			return {}
		result[key] = _convert(source[key], str(key), depth + 1)
		if not errors.is_empty():
			return {}
	return result


func _convert(value: Variant, name: String, depth: int = 0) -> Variant:
	if depth > MAX_DEPTH:
		_fail("Style exceeds maximum nesting depth.")
		return null
	if typeof(value) == TYPE_STRING:
		if value.length() > MAX_STRING_LENGTH:
			_fail("Style string is too long: '%s'." % name)
			return null
		if name.ends_with("color") or name == "background_image_tint":
			if Color.html_is_valid(value):
				return Color.html(value)
			var invalid := Color(-1.0, -1.0, -1.0, -1.0)
			var parsed := Color.from_string(value, invalid)
			if parsed == invalid:
				_fail("Invalid color for '%s': '%s'." % [name, value])
				return null
			return parsed
		return value
	if not value is LuaTable and not value is Dictionary:
		return value
	var source: Dictionary = (value as LuaTable).to_dictionary() if value is LuaTable else value
	if source.size() > MAX_ENTRIES:
		_fail("Style array/map is too large: '%s'." % name)
		return null
	if name in ["min_size", "pivot_ratio", "pivot_offset", "scale", "drop_shadow_offset", "translate"]:
		if source.has("x") and source.has("y") and source.size() == 2:
			if typeof(source["x"]) in [TYPE_INT, TYPE_FLOAT] and typeof(source["y"]) in [TYPE_INT, TYPE_FLOAT]:
				return Vector2(source["x"], source["y"])
		_fail("Style '%s' must contain numeric x and y." % name)
		return null
	if name in ["padding", "margin", "border_width", "border_radius", "corner_radius", "background_image_slice"]:
		if source.size() == 4 and source.has("left") and source.has("top") and source.has("right") and source.has("bottom"):
			return Vector4(source["left"], source["top"], source["right"], source["bottom"])
		if name in ["border_radius", "corner_radius"] and source.size() == 4 and source.has("top_left") and source.has("top_right") and source.has("bottom_right") and source.has("bottom_left"):
			return Vector4(source["top_left"], source["top_right"], source["bottom_right"], source["bottom_left"])
		_fail("Style edges require left, top, right and bottom.")
		return null
	var sequential := true
	for index in range(1, source.size() + 1):
		if not source.has(index):
			sequential = false
			break
	if sequential:
		var result: Array = []
		for index in range(1, source.size() + 1):
			result.append(_convert(source[index], name, depth + 1))
		return result
	return _dictionary(value, name, depth + 1)


func _string_array(value: Variant, path: String) -> Array[String]:
	var converted: Variant = _convert(value, path)
	var result: Array[String] = []
	if not converted is Array:
		_fail("Style '%s' must be an array." % path)
		return result
	for item in converted:
		if typeof(item) != TYPE_STRING:
			_fail("Style '%s' accepts only strings." % path)
			return []
		result.append(item)
	return result


func _fail(message: String) -> bool:
	errors.append(message)
	return false
