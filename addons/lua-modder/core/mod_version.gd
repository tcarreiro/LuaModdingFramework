@tool
class_name ModVersion extends RefCounted


static func is_valid(version: String) -> bool:
	var parts:= version.split(".")
	if parts.size() != 3:
		return false
	for part in parts:
		if part.is_empty():
			return false
		for i in range(part.length()):
			var character := part.substr(i, 1)
			if character < "0" or character > "9":
				return false
			if int(part) > 65535:
				return false
	return true


static func compare(a: String, b: String) -> int:
	var a_parts := a.split(".")
	var b_parts := b.split(".")
	for i in range(3):
		var a_value := int(a_parts[i])
		var b_value := int(b_parts[i])
		if a_value < b_value:
			return -1
		if a_value > b_value:
			return 1
	return 0


static func satisfies(version: String, operator: String, required: String) -> bool:
	if operator.is_empty():
		return true
	
	var result := compare(version, required)
	
	match operator:
		"<":
			return result < 0
		"<=":
			return result <= 0
		"=":
			return result == 0
		">":
			return result > 0
		">=":
			return result >= 0
	
	return false


static func is_compatibility_line(version: String) -> bool:
	var parts := version.split(".")
	if parts.size() != 2:
		return false
	return is_valid(version + ".0")


static func matches_game_version(game_version: String, compatibility_line: String) -> bool:
	if not is_valid(game_version) or not is_compatibility_line(compatibility_line):
		return false
	
	var game_parts := game_version.split(".")
	var line_parts := compatibility_line.split(".")
	
	return int(game_parts[0]) == int(line_parts[0]) and int(game_parts[1]) == int(line_parts[1])
