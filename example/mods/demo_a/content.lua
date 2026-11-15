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

Content.extend({
	{
		type = "gauntlet",
		id = "training_gauntlet",
		max_stack = 1,
		weight = 4.0,
		armor = 3,
		socket_count = 2,
		material_id = "iron_gauntlet",
		attached_items = {
			{
				item_id = "bronze_gauntlet",
				amount = 1
			}
		}
	},
	{
		type = "card",
		id = "quick_guard",
		max_stack = 1,
		weight = 0.1,
		energy_cost = 2
	}
})

table.insert(
	Content.raw["item-container"].starter_chest.initial_items,
	{
		item_id = "training_gauntlet",
		amount = 1
	}
)
