extends GutTest

var styles: UIStyleRegistry
var components: UIComponentRegistry
var premades: UIPremadeCatalog


func before_each() -> void:
	styles = UIStyleRegistry.new()
	components = UIComponentRegistry.new()
	components.style_registry = styles

	premades = UIPremadeCatalog.new()
	assert_true(premades.install(components, styles), str(premades.errors))


func _finalize_registries() -> void:
	assert_true(styles.finalize(), str(styles.errors))
	assert_true(components.finalize(), str(components.errors))


func test_modal_is_registered() -> void:
	assert_true(components.has_component("ui:modal"))
	assert_true(styles.has_style("ui:modal-default"))


func test_modal_has_no_fixed_minimum_size() -> void:
	_finalize_registries()

	var instance := components.instantiate_component("ui:modal")

	assert_not_null(instance)
	if instance == null:
		return

	assert_true(instance.content_root is UIComponentModal)
	assert_eq(instance.content_root.custom_minimum_size, Vector2.ZERO)

	instance.clear_callbacks()
	instance.root.free()


func test_modal_exposes_content_slot_and_drag_handle() -> void:
	_finalize_registries()

	var instance := components.instantiate_component("ui:modal", {
		"title": "Inventário"
	})

	assert_not_null(instance)
	if instance == null:
		return

	var modal := instance.content_root as UIComponentModal

	assert_eq(modal.get_node("Layout/Header/Title").text, "Inventário")
	assert_same(instance.get_slot(), modal.get_node("Layout/Content"))
	assert_same(instance.get_drag_target(), modal)
	assert_same(instance.get_drag_handle(), modal.get_node("Layout/Header"))

	instance.clear_callbacks()
	instance.root.free()


func test_modal_emits_close_requested() -> void:
	_finalize_registries()

	var instance := components.instantiate_component("ui:modal")

	assert_not_null(instance)
	if instance == null:
		return

	var received: Array[String] = []

	assert_true(instance.on_event(&"close_requested", func(event: Dictionary):
		received.append(event["name"])
	))

	add_child(instance.root)

	var close_button := instance.content_root.get_node(
		"Layout/Header/Close"
	) as Button

	close_button.pressed.emit()

	assert_eq(received, ["close_requested"])

	instance.clear_callbacks()
	instance.root.free()



func test_modal_window_keeps_its_own_size() -> void:
	_finalize_registries()
	var host := UIRootHost.new()
	add_child(host)
	var area := host.modal_root
	area.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	area.size = Vector2(800, 600)
	var instance := components.instantiate_component("ui:modal", {
		"title": "Baú"
	})
	assert_not_null(instance, str(components.errors))
	if instance == null:
		host.free()
		return
	var window := instance.root
	var mounted := host.mount_component(
		window,
		"modal",
		true,
		null,
		Control.MOUSE_FILTER_STOP,
		Vector2(80, 60)
	)
	assert_not_null(mounted, str(host.errors))
	if mounted != null:
		assert_same(window.get_parent(), mounted)
		if window.get_parent() == mounted:
			mounted.set_anchors_and_offsets_preset(
				Control.PRESET_TOP_LEFT
			)
			mounted.size = Vector2(800, 600)
			host._place_floating_content(
				window,
				mounted,
				Vector2(80, 60)
			)
			assert_eq(window.position, Vector2(80, 60))
			assert_eq(window.anchor_right, 0.0)
			assert_eq(window.anchor_bottom, 0.0)
			assert_lt(window.size.y, mounted.size.y)
	instance.clear_callbacks()
	host.free()
	if is_instance_valid(window):
		window.free()


func test_template_can_forward_root_modal_event() -> void:
	var definition := UIComponentDefinition.from_template(
		"demo:test-dialog",
		"demo",
		{
			"component": "ui:modal",
			"props": {
				"title": "Diálogo"
			},
			"children": [
				{
					"component": "ui:label",
					"props": {
						"text": "Conteúdo do diálogo"
					}
				}
			]
		}
	)

	definition.events = [&"close_requested"]
	definition.event_routes = {
		"close_requested": {
			"source": "$root",
			"event": "close_requested"
		}
	}

	assert_true(components.register_template(definition))
	_finalize_registries()

	var instance := components.instantiate_component("demo:test-dialog")

	assert_not_null(instance, str(components.errors))
	if instance == null:
		return

	var received: Array[String] = []

	assert_true(instance.on_event(&"close_requested", func(event: Dictionary):
		received.append(event["name"])
	))

	add_child(instance.root)

	var close_button := instance.root.get_node(
		"Layout/Header/Close"
	) as Button

	close_button.pressed.emit()

	assert_eq(received, ["close_requested"])

	instance.clear_callbacks()
	instance.root.free()
