Content.extend({
	{
		type = "loot",
		id = "demo_a_datashard",
		max_stack = 5,
		weight = 0.25
	}
})

table.insert(
	Content.raw["item-container"].starter_chest.initial_items,
	{
		item_id = "demo_a_datashard",
		amount = 2
	}
)
