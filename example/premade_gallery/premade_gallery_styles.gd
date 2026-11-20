class_name PremadeGalleryStyles extends RefCounted

static func register(styles: UIStyleRegistry) -> bool:
	var heading := UIStyleDefinition.new()
	heading.id = "gallery:heading"
	heading.font_sizes = {"font_size": 28}
	heading.colors = {"font_color": Color("#EDF5FF")}
	
	var subtitle := UIStyleDefinition.new()
	subtitle.id = "gallery:subtitle"
	subtitle.font_sizes = {"font_size": 14}
	subtitle.colors = {"font_color": Color("#A8B8CE")}

	var card := UIStyleDefinition.new()
	card.id = "gallery:card"
	card.visual = {
		"background_image": "gallery:ui/frame.png",
		"background_image_slice": 12,
		"padding": 18,
	}

	var hover_label := UIStyleDefinition.new()
	hover_label.id = "gallery:hover-label"
	hover_label.font_sizes = {"font_size": 19}
	hover_label.colors = {"font_color": Color("#E6F0FF")}
	hover_label.layout = {
		"stretch_x": "start",
		"scale_mode": "visual_only",
		"pivot_ratio": Vector2(0.5, 0.5)
	}
	hover_label.states = {
		"hover": {"scale": Vector2(1.08, 1.08)}
	}
	hover_label.transition = {
		"properties": ["scale"],
		"duration": 0.15
	}

	var grid := UIStyleDefinition.new()
	grid.id = "gallery:grid"
	grid.layout = {"gap": 10}

	var stack := UIStyleDefinition.new()
	stack.id = "gallery:stack"
	stack.layout = {"gap": 12}

	var scroll := UIStyleDefinition.new()
	scroll.id = "gallery:scroll"
	scroll.layout = {
		"min_size": Vector2(0, 160),
		"gap": 8,
		"padding": 12
	}

	var sprite := UIStyleDefinition.new()
	sprite.id = "gallery:sprite"
	sprite.layout = {"min_size": Vector2(96, 96)}

	var text_input := UIStyleDefinition.new()
	text_input.id = "gallery:text-input"
	text_input.visual = {
		"background_color": Color("#1B2638"),
		"border_color": Color("#6487AA"),
		"border_width": 1,
		"border_radius": 6,
		"padding": 10
	}
	text_input.colors = {
		"font_color": Color.WHITE,
		"font_placeholder_color": Color("#A0B4CA")
	}
	text_input.layout = {"min_size": Vector2(250, 0)}
	
	var hover_div := UIStyleDefinition.new()
	hover_div.id = "gallery:hover-div"
	hover_div.visual = {
		"background_color": Color("#263C54"),
		"border_color": Color("#587899"),
		"border_width": 1,
		"border_radius": 8,
		"padding": 14
	}
	hover_div.states = {
		"hover": {
			"background_color": Color("#466B89")
		}
	}
	hover_div.transition = {
		"properties": ["background_color"],
		"duration": 0.15
	}

	for style in [
		heading, subtitle, card, hover_label,
		grid, stack, scroll, sprite, text_input,
		hover_div
	]:
		if not styles.register_style(style):
			push_error(str(styles.errors))
			return false

	return true
