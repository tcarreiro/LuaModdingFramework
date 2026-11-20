@tool
class_name UIStyleDefinition extends RefCounted

var id: String
var parent: String = ""
var owner_mod_id: String = ""
var exposed_to_mods: bool = true

var layout: Dictionary = {}
var styleboxes: Dictionary = {}
var colors: Dictionary = {}
var font_sizes: Dictionary = {}
var fonts: Dictionary = {}
var states: Dictionary = {}
var transition: Dictionary = {}
var visual: Dictionary = {}
var sounds: Dictionary = {}
var state_styleboxes: Dictionary = {}

var mod_overrides: Array[String] = []

func copy() -> UIStyleDefinition:
	var result := UIStyleDefinition.new()
	result.id = id
	result.parent = parent
	result.owner_mod_id = owner_mod_id
	result.exposed_to_mods = exposed_to_mods
	result.mod_overrides = mod_overrides.duplicate()
	
	result.layout = layout.duplicate(true)
	result.colors = colors.duplicate(true)
	result.font_sizes = font_sizes.duplicate(true)
	result.fonts = fonts.duplicate()
	
	for name in styleboxes:
		var box := styleboxes[name] as StyleBox
		result.styleboxes[name] = box.duplicate(true) if box != null else null
	
	result.states = states.duplicate(true)
	result.transition = transition.duplicate(true)
	result.visual = visual.duplicate(true)
	result.sounds = sounds.duplicate()
	
	for state_name in state_styleboxes:
		result.state_styleboxes[state_name] = state_styleboxes[state_name].duplicate(true)
	
	return result
