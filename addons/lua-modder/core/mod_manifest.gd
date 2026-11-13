@tool
class_name ModManifest extends RefCounted

var id: String
var display_name: String
var description: String
var version: String
var game_version: String
var author: String
var root_path: String
var dependencies: Array[ModDependency] = []
