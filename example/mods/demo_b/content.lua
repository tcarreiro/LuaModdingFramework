
assert(UI.define_component("demo_b:counter", {
	properties = {
		title = {
			type = "string",
			default = "Demo B"
		},
		button_label = {
			type = "string",
			default = "Clique"
		}
	},

	tree = {
		component = "core:playground-column",

		children = {
			{
				name = "description",
				component = "core:playground-label",
				props = {
					text = { ["$prop"] = "title" }
				}
			},
			{
				name = "action",
				component = "core:playground-button",
				props = {
					label = { ["$prop"] = "button_label" }
				}
			}
		}
	},

	events = {
		pressed = {
			source = "action",
			event = "pressed"
		}
	}
}))
