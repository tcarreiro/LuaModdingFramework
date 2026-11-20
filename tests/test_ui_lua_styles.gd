extends GutTest

var styles: UIStyleRegistry
var components: UIComponentRegistry
var state: ContentState


func before_each() -> void:
	styles = UIStyleRegistry.new()
	components = UIComponentRegistry.new()
	components.style_registry = styles
	state = ContentState.new(ContentTypeRegistry.new(), components)
	state.start()


func after_each() -> void:
	state.close()


func test_core_can_define_private_style_from_lua() -> void:
	assert_true(state.execute('''
		assert(UI.define_style("core:action", {
			background_color = "#AA3344",
			border_width = 2,
			border_radius = 8,
			padding = 12,
			font_color = "#FFFFFF",
			states = {
				hover = { background_color = "#CC4455", scale = {x = 1.02, y = 1.02} },
				pressed = { background_color = "#882233" }
			},
			transition_property = {"background_color", "scale"},
			transition_duration = 0.15
		}))
	''', "core"), str(state.get_errors()))
	assert_true(styles.has_style("core:action"))
	assert_false(styles.get_style("core:action").exposed_to_mods)
	assert_true(styles.finalize(), str(styles.errors))
	var prepared := styles.prepare_instance("core:action", {}, true)
	assert_not_null(prepared)
	if prepared != null:
		assert_eq(prepared.visual["background_color"], Color("#AA3344"))
		assert_eq(prepared.states["hover"]["scale"], Vector2(1.02, 1.02))
	assert_null(styles.prepare_instance("core:action", {}, false))


func test_mod_cannot_define_styles_by_default() -> void:
	assert_false(state.execute('UI.define_style("other:test", { background_color = "#FFFFFF" })', "other"))
	assert_false(styles.has_style("other:test"))


func test_owner_namespace_is_required() -> void:
	assert_false(state.execute('UI.define_style("other:test", {})', "core"))
	assert_false(styles.has_style("other:test"))


func test_consumer_can_enable_selected_mods() -> void:
	state.close()
	state = ContentState.new(ContentTypeRegistry.new(), components, ["core", "demo"])
	state.start()
	assert_true(state.execute('''
		assert(UI.define_style("demo:highlight", {
			background_color = "#102030",
			exposed_to_mods = true,
			stretch_x = "expand_fill"
		}))
	''', "demo"), str(state.get_errors()))
	assert_true(styles.finalize(), str(styles.errors))
	assert_not_null(styles.prepare_instance("demo:highlight", {}, false))


func test_invalid_styles_are_rejected() -> void:
	assert_false(state.execute('UI.define_style("core:bad", { strange_key = 5 })', "core"))
	assert_false(styles.has_style("core:bad"))
