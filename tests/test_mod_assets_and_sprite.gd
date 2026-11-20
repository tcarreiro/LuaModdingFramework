extends GutTest

const TEST_ROOT := "user://gut_mod_asset_test"
const TEST_IMAGE := TEST_ROOT + "/assets/ui/sheet.png"

var assets: ModAssetRegistry

func before_each() -> void:
	assets = ModAssetRegistry.new()
	var directory := TEST_ROOT.path_join("assets/ui")
	assert_eq(DirAccess.make_dir_recursive_absolute(directory), OK)

	var image := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color("#d6a965"))

	assert_eq(image.save_png(TEST_IMAGE), OK)

	var manifest := ModManifest.new()
	manifest.id = "test_assets"
	manifest.root_path = TEST_ROOT

	var mods: Array[ModManifest] = [manifest]
	assets.configure(mods)


func after_each() -> void:
	assets.clear()
	DirAccess.remove_absolute(TEST_IMAGE)
	DirAccess.remove_absolute(TEST_ROOT.path_join("assets/ui"))
	DirAccess.remove_absolute(TEST_ROOT.path_join("assets"))
	DirAccess.remove_absolute(TEST_ROOT)


func test_texture_is_loaded_by_asset_id() -> void:
	var texture := assets.get_texture("test_assets:ui/sheet.png")

	assert_not_null(texture, str(assets.errors))
	assert_eq(texture.get_size(), Vector2(64, 32))


func test_texture_is_cached() -> void:
	var first := assets.get_texture("test_assets:ui/sheet.png")
	var second := assets.get_texture("test_assets:ui/sheet.png")

	assert_not_null(first)
	assert_same(first, second)


func test_invalid_relative_path_is_rejected() -> void:
	var texture := assets.get_texture("test_assets:../outside.png")

	assert_null(texture)
	assert_false(assets.errors.is_empty())


func test_unknown_mod_asset_is_rejected() -> void:
	var texture := assets.get_texture("missing:ui/sheet.png")

	assert_null(texture)
	assert_false(assets.errors.is_empty())


func test_sprite_sheet_selects_correct_frame() -> void:
	var sprite := UIComponentSprite.new()

	sprite.configure({
		"texture": "test_assets:ui/sheet.png",
		"hframes": 4,
		"vframes": 2,
		"frame_count": 8,
		"frame": 0,
		"playing": false,
	}, Callable(assets, "get_texture"))

	var atlas := sprite.texture as AtlasTexture

	assert_not_null(atlas)
	assert_eq(atlas.region.size, Vector2(16, 16))
	assert_eq(sprite.custom_minimum_size, Vector2.ZERO)

	sprite.set_frame(5)

	assert_eq(atlas.region.position, Vector2(16, 16))

	sprite.free()


func test_sprite_does_not_define_minimum_size_by_default() -> void:
	var sprite := UIComponentSprite.new()

	sprite.configure({
		"texture": "test_assets:ui/sheet.png",
		"hframes": 4,
		"vframes": 2,
		"playing": false
	}, Callable(assets, "get_texture"))

	assert_eq(sprite.custom_minimum_size, Vector2.ZERO)

	sprite.free()


func test_sprite_emits_frame_changed() -> void:
	var sprite := UIComponentSprite.new()

	sprite.configure({
		"texture": "test_assets:ui/sheet.png",
		"hframes": 4,
		"vframes": 2,
		"playing": false
	}, Callable(assets, "get_texture"))

	var received: Array[int] = []

	sprite.frame_changed.connect(func(frame: int):
		received.append(frame)
	)

	sprite.set_frame(3)

	assert_eq(received, [3])

	sprite.free()


func test_sprite_stops_after_non_looping_animation() -> void:
	var sprite := UIComponentSprite.new()

	sprite.configure({
		"texture": "test_assets:ui/sheet.png",
		"hframes": 4,
		"vframes": 2,
		"frame_count": 8,
		"fps": 8.0,
		"loop": false,
		"playing": false
	}, Callable(assets, "get_texture"))

	var completed := [false]

	sprite.finished.connect(func():
		completed[0] = true
	)

	sprite.play()
	sprite._process(1.1)

	assert_true(completed[0])
	assert_false(sprite.is_processing())

	sprite.free()


func test_style_compiler_uses_mod_texture() -> void:
	var compiler := UIStyleBoxCompiler.new()
	compiler.texture_resolver = Callable(assets, "get_texture")

	var box := compiler.compile({
		"background_image": "test_assets:ui/sheet.png",
		"background_image_slice": 4,
		"padding": 8
	})

	assert_not_null(box, str(compiler.errors))
	assert_true(box is StyleBoxTexture)

	var texture_box := box as StyleBoxTexture

	assert_eq(texture_box.texture.get_size(), Vector2(64, 32))
	assert_eq(texture_box.texture_margin_left, 4.0)
	assert_eq(texture_box.content_margin_left, 8.0)
