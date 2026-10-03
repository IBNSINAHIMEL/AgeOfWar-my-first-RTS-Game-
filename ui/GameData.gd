extends Node

var selected_region = 0  # Default to Japanese (0)
var game_data = {}

func set_user_region(region: int):
	selected_region = region
	game_data["user_region"] = region
	print("🎮 Region saved: ", _get_region_name(region))

func get_user_region() -> int:
	return selected_region

func _get_region_name(region: int) -> String:
	match region:
		0: return "Japanese Empire"
		1: return "Mughal Empire"
		2: return "Mongol Empire"
	return "Unknown"

func set_data(data: Dictionary):
	game_data = data

func get_data() -> Dictionary:
	return game_data

func get_enemy_regions() -> Array:
	return game_data.get("enemy_regions", [])

func get_difficulty() -> String:
	return game_data.get("difficulty", "vs_first")
