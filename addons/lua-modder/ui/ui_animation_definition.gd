@tool
class_name UIAnimationDefinition extends RefCounted

var id: String
var owner_mod_id: String = ""
var exposed_to_mods: bool = true

var duration: float = 1.0
var trans: Tween.TransitionType = Tween.TRANS_LINEAR
var ease: Tween.EaseType = Tween.EASE_IN_OUT
# >0 or "infinite"
var iterations: Variant = 1
var keyframes: Array[Dictionary] = []
var compiled_tracks: Dictionary = {}

func copy() -> UIAnimationDefinition:
	var result := UIAnimationDefinition.new()
	result.id = id
	result.owner_mod_id = owner_mod_id
	result.exposed_to_mods = exposed_to_mods
	result.duration = duration
	result.trans = trans
	result.ease = ease
	result.iterations = iterations
	result.keyframes = keyframes.duplicate(true)
	result.compiled_tracks = compiled_tracks.duplicate(true)
	return result
