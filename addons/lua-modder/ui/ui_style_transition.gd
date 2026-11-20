class_name UIStyleTransition extends RefCounted

const VISUAL_STATES := ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]
const BUTTON_BOXES := ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]
const FONT_COLORS := [
	"font_color", "font_hover_color", "font_pressed_color",
	"font_hover_pressed_color", "font_disabled_color"
]

const FONT_BY_STATE := {
	"normal": "font_color",
	"hover": "font_hover_color",
	"pressed": "font_pressed_color",
	"hover_pressed": "font_hover_pressed_color",
	"disabled": "font_disabled_color",
	"focus": "font_color"
}

var control: Control
var _box_control: Control
var style: UIStyleDefinition
var current_state := "normal"

var _tween: Tween
var _generation := 0
var _from: Dictionary = {}
var _to: Dictionary = {}

var _base_scale := Vector2.ONE
var _base_opacity := 1.0

var _original_boxes: Dictionary = {}
var _original_font_overrides: Dictionary = {}
var _font_palette: Dictionary = {}

var _live_box: StyleBox
var _live_font := Color.WHITE
var _font_active := false


func setup(target: Control, prepared_style: UIStyleDefinition, visual_target: Control = null) -> void:
	control = target
	_box_control = visual_target if visual_target != null else target
	style = prepared_style
	_base_scale = _read_scale()
	_base_opacity = control.modulate.a
	_remember_theme()
	_connect_signals()
	current_state = _detect_state()
	_apply_non_button_state_box(current_state)
	_apply_scalar_values(_target_values(current_state), [])


func is_animating() -> bool:
	return _tween != null and _tween.is_running()


func refresh() -> void:
	if control == null or not is_instance_valid(control):
		return
	set_state(_detect_state())


func set_state(next_state: String) -> void:
	if control == null or not is_instance_valid(control):
		return

	if next_state not in VISUAL_STATES or next_state == current_state:
		return

	var previous := current_state
	var source := _current_values(previous)
	var destination := _target_values(next_state)

	_stop_tween()
	_restore_theme()
	current_state = next_state
	_apply_non_button_state_box(current_state)
	
	var config := style.transition
	var duration := float(config.get("duration", 0.0))
	var properties: Array = config.get("properties", [])

	if not control.is_inside_tree() or duration <= 0.0 or properties.is_empty():
		_apply_scalar_values(destination, [])
		return

	_from.clear()
	_to.clear()

	for property_name in properties:
		if not source.has(property_name) or not destination.has(property_name):
			continue

		if source[property_name] == destination[property_name]:
			continue

		match property_name:
			"background_color":
				if not _prepare_background(previous, next_state, source[property_name]):
					continue
			"font_color":
				_install_live_font(source[property_name])

		_from[property_name] = source[property_name]
		_to[property_name] = destination[property_name]

	_apply_scalar_values(destination, _from.keys())

	if _from.is_empty():
		_restore_theme()
		return

	_start_tween(duration, config)


func _start_tween(duration: float, config: Dictionary) -> void:
	_generation += 1
	var generation := _generation

	_tween = control.create_tween()
	_tween.set_trans(config.get("trans", Tween.TRANS_SINE))
	_tween.set_ease(config.get("ease", Tween.EASE_OUT))

	var iterations: int = config.get("iterations", 1)

	for index in range(iterations):
		var step := _tween.tween_method(_apply_progress, 0.0, 1.0, duration)
		if index == 0:
			step.set_delay(float(config.get("delay", 0.0)))

		if index < iterations - 1:
			_tween.tween_method(_apply_progress, 1.0, 0.0, duration)

	_tween.finished.connect(_on_finished.bind(generation))



func _apply_progress(weight: float) -> void:
	if control == null or not is_instance_valid(control):
		return
	for property_name in _from:
		var start: Variant = _from[property_name]
		var finish: Variant = _to[property_name]
		match property_name:
			"background_color":
				var color := start as Color
				_set_background(_live_box, color.lerp(finish, weight))
			"font_color":
				var color := start as Color
				_apply_live_font(color.lerp(finish, weight))
			"opacity":
				var color := control.modulate
				color.a = lerpf(float(start), float(finish), weight)
				control.modulate = color
			"scale":
				var scale := start as Vector2
				_write_scale(scale.lerp(finish, weight))


func _on_finished(generation: int) -> void:
	if generation != _generation:
		return

	_apply_progress(1.0)
	_restore_theme()
	_tween = null


func _stop_tween() -> void:
	_generation += 1

	if _tween != null and _tween.is_valid():
		_tween.kill()

	_tween = null


#region State resolution

func _detect_state() -> String:
	if control is BaseButton:
		var button := control as BaseButton

		match button.get_draw_mode():
			BaseButton.DRAW_DISABLED:
				return "disabled"
			BaseButton.DRAW_HOVER_PRESSED:
				return "hover_pressed"
			BaseButton.DRAW_PRESSED:
				return "pressed"
			BaseButton.DRAW_HOVER:
				return "hover"

		if button.has_focus():
			return "focus"

		return "normal"

	if control.has_focus():
		return "focus"

	if control.is_inside_tree() \
			and Rect2(Vector2.ZERO, control.size).has_point(control.get_local_mouse_position()):
		return "hover"

	return "normal"


func _target_values(state_name: String) -> Dictionary:
	var normal: Dictionary = style.states.get("normal", {})
	var current: Dictionary = style.states.get(state_name, {})
	var result := {
		"opacity": current.get("opacity", normal.get("opacity", _base_opacity)),
		"scale": current.get("scale", normal.get("scale", _base_scale)),
		"font_color": current.get("font_color", normal.get("font_color",
					_font_palette.get(FONT_BY_STATE[state_name], Color.WHITE))
		)
	}
	var box := _box_for_state(state_name)
	if box != null:
		var background := _background(box)
		if background != null:
			result["background_color"] = background
	return result


func _current_values(state_name: String) -> Dictionary:
	var result := {
		"opacity": control.modulate.a,
		"scale": _read_scale(),
		"font_color": _live_font if _font_active else _font_palette.get(
			FONT_BY_STATE[state_name], Color.WHITE
		)
	}
	var box := _live_box if _live_box != null else _box_for_state(state_name)
	if box != null:
		var background := _background(box)
		if background != null:
			result["background_color"] = background
	return result


func _apply_scalar_values(values: Dictionary, excluded: Array) -> void:
	if "opacity" not in excluded and _has_state_transform("opacity"):
		var color := control.modulate
		color.a = float(values["opacity"])
		control.modulate = color
	if "scale" not in excluded and _has_state_transform("scale"):
		_write_scale(values["scale"])
	if "font_color" not in excluded:
		var active_state: Dictionary = style.states.get(current_state, {})
		if active_state.has("font_color"):
			_apply_live_font(values["font_color"])


func _has_state_transform(name: String) -> bool:
	for state_values in style.states.values():
		if (state_values as Dictionary).has(name):
			return true
	return false


func _apply_non_button_state_box(state_name: String) -> void:
	if _box_control is BaseButton:
		return
	var box_name := UIStyleApplier.native_stylebox_slot(_box_control)
	if box_name.is_empty():
		return
	var box := _box_for_state(state_name)
	if box == null:
		return
	_box_control.add_theme_stylebox_override(box_name, box)
	_original_boxes[box_name] = box
#endregion


#region Background transition
func _box_for_state(state_name: String) -> StyleBox:
	if _box_control is BaseButton:
		var key := state_name
		if key == "focus" and not style.styleboxes.has("focus"):
			key = "normal"
		elif key == "hover_pressed" and not style.styleboxes.has(key):
			key = "pressed"
		return style.styleboxes.get(
			key, style.styleboxes.get("normal")
		) as StyleBox
	var slot := UIStyleApplier.native_stylebox_slot(_box_control)
	if not slot.is_empty():
		var fallback := "normal" if slot == &"normal" else "panel"
		return style.state_styleboxes.get(state_name,
			style.styleboxes.get(fallback, style.styleboxes.get("normal"))) as StyleBox
	return null


func _background(box: StyleBox) -> Variant:
	if box is StyleBoxFlat:
		return (box as StyleBoxFlat).bg_color
	if box is StyleBoxTexture:
		return (box as StyleBoxTexture).modulate_color
	return null


func _set_background(box: StyleBox, color: Color) -> void:
	if box is StyleBoxFlat:
		(box as StyleBoxFlat).bg_color = color
	elif box is StyleBoxTexture:
		(box as StyleBoxTexture).modulate_color = color


func _prepare_background(previous: String, next_state: String, start_color: Color) -> bool:
	var before := _box_for_state(previous)
	var target := _box_for_state(next_state)
	if before == null or target == null or before.get_class() != target.get_class():
		return false
	
	if not target is StyleBoxFlat and not target is StyleBoxTexture:
		return false
	
	_live_box = target.duplicate(true)
	var installed: StyleBox = _original_boxes.get(next_state) as StyleBox
	if installed == null and _box_control is BaseButton:
		installed = _original_boxes.get("normal") as StyleBox
	if installed != null:
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			_live_box.set_content_margin(side, installed.get_content_margin(side))
	_set_background(_live_box, start_color)
	for name in _box_names():
		_box_control.add_theme_stylebox_override(StringName(name), _live_box)
	return true


func _box_names() -> Array:
	if _box_control is BaseButton:
		return BUTTON_BOXES
	var slot := UIStyleApplier.native_stylebox_slot(_box_control)
	return [slot] if not slot.is_empty() else []
#endregion


#region Font transition

func _install_live_font(color: Color) -> void:
	_font_active = true
	_apply_live_font(color)


func _apply_live_font(color: Color) -> void:
	_live_font = color

	var names := FONT_COLORS if control is Button else ["font_color"]

	for name in names:
		control.add_theme_color_override(StringName(name), color)

#endregion


#region Theme preservation
func _remember_theme() -> void:
	for name in _box_names():
		_original_boxes[name] = _box_control.get_theme_stylebox(name) \
			if _box_control.has_theme_stylebox_override(name) else null

	var names := FONT_COLORS if control is Button else ["font_color"]

	for name in names:
		_original_font_overrides[name] = control.get_theme_color(name) \
			if control.has_theme_color_override(name) else null
		_font_palette[name] = control.get_theme_color(name)


func _uses_visual_scale() -> bool:
	return style != null and style.layout.get(
		"scale_mode", "transform"
	) == "visual_only"


func _read_scale() -> Vector2:
	if _uses_visual_scale():
		return control.offset_transform_scale

	return control.scale


func _write_scale(value: Vector2) -> void:
	if _uses_visual_scale():
		control.offset_transform_scale = value
	else:
		control.scale = value


func _restore_theme() -> void:
	if _live_box != null:
		for name in _box_names():
			var original: StyleBox = _original_boxes[name]
			if original != null:
				_box_control.add_theme_stylebox_override(StringName(name), original)
			else:
				_box_control.remove_theme_stylebox_override(StringName(name))

		_live_box = null

	if _font_active:
		var names := FONT_COLORS if control is Button else ["font_color"]

		for name in names:
			var original: Variant = _original_font_overrides[name]
			if original == null:
				control.remove_theme_color_override(StringName(name))
			else:
				control.add_theme_color_override(StringName(name), original)

		_font_active = false
#endregion


#region Signals
func _connect_signals() -> void:
	control.mouse_entered.connect(refresh)
	control.mouse_exited.connect(refresh)
	control.focus_entered.connect(refresh)
	control.focus_exited.connect(refresh)

	if control is BaseButton:
		var button := control as BaseButton
		button.button_down.connect(refresh)
		button.button_up.connect(refresh)
		button.toggled.connect(_on_toggled)


func _on_toggled(_value: bool) -> void:
	refresh()
#endregion
