extends GutTest


func test_mod_panel_uses_scrollable_content() -> void:
	var scene := load(
		"res://example/scenes/runtime_playground.tscn"
	) as PackedScene

	assert_not_null(scene)

	var root := scene.instantiate()
	var scroll := root.get_node(
		"OuterMargin/Body/WorkArea/ModPanel/ModMargin/ModContent/ModScroll"
	) as ScrollContainer

	assert_not_null(scroll)
	assert_eq(
		scroll.vertical_scroll_mode,
		ScrollContainer.SCROLL_MODE_AUTO
	)
	assert_eq(
		scroll.size_flags_vertical,
		Control.SIZE_EXPAND_FILL
	)

	var mod_ui := scroll.get_node("ModUIRoot") as VBoxContainer

	assert_not_null(mod_ui)

	root.free()


func test_work_area_and_panels_allow_compression() -> void:
	var scene := load(
		"res://example/scenes/runtime_playground.tscn"
	) as PackedScene

	var root := scene.instantiate()

	var work_area := root.get_node(
		"OuterMargin/Body/WorkArea"
	) as BoxContainer

	var mod_panel := work_area.get_node("ModPanel") as PanelContainer
	var log_panel := work_area.get_node("LogPanel") as PanelContainer

	assert_not_null(work_area)
	assert_eq(
		work_area.size_flags_vertical,
		Control.SIZE_EXPAND_FILL
	)

	assert_eq(mod_panel.custom_minimum_size.y, 0.0)
	assert_eq(log_panel.custom_minimum_size.y, 0.0)

	root.free()
