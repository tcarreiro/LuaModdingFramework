class_name UIComponentTextInput extends LineEdit

signal validated_text_changed(value: String)
signal validated_text_submitted(value: String)
signal value_submitted(value: Variant)
signal validation_failed(value: String)

var _validation := "text"
var _allow_negative := false
var _allow_empty := true
var _decimal_separator := "both"

var _has_min := false
var _has_max := false
var _min_value := 0.0
var _max_value := 0.0

var _accepted_text := ""
var _pattern := RegEx.new()


func _ready() -> void:
	text_changed.connect(_on_text_changed)
	text_submitted.connect(_on_text_submitted)
	_accepted_text = text


func get_premade_definition() -> UIComponentDefinition:
	var definition := UIPremadeContract.create_definition(
		UIBuiltinIds.TEXT_INPUT,
		{
			UIKeys.PROP_TEXT: UIPremadeContract.property(TYPE_STRING, ""),
			UIKeys.PROP_PLACEHOLDER: UIPremadeContract.property(TYPE_STRING, ""),
			UIKeys.PROP_EDITABLE: UIPremadeContract.property(TYPE_BOOL, true),
			UIKeys.PROP_SECRET: UIPremadeContract.property(TYPE_BOOL, false),
			UIKeys.PROP_MAX_LENGTH: UIPremadeContract.property(TYPE_INT, 0),
			UIKeys.PROP_CLEAR_BUTTON: UIPremadeContract.property(TYPE_BOOL, false),
			UIKeys.PROP_VALIDATION: UIPremadeContract.property(TYPE_STRING, "text"),
			UIKeys.PROP_ALLOW_NEGATIVE: UIPremadeContract.property(TYPE_BOOL, false),
			UIKeys.PROP_ALLOW_EMPTY: UIPremadeContract.property(TYPE_BOOL, true),
			UIKeys.PROP_DECIMAL_SEPARATOR: UIPremadeContract.property(TYPE_STRING, "both"),
			UIKeys.PROP_MIN: {"type": TYPE_FLOAT, "mod_editable": true},
			UIKeys.PROP_MAX: {"type": TYPE_FLOAT, "mod_editable": true}
		},
		UIBuiltinIds.STYLE_TEXT_INPUT,
		[
			UIKeys.EVENT_TEXT_CHANGED,
			UIKeys.EVENT_TEXT_SUBMITTED,
			UIKeys.EVENT_VALUE_SUBMITTED,
			UIKeys.EVENT_VALIDATION_FAILED,
			UIKeys.EVENT_FOCUS_ENTERED,
			UIKeys.EVENT_FOCUS_EXITED,
			UIKeys.EVENT_MOUSE_ENTERED,
			UIKeys.EVENT_MOUSE_EXITED
		]
	)
	
	definition.event_sources[UIKeys.EVENT_TEXT_CHANGED] = {
		"path": NodePath("."),
		"signal": &"validated_text_changed"
	}
	definition.event_sources[UIKeys.EVENT_TEXT_SUBMITTED] = {
		"path": NodePath("."),
		"signal": &"validated_text_submitted"
	}
	return definition


func get_premade_styles() -> Array[UIStyleDefinition]:
	var style := UIStyleDefinition.new()
	style.id = UIBuiltinIds.STYLE_TEXT_INPUT
	style.visual = {
		UIKeys.PROP_BACKGROUND_COLOR: Color("#202938"),
		UIKeys.PROP_BORDER_COLOR: Color("#536780"),
		UIKeys.PROP_BORDER_WIDTH: 1,
		UIKeys.PROP_BORDER_RADIUS: 6,
		UIKeys.PROP_PADDING: 8
	}
	style.colors = {
		"font_color": Color("#EDF5FF"),
		"font_placeholder_color": Color("#93A3B8")
	}
	return [style]


func apply_premade_properties(values: Dictionary) -> void:
	configure(values)
	UIPremadeContract.apply_common(self, values)


func configure(values: Dictionary) -> void:
	_configure_input_validation(values)
	
	if values.has("placeholder"):
		placeholder_text = values["placeholder"]
	
	if values.has("editable"):
		editable = values["editable"]
	
	if values.has("secret"):
		secret = values["secret"]
		
	if values.has("max_length"):
		max_length = maxi(0, values["max_length"])
	
	if values.has("clear_button"):
		clear_button_enabled = values["clear_button"]
	
	if values.has("text"):
		var candidate: String = values["text"]
	
		if _accepts_partial(candidate):
			text = candidate
		else:
			push_warning("TextInput rejected an invalid initial value.")
	
	if not _accepts_partial(text):
		text = ""
	
	text = _clamp_numeric_text(text)
	_accepted_text = text
	_configure_keyboard()


func _configure_input_validation(values: Dictionary) -> void:
	_validation = values.get("validation", _validation)
	_allow_negative = values.get("allow_negative", _allow_negative)
	_allow_empty = values.get("allow_empty", _allow_empty)
	_decimal_separator = values.get("decimal_separator", _decimal_separator)
	
	if values.has("min"):
		_has_min = true
		_min_value = float(values["min"])
	
	if values.has("max"):
		_has_max = true
		_max_value = float(values["max"])
	
	_compile_validator()


func _compile_validator() -> void:
	if _validation == "text":
		return
	
	var sign_pattern := "-?" if _allow_negative else ""
	var expression := ""
	match _validation:
		"integer":
			expression = "^%s[0-9]*$" % sign_pattern
		"decimal":
			var separator_pattern := "[.,]"
			match _decimal_separator:
				".":
					separator_pattern = "\\."
				",":
					separator_pattern = ","
				"both":
					pass
				_:
					push_warning("Unknown decimal separator. Using both.")
					_decimal_separator = "both"
			expression = "^%s[0-9]*(?:%s[0-9]*)?$" % [
				sign_pattern,
				separator_pattern
			]
		_:
			push_warning("Unknown TextInput validation mode: %s" % _validation)
			_validation = "text"
			return
	if _pattern.compile(expression) != OK:
		push_error("Cannot compile TextInput validation pattern.")
		_validation = "text"


func _configure_keyboard() -> void:
	match _validation:
		"integer":
			virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
		"decimal":
			virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
		_:
			virtual_keyboard_type = (
				LineEdit.KEYBOARD_TYPE_PASSWORD
				if secret else LineEdit.KEYBOARD_TYPE_DEFAULT
			)


func _accepts_partial(value: String) -> bool:
	if _validation == "text":
		return true

	return _pattern.search(value) != null


func is_value_valid() -> bool:
	if not _accepts_partial(text):
		return false
	
	if text.is_empty():
		return _allow_empty
	
	if _validation == "text":
		return true
	
	if _has_min and _has_max and _min_value > _max_value:
		return false
	
	var has_digit := false
	for character in text:
		if character >= "0" and character <= "9":
			has_digit = true
			break
	
	if not has_digit:
		return false
	
	var numeric_value := float(text.replace(",", "."))
	if not is_finite(numeric_value):
		return false
	
	if _has_min and numeric_value < _min_value:
		return false
	
	if _has_max and numeric_value > _max_value:
		return false
	return true



func get_value() -> Variant:
	if not is_value_valid():
		return null

	if _validation == "text":
		return text

	if text.is_empty():
		return null

	if _validation == "integer":
		return int(text)

	return float(text.replace(",", "."))



func _on_text_changed(new_text: String) -> void:
	if not _accepts_partial(new_text):
		var restore_caret := _common_prefix_length(_accepted_text, new_text)
		text = _accepted_text
		caret_column = restore_caret
		return

	var corrected := _clamp_numeric_text(new_text)
	if corrected != new_text:
		var previous_caret := caret_column
		text = corrected
		caret_column = mini(previous_caret, corrected.length())

	_accepted_text = corrected
	validated_text_changed.emit(corrected)



func _on_text_submitted(_raw_text: String) -> void:
	if not is_value_valid():
		validation_failed.emit(text)
		return

	validated_text_submitted.emit(text)
	value_submitted.emit(get_value())


func _common_prefix_length(first: String, second: String) -> int:
	var limit := mini(first.length(), second.length())

	for index in range(limit):
		if first[index] != second[index]:
			return index

	return limit


func _clamp_numeric_text(value: String) -> String:
	if _validation not in ["integer", "decimal"]:
		return value
	if not _has_min and not _has_max:
		return value
	var has_digit := false
	for character in value:
		if character >= "0" and character <= "9":
			has_digit = true
			break
	if not has_digit:
		return value
	var numeric := float(value.replace(",", "."))
	if not is_finite(numeric):
		return value
	var corrected := numeric
	if _has_min:
		var minimum := _min_value
		if _validation == "integer":
			minimum = ceilf(minimum)
		corrected = maxf(corrected, minimum)
	if _has_max:
		var maximum := _max_value
		if _validation == "integer":
			maximum = floorf(maximum)
		corrected = minf(corrected, maximum)
	if corrected == numeric:
		return value
	if _validation == "integer":
		return str(int(corrected))
	var result := str(corrected)
	if result.ends_with(".0"):
		result = result.trim_suffix(".0")
	if value.contains(","):
		result = result.replace(".", ",")
	return result
