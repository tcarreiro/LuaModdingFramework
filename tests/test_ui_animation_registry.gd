extends GutTest

var registry: UIAnimationRegistry


func before_each() -> void:
	registry = UIAnimationRegistry.new()


func _animation() -> UIAnimationDefinition:
	var animation := UIAnimationDefinition.new()
	animation.id = "core:appear"
	animation.duration = 0.12
	animation.trans = Tween.TRANS_LINEAR
	animation.ease = Tween.EASE_IN_OUT

	animation.keyframes = [
		{
			"time": 0.0,
			"values": {
				"opacity": 0.0,
				"scale": Vector2(0.8, 0.8)
			}
		},
		{
			"time": 0.5,
			"values": {
				"scale": Vector2(1.1, 1.1)
			}
		},
		{
			"time": 1.0,
			"values": {
				"opacity": 1.0,
				"scale": Vector2.ONE
			}
		}
	]

	return animation


func _prepare() -> void:
	assert_true(registry.register_animation(_animation()))
	assert_true(registry.finalize())


func _player(control: Control, trusted: bool = true) -> UIAnimationPlayer:
	var player := UIAnimationPlayer.new()
	player.setup(registry, control, trusted)
	return player


func test_keyframes_are_compiled_into_independent_tracks() -> void:
	_prepare()

	var compiled := registry._get_compiled("core:appear", true)

	assert_not_null(compiled)
	assert_eq(compiled.compiled_tracks.size(), 2)
	assert_eq(compiled.compiled_tracks["opacity"]["frames"].size(), 2)
	assert_eq(compiled.compiled_tracks["scale"]["frames"].size(), 3)
	assert_eq(compiled.compiled_tracks["opacity"]["path"], NodePath("modulate:a"))


func test_animation_definition_is_copied_on_registration() -> void:
	var definition := _animation()

	assert_true(registry.register_animation(definition))

	definition.keyframes[0]["values"]["opacity"] = 0.9

	assert_true(registry.finalize())

	var compiled := registry._get_compiled("core:appear", true)
	assert_eq(compiled.compiled_tracks["opacity"]["frames"][0]["value"], 0.0)


func test_registry_rejects_new_definitions_after_finalization() -> void:
	_prepare()

	var another := _animation()
	another.id = "core:another"

	assert_false(registry.register_animation(another))
	assert_false(registry.has_animation("core:another"))


func test_invalid_animation_channel_is_rejected() -> void:
	var definition := _animation()
	definition.keyframes[0]["values"]["unknown"] = 10

	assert_true(registry.register_animation(definition))
	assert_false(registry.finalize())


func test_missing_endpoint_is_rejected() -> void:
	var definition := _animation()
	definition.keyframes[0]["time"] = 0.2

	assert_true(registry.register_animation(definition))
	assert_false(registry.finalize())


func test_duplicate_keyframe_time_is_rejected() -> void:
	var definition := _animation()
	definition.keyframes[1]["time"] = 0.0

	assert_true(registry.register_animation(definition))
	assert_false(registry.finalize())


func test_animation_applies_initial_and_final_values() -> void:
	_prepare()

	var control := Control.new()
	add_child(control)

	var player := _player(control)

	assert_true(player.play("core:appear"), str(player.errors))
	assert_eq(control.modulate.a, 0.0)
	assert_eq(control.scale, Vector2(0.8, 0.8))

	await get_tree().create_timer(0.20).timeout

	assert_false(player.is_playing())
	assert_true(is_equal_approx(control.modulate.a, 1.0))
	assert_true(control.scale.is_equal_approx(Vector2.ONE))

	control.free()


func test_infinite_animation_can_be_interrupted() -> void:
	var definition := _animation()
	definition.iterations = "infinite"

	assert_true(registry.register_animation(definition))
	assert_true(registry.finalize())

	var control := Control.new()
	add_child(control)

	var player := _player(control)

	assert_true(player.play("core:appear"), str(player.errors))
	assert_true(player.is_playing())
	assert_eq(player._tween.get_loops_left(), -1)

	player.stop()

	assert_false(player.is_playing())
	assert_eq(player.current_animation, "")

	control.free()


func test_animation_instances_are_independent() -> void:
	_prepare()

	var first := Control.new()
	var second := Control.new()

	add_child(first)
	add_child(second)

	var first_player := _player(first)

	assert_true(first_player.play("core:appear"), str(first_player.errors))

	assert_eq(first.modulate.a, 0.0)
	assert_eq(second.modulate.a, 1.0)
	assert_eq(second.scale, Vector2.ONE)

	first_player.stop()

	assert_false(first_player.is_playing())
	assert_eq(second.modulate.a, 1.0)

	first.free()
	second.free()


func test_private_animation_is_not_available_to_mods() -> void:
	var definition := _animation()
	definition.exposed_to_mods = false

	assert_true(registry.register_animation(definition))
	assert_true(registry.finalize())

	var control := Control.new()
	add_child(control)

	var player := _player(control, false)

	assert_false(player.play("core:appear"))
	assert_false(player.errors.is_empty())

	control.free()


func test_component_can_execute_registered_animation() -> void:
	_prepare()

	var components := UIComponentRegistry.new()
	components.animation_registry = registry

	var button := Button.new()
	var scene := PackedScene.new()
	assert_eq(scene.pack(button), OK)
	button.free()

	var definition := UIComponentDefinition.from_scene(
		"core:button",
		scene,
		func(_control: Control, _values: Dictionary) -> void: pass
	)

	assert_true(components.register_scene(definition))
	assert_true(components.finalize())

	var instance := components.instantiate_component("core:button")
	assert_not_null(instance)

	add_child(instance.root)

	assert_true(instance.play_animation("core:appear"))
	assert_not_null(instance.animation)
	assert_true(instance.animation.is_playing())

	instance.stop_animation()

	assert_false(instance.animation.is_playing())

	instance.root.free()
