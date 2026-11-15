extends GutTest


func test_required_dependency() -> void:
	var dependency := ModDependency.parse("demo_a")

	assert_not_null(dependency)
	if dependency == null:
		return

	assert_eq(dependency.id, "demo_a")
	assert_eq(dependency.type, ModDependency.Type.REQUIRED)
	assert_true(dependency.is_required())
	assert_true(dependency.affects_load_order())


func test_optional_dependency() -> void:
	var dependency := ModDependency.parse("? demo_a >= 1.2.0")

	assert_not_null(dependency)
	if dependency == null:
		return

	assert_eq(dependency.id, "demo_a")
	assert_eq(dependency.type, ModDependency.Type.OPTIONAL)
	assert_eq(dependency.operator, ">=")
	assert_eq(dependency.version, "1.2.0")
	assert_false(dependency.is_required())


func test_all_dependency_prefixes() -> void:
	var cases := [
		{"raw": "demo_a", "type": ModDependency.Type.REQUIRED},
		{"raw": "? demo_a", "type": ModDependency.Type.OPTIONAL},
		{"raw": "+ demo_a", "type": ModDependency.Type.RECOMMENDED},
		{"raw": "(?) demo_a", "type": ModDependency.Type.HIDDEN_OPTIONAL},
		{"raw": "! demo_a", "type": ModDependency.Type.INCOMPATIBLE},
		{"raw": "~ demo_a", "type": ModDependency.Type.NO_ORDER}
	]

	for entry in cases:
		var dependency := ModDependency.parse(entry["raw"])
		assert_not_null(dependency, "Failed to parse: %s" % entry["raw"])

		if dependency == null:
			continue

		assert_eq(dependency.type, entry["type"])
		assert_eq(dependency.id, "demo_a")


func test_dependency_ordering_rules() -> void:
	var optional := ModDependency.parse("? demo_a")
	var no_order := ModDependency.parse("~ demo_a")
	var incompatible := ModDependency.parse("! demo_a")

	assert_true(optional.affects_load_order())
	assert_false(no_order.affects_load_order())
	assert_false(incompatible.affects_load_order())
	assert_true(no_order.is_required())


func test_incompatible_dependency_ignores_version() -> void:
	var dependency := ModDependency.parse("! demo_a >= 2.0.0")

	assert_not_null(dependency)
	if dependency == null:
		return

	assert_eq(dependency.type, ModDependency.Type.INCOMPATIBLE)
	assert_eq(dependency.operator, "")
	assert_eq(dependency.version, "")


func test_invalid_dependencies() -> void:
	assert_null(ModDependency.parse(""))
	assert_null(ModDependency.parse("?"))
	assert_null(ModDependency.parse("invalid mod name"))
	assert_null(ModDependency.parse("demo_a >= invalid"))
	assert_null(ModDependency.parse("demo_a >= 1.2"))
	assert_null(ModDependency.parse("demo_a >= 1.2.65536"))
