extends GutTest

const CATALOG_SCRIPT := preload("res://example/consumer/consumer_catalog.gd")
const STORE_SCRIPT := preload("res://example/consumer/consumer_store.gd")


func test_consumer_registers_lua_pages_and_styles() -> void:
	var catalog := CATALOG_SCRIPT.new() as ConsumerCatalog
	assert_true(catalog.initialize(), str(catalog.errors))
	if not catalog.errors.is_empty():
		return
	assert_true(catalog.components.has_component("core:main-menu"))
	assert_true(catalog.components.has_component("core:save-card"))
	assert_true(catalog.components.has_component("core:inventory-panel"))
	assert_true(catalog.styles.has_style("core:trash"))
	assert_true(catalog.styles.has_style("core:button-gold"))
	assert_false(catalog.styles.get_style("core:button-gold").exposed_to_mods)


func test_required_mod_is_added_by_real_mod_manager() -> void:
	var catalog := CATALOG_SCRIPT.new() as ConsumerCatalog
	assert_true(catalog.initialize(), str(catalog.errors))
	if not catalog.errors.is_empty():
		return
	var resolved := catalog.resolve(["relics"])
	var ids: Array[String] = []
	for manifest in resolved:
		ids.append(manifest.id)
	assert_true(ids.has("core"))
	assert_true(ids.has("ambient"))
	assert_true(ids.has("relics"))


func test_settings_keep_their_original_owner() -> void:
	var catalog := CATALOG_SCRIPT.new() as ConsumerCatalog
	assert_true(catalog.initialize(), str(catalog.errors))
	if not catalog.errors.is_empty():
		return
	var registry := catalog.settings_for(["relics"])
	assert_not_null(registry, str(catalog.errors))
	if registry == null:
		return
	var core_equipment := registry.get_setting("core:starting_equipment")
	assert_not_null(core_equipment)
	if core_equipment != null:
		assert_eq(core_equipment.owner_mod_id, "core")
	var difficulty := registry.get_setting("core:difficulty")
	assert_not_null(difficulty)
	if difficulty != null:
		assert_eq(difficulty.owner_mod_id, "core")
		assert_true(difficulty.allowed_values.has("Extremo"))
	var weather := registry.get_setting("ambient:weather")
	assert_not_null(weather)
	if weather != null:
		assert_eq(weather.owner_mod_id, "ambient")


func test_mock_options_emit_reactive_changes() -> void:
	var store := STORE_SCRIPT.new() as ConsumerStore
	var changes: Array = []
	store.changed.connect(func(section: String, key: String, value: Variant) -> void:
		changes.append([section, key, value])
	)
	store.set_option("music_volume", 42.0)
	assert_eq(store.options["music_volume"], 42.0)
	assert_eq(changes.size(), 1)
	store.set_option("music_volume", 42.0)
	assert_eq(changes.size(), 1)
	store.reset_options()
	assert_eq(store.options["music_volume"], 65.0)
	assert_eq(changes.size(), 2)
