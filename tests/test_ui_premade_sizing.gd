extends GutTest

var styles: UIStyleRegistry
var components: UIComponentRegistry


func before_each() -> void:
	styles = UIStyleRegistry.new()
	components = UIComponentRegistry.new()
	components.style_registry = styles
	var catalog := UIPremadeCatalog.new()
	assert_true(catalog.install(components, styles), str(catalog.errors))
	assert_true(styles.finalize(), str(styles.errors))
	assert_true(components.finalize(), str(components.errors))


func test_controls_with_no_intrinsic_width_expand_horizontally() -> void:
	for id in [UIBuiltinIds.SLIDER, UIBuiltinIds.PROGRESS_BAR, UIBuiltinIds.LIST, UIBuiltinIds.TREE, UIBuiltinIds.TABS, UIBuiltinIds.SCROLL]:
		var instance := components.instantiate_component(id)
		assert_not_null(instance, id)
		if instance == null:
			continue
		assert_eq(instance.root.size_flags_horizontal, Control.SIZE_EXPAND_FILL, id)
		assert_eq(instance.root.size_flags_vertical, Control.SIZE_SHRINK_BEGIN, id)
		instance.clear_callbacks()
		instance.root.free()


func test_content_sized_controls_remain_shrink_by_default() -> void:
	for id in [UIBuiltinIds.BUTTON, UIBuiltinIds.TOGGLE, UIBuiltinIds.DROPDOWN, UIBuiltinIds.TEXT_INPUT, UIBuiltinIds.SPIN_BOX, UIBuiltinIds.DIV]:
		var instance := components.instantiate_component(id)
		assert_not_null(instance, id)
		if instance == null:
			continue
		assert_eq(instance.root.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN, id)
		assert_eq(instance.root.size_flags_vertical, Control.SIZE_SHRINK_BEGIN, id)
		instance.clear_callbacks()
		instance.root.free()


func test_separator_expands_along_its_direction() -> void:
	var instance := components.instantiate_component(UIBuiltinIds.SEPARATOR, {"direction": "horizontal"})
	assert_not_null(instance)
	if instance == null:
		return
	assert_eq(instance.root.size_flags_horizontal, Control.SIZE_EXPAND_FILL)
	assert_eq(instance.root.size_flags_vertical, Control.SIZE_SHRINK_BEGIN)
	assert_true(instance.update({"direction": "vertical"}))
	assert_eq(instance.root.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN)
	assert_eq(instance.root.size_flags_vertical, Control.SIZE_EXPAND_FILL)
	instance.clear_callbacks()
	instance.root.free()


func test_label_expands_horizontally_without_vertical_stretch() -> void:
	var instance := components.instantiate_component(UIBuiltinIds.LABEL)
	assert_not_null(instance)
	if instance == null:
		return
	assert_eq(instance.root.size_flags_horizontal, Control.SIZE_EXPAND_FILL)
	assert_eq(instance.root.size_flags_vertical, Control.SIZE_SHRINK_BEGIN)
	instance.clear_callbacks()
	instance.root.free()
