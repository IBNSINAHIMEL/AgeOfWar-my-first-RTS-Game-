# ===== ResourceManager.gd (Autoload) =====
extends Node
# ===== POPULATION / TOWN CENTER LIMITS =====
const UNITS_PER_TOWN_CENTER: int = 40
const MAX_TOWN_CENTERS_PER_REGION: int = 3

signal population_cap_reached(region: int)
# Region-specific resource pools
var region_resources = {
	0: { "food": 500, "wood": 500, "coin": 200 },  # Japanese
	1: { "food": 500, "wood": 500, "coin": 200 },  # Mughal
	2: { "food": 500, "wood": 500, "coin": 200 },  # Mongol
}

# ===== PER-REGION GENERATION TRACKING =====
var region_generations: Dictionary = {
	0: { "completed": 0, "age": 0, "buildings_built": {} },  # Japanese
	1: { "completed": 0, "age": 0, "buildings_built": {} },  # Mughal
	2: { "completed": 0, "age": 0, "buildings_built": {} },  # Mongol
}

# Player's region (set by GameManager)
var player_region: int = 0

func _ready():
	await get_tree().process_frame
	if GameManager:
		player_region = GameManager.player_region

# ===== RESOURCE FUNCTIONS =====
func get_resource(region: int, type: String) -> int:
	return region_resources.get(region, {}).get(type, 0)

func add_resource(region: int, type: String, amount: int):
	if region not in region_resources:
		region_resources[region] = { "food": 0, "wood": 0, "coin": 0 }
	region_resources[region][type] += amount
	if region == player_region:
		_emit_resource_update(type)

func spend_resource(region: int, type: String, amount: int) -> bool:
	if region not in region_resources:
		return false
	if region_resources[region][type] >= amount:
		region_resources[region][type] -= amount
		if region == player_region:
			_emit_resource_update(type)
		return true
	return false
# ══════════════════════════════════════════════════════════════
#  POPULATION
# ══════════════════════════════════════════════════════════════
func get_region_population(region: int) -> int:
	var count := 0
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u):
			continue
		var r := -1
		if u.has_meta("owner_region"):
			r = int(u.get_meta("owner_region"))
		elif "owner_region" in u:
			r = int(u.owner_region)
		elif "my_region" in u:
			r = int(u.my_region)
		if r == region:
			count += 1
	return count

func get_region_tc_count(region: int) -> int:
	var count := 0
	for tc in get_tree().get_nodes_in_group("town_centers"):
		if not is_instance_valid(tc):
			continue
		if "is_destroyed" in tc and tc.is_destroyed:
			continue
		var r := -1
		if tc.has_meta("owner_region"):
			r = int(tc.get_meta("owner_region"))
		elif "my_region" in tc:
			r = int(tc.my_region)
		if r == region:
			count += 1
	return count

func get_region_population_cap(region: int) -> int:
	return get_region_tc_count(region) * UNITS_PER_TOWN_CENTER

func can_region_spawn_unit(region: int) -> bool:
	var cap := get_region_population_cap(region)
	if cap <= 0:
		return false
	return get_region_population(region) < cap

func can_region_build_town_center(region: int) -> bool:
	return get_region_tc_count(region) < MAX_TOWN_CENTERS_PER_REGION

## Call this from a spawn site when spawning is refused due to cap.
## Emits the signal so the HUD (player only) can show a warning.
func notify_population_cap(region: int) -> void:
	emit_signal("population_cap_reached", region)
func can_afford(region: int, cost: Dictionary) -> bool:
	for type in cost:
		if get_resource(region, type) < cost[type]:
			return false
	return true

# ===== GENERATION FUNCTIONS =====
func get_region_generation(region: int) -> int:
	return region_generations.get(region, {}).get("completed", 0)

func get_region_age(region: int) -> int:
	return region_generations.get(region, {}).get("age", 0)

func get_region_building_built(region: int, building_key: String) -> bool:
	var buildings = region_generations.get(region, {}).get("buildings_built", {})
	return buildings.get(building_key, false)

func mark_building_built(region: int, building_key: String):
	if region not in region_generations:
		region_generations[region] = { "completed": 0, "age": 0, "buildings_built": {} }
	region_generations[region]["buildings_built"][building_key] = true

func advance_generation(region: int, building_key: String, new_age: int) -> bool:
	if region not in region_generations:
		region_generations[region] = { "completed": 0, "age": 0, "buildings_built": {} }

	if region_generations[region]["buildings_built"].get(building_key, false):
		return false

	var current_completed = region_generations[region]["completed"]
	var data = GameManager.building_data.get(building_key) if GameManager else null
	if not data:
		return false

	var gen_level = data.get("generation_level", 0)
	if gen_level != current_completed + 1:
		return false

	region_generations[region]["buildings_built"][building_key] = true
	region_generations[region]["completed"] = gen_level
	region_generations[region]["age"] = new_age

	# ═══════════════════════════════════════════════════════════
	# ✅ FIX: Read GameManager.player_region at CALL time,
	#    not the stale cached ResourceManager.player_region.
	# ═══════════════════════════════════════════════════════════
	var current_player_region := GameManager.player_region if GameManager else region
	if region == current_player_region:
		if GameManager:
			GameManager.emit_signal("age_changed", new_age, gen_level)
			GameManager.emit_signal("generational_building_built", building_key, new_age)

	return true

func _emit_resource_update(type: String):
	if GameManager:
		var pr := GameManager.player_region
		GameManager.emit_signal("resources_updated", type, get_resource(pr, type))
