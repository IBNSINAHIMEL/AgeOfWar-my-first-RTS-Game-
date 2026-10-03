extends Node

# ===== AGE / GENERATION =====
enum Age { RISING = 0, DISCOVERY = 1, COLONIAL = 2, INDUSTRIAL = 3 }
var current_age: int = Age.RISING
var age_names = { 
	0: "Rising Age",
	1: "Age of Discovery", 
	2: "Colonial Age", 
	3: "Industrial Age" 
}

# ===== PLAYER REGION =====
enum Region { JAPANESE, MUGHAL, MONGOL }
var player_region: int = Region.JAPANESE
var is_game_active: bool = false

# ===== GENERATIONAL BUILDINGS TRACKING =====
var generational_buildings_built = {
	"tori_gate": false,
	"agra_fort": false,
	"porcelain_tower": false,
	"shogunate": false,
	"taj_mahal": false,
	"confunction_academy": false,
	"great_buddha": false,
}
var generations_completed: int = 0

# ===== BUILDING DEFINITIONS =====
var building_data = {
	"hometown": { "cost": {"wood": 1000}, "age_required": Age.RISING, "region_specific": true, "generational": false, "display_name": "Hometown" },
	"outpost": { "cost": {"wood": 300}, "age_required": Age.RISING, "region_specific": true, "generational": false, "display_name": "Outpost" },
	"rice_paddy": { "cost": {"wood": 300, "coin": 50}, "age_required": Age.RISING, "region_specific": false, "generational": false, "display_name": "Rice Paddy" },
	"marketplace": { "cost": {"wood": 250}, "age_required": Age.RISING, "region_specific": false, "generational": false, "display_name": "Marketplace" },
	"barracks": { "cost": {"wood": 250}, "age_required": Age.RISING, "region_specific": true, "generational": false, "display_name": "Barracks" },
	"tori_gate": { "cost": {"food": 1400, "coin": 150}, "age_required": Age.RISING, "region": Region.JAPANESE, "region_specific": true, "generational": true, "advances_to_age": Age.DISCOVERY, "generation_level": 1, "display_name": "Tori Gate" },
	"agra_fort": { "cost": {"food": 1400, "coin": 150}, "age_required": Age.RISING, "region": Region.MUGHAL, "region_specific": true, "generational": true, "advances_to_age": Age.DISCOVERY, "generation_level": 1, "display_name": "Agra Fort" },
	"porcelain_tower": { "cost": {"food": 1400, "coin": 150}, "age_required": Age.RISING, "region": Region.MONGOL, "region_specific": true, "generational": true, "advances_to_age": Age.DISCOVERY, "generation_level": 1, "display_name": "Porcelain Tower" },
	"shogunate": { "cost": {"food": 1400, "coin": 150}, "age_required": Age.DISCOVERY, "region": Region.JAPANESE, "region_specific": true, "generational": true, "advances_to_age": Age.COLONIAL, "generation_level": 2, "display_name": "Shogunate" },
	"taj_mahal": { "cost": {"food": 1400, "coin": 150}, "age_required": Age.DISCOVERY, "region": Region.MUGHAL, "region_specific": true, "generational": true, "advances_to_age": Age.COLONIAL, "generation_level": 2, "display_name": "Taj Mahal" },
	"confunction_academy": { "cost": {"food": 1400, "coin": 150}, "age_required": Age.DISCOVERY, "region": Region.MONGOL, "region_specific": true, "generational": true, "advances_to_age": Age.COLONIAL, "generation_level": 2, "display_name": "Confunction Academy" },
	"great_buddha": { "cost": {"food": 1400, "coin": 150}, "age_required": Age.COLONIAL, "region": null, "region_specific": false, "generational": true, "advances_to_age": Age.INDUSTRIAL, "generation_level": 3, "display_name": "Great Buddha" },
	"stables": { "cost": {"wood": 400}, "age_required": Age.DISCOVERY, "region_specific": false, "generational": false, "display_name": "Stables" },
	"fort": { "cost": {"wood": 450, "coin": 400}, "age_required": Age.COLONIAL, "region_specific": true, "generational": false, "display_name": "Fort" },
}

# ===== SIGNALS =====
signal resources_updated(resource_type: String, amount: int)
signal age_changed(new_age: int, generation_level: int)
signal building_unlocked(building_key: String)
signal generational_building_built(building_key: String, new_age: int)

# ===== INIT =====
func _ready():
	await get_tree().process_frame
	if has_node("/root/GameData") and GameData.has_method("get_user_region"):
		player_region = GameData.get_user_region()
		print("🧭 [DEBUG] GameManager region = ", player_region)
	else:
		print("⚠️ GameData not found, using Japanese as default")
	
	# Sync with ResourceManager
	if ResourceManager:
		ResourceManager.player_region = player_region
		# Give starting resources to player
		ResourceManager.add_resource(player_region, "food", 500)
		ResourceManager.add_resource(player_region, "wood", 500)
		ResourceManager.add_resource(player_region, "coin", 200)
	
	print("=".repeat(50))
	print("🏯 GAME MANAGER INITIALIZED")
	print("Region: ", _get_region_name(player_region))
	print("Starting Age: ", age_names[current_age])
	print("=".repeat(50))

func _get_region_name(region: int) -> String:
	match region:
		Region.JAPANESE: return "Japanese Empire"
		Region.MUGHAL: return "Mughal Empire"
		Region.MONGOL: return "Mongol Empire"
		_: return "Unknown"

# ===== RESOURCE MANAGEMENT (Delegates to ResourceManager) =====
func add_resource(type: String, amount: int):
	if ResourceManager:
		ResourceManager.add_resource(player_region, type, amount)
		emit_signal("resources_updated", type, get_resource(type))

func spend_resource(type: String, amount: int) -> bool:
	if ResourceManager:
		var success = ResourceManager.spend_resource(player_region, type, amount)
		if success:
			emit_signal("resources_updated", type, get_resource(type))
		return success
	return false

func can_afford(cost: Dictionary) -> bool:
	if ResourceManager:
		return ResourceManager.can_afford(player_region, cost)
	return false

func get_resource(type: String) -> int:
	if ResourceManager:
		return ResourceManager.get_resource(player_region, type)
	return 0

# ===== BUILDING SCENE PATHS =====
func get_building_scene_path(building_key: String) -> String:
	match building_key:
		"hometown":
			match player_region:
				Region.JAPANESE: return "res://scenes/buildings/japanese home town center.tscn"
				Region.MUGHAL: return "res://scenes/buildings/mughal empire towncenter.tscn"
				Region.MONGOL: return "res://scenes/buildings/mongol_empire_towncenter.tscn"
				_: return ""
		"outpost":
			match player_region:
				Region.JAPANESE: return "res://scenes/buildings/japanese outpost.tscn"
				Region.MUGHAL: return "res://scenes/buildings/mughal empire outpost.tscn"
				Region.MONGOL: return "res://scenes/buildings/mongolian outpost.tscn"
				_: return ""
		"barracks":
			match player_region:
				Region.JAPANESE: return "res://scenes/buildings/japanese barrack.tscn"
				Region.MUGHAL: return "res://scenes/buildings/mughal_barracks.tscn"
				Region.MONGOL: return "res://scenes/buildings/mongol empire barracks.tscn"
				_: return ""
		"fort":
			match player_region:
				Region.JAPANESE: return "res://scenes/buildings/japanese fort.tscn"
				Region.MUGHAL: return "res://scenes/buildings/mughal empire fort.tscn"
				Region.MONGOL: return "res://scenes/buildings/mongol empire fort.tscn"
				_: return ""
		"tori_gate": return "res://scenes/buildings/tori gate.tscn"
		"shogunate": return "res://scenes/buildings/shogunate.tscn"
		"agra_fort": return "res://scenes/buildings/Agra Fort.tscn"
		"taj_mahal": return "res://scenes/buildings/Taj mahal.tscn"
		"porcelain_tower": return "res://scenes/buildings/porcelian tower.tscn"
		"confunction_academy": return "res://scenes/buildings/confunction academy.tscn"
		"rice_paddy": return "res://scenes/buildings/rice paddy.tscn"
		"marketplace": return "res://scenes/buildings/marketplace.tscn"
		"stables": return "res://scenes/buildings/stables.tscn"
		"great_buddha": return "res://scenes/buildings/great buddha.tscn"
		_: return ""

func get_building_scene_path_for_region(building_key: String, region: int) -> String:
	match building_key:
		"hometown":
			match region:
				Region.JAPANESE: return "res://scenes/buildings/japanese home town center.tscn"
				Region.MUGHAL:   return "res://scenes/buildings/mughal empire towncenter.tscn"
				Region.MONGOL:   return "res://scenes/buildings/mongol_empire_towncenter.tscn"
				_: return ""
		"outpost":
			match region:
				Region.JAPANESE: return "res://scenes/buildings/japanese outpost.tscn"
				Region.MUGHAL:   return "res://scenes/buildings/mughal empire outpost.tscn"
				Region.MONGOL:   return "res://scenes/buildings/mongolian outpost.tscn"
				_: return ""
		"barracks":
			match region:
				Region.JAPANESE: return "res://scenes/buildings/japanese barrack.tscn"
				Region.MUGHAL:   return "res://scenes/buildings/mughal_barracks.tscn"
				Region.MONGOL:   return "res://scenes/buildings/mongol empire barracks.tscn"
				_: return ""
		"fort":
			match region:
				Region.JAPANESE: return "res://scenes/buildings/japanese fort.tscn"
				Region.MUGHAL:   return "res://scenes/buildings/mughal empire fort.tscn"
				Region.MONGOL:   return "res://scenes/buildings/mongol empire fort.tscn"
				_: return ""
		"tori_gate":
			match region:
				Region.JAPANESE: return "res://scenes/buildings/tori gate.tscn"
				_: return ""
		"shogunate":
			match region:
				Region.JAPANESE: return "res://scenes/buildings/shogunate.tscn"
				_: return ""
		"agra_fort":
			match region:
				Region.MUGHAL: return "res://scenes/buildings/Agra Fort.tscn"
				_: return ""
		"taj_mahal":
			match region:
				Region.MUGHAL: return "res://scenes/buildings/Taj mahal.tscn"
				_: return ""
		"porcelain_tower":
			match region:
				Region.MONGOL: return "res://scenes/buildings/porcelian tower.tscn"
				_: return ""
		"confunction_academy":
			match region:
				Region.MONGOL: return "res://scenes/buildings/confunction academy.tscn"
				_: return ""
		"rice_paddy":    return "res://scenes/buildings/rice paddy.tscn"
		"marketplace":   return "res://scenes/buildings/marketplace.tscn"
		"stables":       return "res://scenes/buildings/stables.tscn"
		"great_buddha":  return "res://scenes/buildings/great buddha.tscn"
		_: return ""

func get_building_display_name(building_key: String) -> String:
	var data = building_data.get(building_key, {})
	return data.get("display_name", building_key.replace("_", " ").capitalize())

# ===== GENERATIONAL BUILDING PLACEMENT =====
func register_generational_building(building_key: String) -> Dictionary:
	var data = building_data.get(building_key)
	if not data or not data.get("generational", false):
		return { "success": false, "new_age": current_age, "message": "Not a generational building!" }
	
	var region = player_region
	if ResourceManager:
		if ResourceManager.get_region_building_built(region, building_key):
			return { "success": false, "new_age": current_age, "message": "Already built this building!" }
		
		var current_gen = ResourceManager.get_region_generation(region)
		var gen_level = data.get("generation_level", 0)
		
		if current_age < data["age_required"]:
			return { "success": false, "new_age": current_age, "message": "Wrong age to build this!" }
		
		if gen_level <= current_gen:
			return { "success": false, "new_age": current_age, "message": "This generation already completed!" }
		
		if gen_level != current_gen + 1:
			return { "success": false, "new_age": current_age, "message": "Build previous generation buildings first!" }
		
		var new_age = data["advances_to_age"]
		var success = ResourceManager.advance_generation(region, building_key, new_age)
		
		if success:
			# ✅ Update player's local cache ONLY if this is the player's region
			current_age = new_age
			generational_buildings_built[building_key] = true
			generations_completed += 1
			
			print("\n" + "=".repeat(50))
			print("🎉 GENERATION ", generations_completed, " COMPLETED! 🎉")
			print("🏛️ Built: ", get_building_display_name(building_key))
			print("➡️ Advanced to: ", age_names[current_age])
			print("=".repeat(50))
			
			# ✅ Signals are now emitted from ResourceManager.advance_generation()
			# for the player's region only
			
			return { 
				"success": true, 
				"new_age": current_age, 
				"generation": generations_completed,
				"message": "Advanced to " + age_names[current_age] + "!" 
			}
	
	return { "success": false, "new_age": current_age, "message": "Failed to advance generation!" }
# ===== BUILDING AVAILABILITY =====
func is_building_unlocked(building_key: String) -> bool:
	var data = building_data.get(building_key)
	if not data: return false
	
	# ✅ Use per-region tracking for player
	var region = player_region
	if ResourceManager:
		var region_age = ResourceManager.get_region_age(region)
		if region_age < data["age_required"]:
			return false
		
		if data.has("region") and data["region"] != null and data["region"] != region:
			return false
		
		if data.get("generational", false):
			if ResourceManager.get_region_building_built(region, building_key):
				return false
		
		return true
	
	# Fallback to old behavior
	if current_age < data["age_required"]: return false
	if data.has("region") and data["region"] != null and data["region"] != player_region:
		return false
	if data.get("generational", false):
		if generational_buildings_built.get(building_key, false):
			return false
	return true

func get_next_required_building() -> String:
	var region = player_region
	if ResourceManager:
		var gen_completed = ResourceManager.get_region_generation(region)
		match gen_completed:
			0:
				match region:
					Region.JAPANESE: return "tori_gate"
					Region.MUGHAL: return "agra_fort"
					Region.MONGOL: return "porcelain_tower"
			1:
				match region:
					Region.JAPANESE: return "shogunate"
					Region.MUGHAL: return "taj_mahal"
					Region.MONGOL: return "confunction_academy"
			2:
				return "great_buddha"
			_:
				return ""
	
	# Fallback to old behavior
	return get_next_required_building_old()

# Keep old function for backward compatibility
func get_next_required_building_old() -> String:
	match generations_completed:
		0:
			match player_region:
				Region.JAPANESE: return "tori_gate"
				Region.MUGHAL: return "agra_fort"
				Region.MONGOL: return "porcelain_tower"
				_: return ""
		1:
			match player_region:
				Region.JAPANESE: return "shogunate"
				Region.MUGHAL: return "taj_mahal"
				Region.MONGOL: return "confunction_academy"
				_: return ""
		2:
			return "great_buddha"
		_: return ""
func get_buildable_buildings() -> Array:
	var buildable = []
	for key in building_data:
		if is_building_unlocked(key):
			buildable.append(key)
	return buildable

func get_current_age_name() -> String:
	return age_names[current_age]

func get_generations_completed() -> int:
	return generations_completed


func get_next_building_display_name() -> String:
	var key = get_next_required_building()
	return get_building_display_name(key)

# ===== TOWN CENTER LIMIT =====
var town_center_count: int = 0
const MAX_TOWN_CENTERS: int = 3

func can_build_town_center() -> bool:
	if town_center_count >= MAX_TOWN_CENTERS:
		print("❌ Build Limit Reached: Maximum of 3 Town Centers allowed!")
		return false
	return true

# ===== DEBUG HELPERS =====
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_0:
				add_resource("food", 2000)
				add_resource("wood", 2000)
				add_resource("coin", 1000)
				print("🔧 DEBUG: Added 2000 food, 2000 wood, 1000 coin")
			KEY_9:
				add_resource("food", 5000)
				add_resource("coin", 2000)
				print("🔧 DEBUG: Added 5000 food, 2000 coin")
			_:
				pass
