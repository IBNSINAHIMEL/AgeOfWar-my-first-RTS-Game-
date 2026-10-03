extends StaticBody2D

# ===== NODE REFERENCES =====
@onready var animated_sprite = $AnimatedSprite2D
@onready var selection_area = $Area2D
@onready var health_bar = $ProgressBar
@onready var construction_timer = $Timer
@onready var collision_shape = $CollisionShape2D

# ===== CONFIGURABLE PROPERTIES =====
@export var max_health: int = 1000
@export var build_time: float = 10.0
@export var click_radius: float = 0.0 # 🟢 Fallback click radius size in pixels

# Unit scenes (Assign these in the Inspector panel)
@export var villager_scene: PackedScene
@export var samurai_scene: PackedScene
@export var archer_knight_scene: PackedScene
@export var flaming_arrow_scene: PackedScene

# ===== RUNTIME VARIABLES =====
var current_generation: int = 0
var is_built: bool = false
var is_selected: bool = false
var is_destroyed: bool = false
var current_health: int

# Villager tracking counters
var villagers_spawned: int = 0
var male_villager_count: int = 0
var female_villager_count: int = 0

# Local Resource Fallbacks (Used if global GameManager auto-load isn't found)
var food: int = 500 
var wood: int = 200
var stone: int = 100
var gold: int = 150

# State management mechanics
enum TownState { CONSTRUCTING, IDLE, DAMAGED, DESTROYED }
var current_state: int = TownState.CONSTRUCTING

enum DamageStage { NORMAL, LIGHT_DAMAGE, HEAVY_DAMAGE, DESTROYED }
var current_damage_stage: int = DamageStage.NORMAL

# ===== SIGNALS =====
signal building_selected(building)
signal building_destroyed(building)
signal generation_claimed(generation: int)
signal villager_spawned(villager)

# ===== INITIALIZATION =====
func _ready():
	current_health = max_health
	current_state = TownState.CONSTRUCTING
	is_destroyed = false
	is_built = false
	
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = max_health
		health_bar.visible = false
	
	# Primary Detection: Setup Area2D Input Picking
	if selection_area:
		selection_area.input_pickable = true
		if selection_area.input_event.is_connected(_on_selection_input):
			selection_area.input_event.disconnect(_on_selection_input)
		selection_area.input_event.connect(_on_selection_input)
	
	add_to_group("town_centers")
	add_to_group("player_buildings")
	
	start_construction()

func start_construction():
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	
	if animated_sprite and animated_sprite.sprite_frames.has_animation("construction"):
		animated_sprite.play("construction")
	elif animated_sprite:
		animated_sprite.play("idle")
	
	if construction_timer:
		construction_timer.wait_time = build_time
		construction_timer.one_shot = true
		construction_timer.start()
		await construction_timer.timeout
		
		if is_instance_valid(self) and not is_destroyed:
			_on_construction_complete()

func _on_construction_complete():
	is_built = true
	current_state = TownState.IDLE
	print("✅ Town Center construction complete!")
	
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
		
	update_damage_animation()
	spawn_initial_villagers()

# ===== 🟢 DUAL-LAYER INPUT DETECTOR =====

# Layer A: Standard Physics-based detection (Area2D)
func _on_selection_input(_viewport, event, _shape_idx):
	var is_mouse_click = event is InputEventMouseButton and event.pressed
	var is_mobile_touch = event is InputEventScreenTouch and event.pressed
	
	if is_mouse_click or is_mobile_touch:
		print("🎯 [Layer A] Click captured via Area2D Collision Object!")
		select_building()
		get_viewport().set_input_as_handled() # Prevent event cascading

# Layer B: Global Math Backup (Runs if Area2D physics picker gets blocked by UI/Bugs)
func _unhandled_input(event):
	if not is_built or is_destroyed: return
	
	var is_mouse_click = event is InputEventMouseButton and event.pressed
	var is_mobile_touch = event is InputEventScreenTouch and event.pressed
	
	if is_mouse_click or is_mobile_touch:
		var target_click_pos = get_global_mouse_position()
		var distance = global_position.distance_to(target_click_pos)
		
		# If click falls within our designated building screen zone
		if distance <= click_radius:
			print("⚡ [Layer B Fallback] Math Engine intercepted click at distance: ", int(distance), "px")
			select_building()
			get_viewport().set_input_as_handled()

# ===== SELECTION PROCESSORS =====
func select_building():
	if not is_built or is_destroyed:
		return
		
	is_selected = true
	
	if animated_sprite:
		animated_sprite.modulate = Color(1.1, 1.1, 0.7) # Selection glow highlight
	if health_bar:
		health_bar.visible = true
		
	# Find UI node in active screen view tree layout hierarchy
	var ui_node = get_tree().root.find_child("JapaneseTownCenterUI", true, false)
	if ui_node:
		ui_node.show_ui(self)
	else:
		emit_signal("building_selected", self)
		print("⚠️ UI Routing Failure: 'JapaneseTownCenterUI' node could not be located in current scene path.")

func deselect():
	is_selected = false
	if animated_sprite:
		animated_sprite.modulate = Color.WHITE
	if health_bar and current_health == max_health:
		health_bar.visible = false

# ===== UNIT PRODUCTION MANAGEMENT =====
func spawn_initial_villagers():
	var genders = ["male", "female", "male", "female"]
	for gender in genders:
		await get_tree().create_timer(0.4).timeout
		if not is_instance_valid(self) or is_destroyed: return
		spawn_villager_with_gender(gender)

func spawn_villager_with_gender(gender: String) -> bool:
	if not is_built or is_destroyed or not villager_scene:
		return false
		
	if get_food() < 100:
		print("❌ Training canceled: Insufficient Food resources.")
		return false
		
	if "GameManager" in get_tree().root:
		get_tree().root.GameManager.food -= 100
	else:
		food -= 100
		
	var spawn_pos = global_position + Vector2(randf_range(-60, 60), randf_range(-40, 40))
	var villager = villager_scene.instantiate()
	villager.global_position = spawn_pos
	
	if villager.has_method("set_gender"):
		villager.set_gender(gender)
		if gender == "male": male_villager_count += 1
		else: female_villager_count += 1
		villagers_spawned += 1
		
	get_parent().add_child(villager)
	emit_signal("villager_spawned", villager)
	
	return true

func spawn_villager() -> bool:
	var gender = "male" if (villagers_spawned % 2 == 0) else "female"
	return spawn_villager_with_gender(gender)

# ===== MILITARY GENERATION PROGRESSION =====
func trigger_generation_bonus(generation: int) -> bool:
	if not is_built or is_destroyed or generation <= current_generation or generation > 3:
		return false
		
	current_generation = generation
	
	match generation:
		1: spawn_units(samurai_scene, 8)
		2: spawn_units(archer_knight_scene, 8)
		3: spawn_units(flaming_arrow_scene, 4)
		
	emit_signal("generation_claimed", generation)
	return true

func spawn_units(unit_scene: PackedScene, count: int):
	if not unit_scene: return
	for i in range(count):
		await get_tree().create_timer(0.25).timeout
		if not is_instance_valid(self) or is_destroyed or not get_parent(): return
		
		var spawn_pos = global_position + Vector2(randf_range(-70, 70), randf_range(-50, 50))
		var unit = unit_scene.instantiate()
		get_parent().add_child(unit)
		unit.global_position = spawn_pos

# ===== HEALTH AND DAMAGES HANDLING =====
func take_damage(amount: int):
	if not is_built or is_destroyed: return
	current_health = max(0, current_health - amount)
	
	if health_bar:
		health_bar.value = current_health
		health_bar.visible = true
		
	update_damage_stage()
	
	if animated_sprite:
		animated_sprite.modulate = Color.RED
		await get_tree().create_timer(0.12).timeout
		if is_instance_valid(self) and not is_destroyed:
			animated_sprite.modulate = Color(1.1, 1.1, 0.7) if is_selected else Color.WHITE
			
	if current_health <= 0:
		destroy()

func update_damage_stage():
	var pct = float(current_health) / float(max_health)
	if pct <= 0: current_damage_stage = DamageStage.DESTROYED
	elif pct <= 0.3: current_damage_stage = DamageStage.HEAVY_DAMAGE
	elif pct <= 0.7: current_damage_stage = DamageStage.LIGHT_DAMAGE
	else: current_damage_stage = DamageStage.NORMAL
	update_damage_animation()

func update_damage_animation():
	if not is_built or is_destroyed or not animated_sprite: return
	match current_damage_stage:
		DamageStage.NORMAL:
			if animated_sprite.sprite_frames.has_animation("idle"): animated_sprite.play("idle")
		DamageStage.LIGHT_DAMAGE:
			if animated_sprite.sprite_frames.has_animation("destruction1"): animated_sprite.play("destruction1")
		DamageStage.HEAVY_DAMAGE:
			if animated_sprite.sprite_frames.has_animation("destruction2"): animated_sprite.play("destruction2")

func destroy():
	if is_destroyed: return
	is_destroyed = true
	is_built = false
	
	if collision_shape: collision_shape.set_deferred("disabled", true)
	if health_bar: health_bar.visible = false
	
	var ui_node = get_tree().root.find_child("JapaneseTownCenterUI", true, false)
	if ui_node and ui_node.target_building == self:
		ui_node.hide_ui()
		
	emit_signal("building_destroyed", self)
	
	if animated_sprite and animated_sprite.sprite_frames.has_animation("destroyed"):
		animated_sprite.play("destroyed")
		await animated_sprite.animation_finished
		
	queue_free()

# ===== EXPORT DATA INTERFACES =====
func get_food() -> int:
	if "GameManager" in get_tree().root: return get_tree().root.GameManager.food
	return food

func get_current_generation() -> int: return current_generation
func get_health_percent() -> float: return float(current_health) / float(max_health)
func can_claim_generation(gen: int) -> bool: return is_built and not is_destroyed and gen == (current_generation + 1)

func get_villager_counts() -> Dictionary:
	return { "male": male_villager_count, "female": female_villager_count, "total": villagers_spawned }

func get_status_text() -> String:
	if is_destroyed: return "DESTROYED"
	if not is_built: return "BUILDING..."
	match current_damage_stage:
		DamageStage.LIGHT_DAMAGE: return "LIGHT DAMAGE"
		DamageStage.HEAVY_DAMAGE: return "CRITICAL DAMAGE"
		_: return "OPERATIONAL"
