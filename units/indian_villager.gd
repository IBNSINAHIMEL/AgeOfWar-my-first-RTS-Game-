# indian_villager.gd - Mughal Empire Villager
extends CharacterBody2D

@onready var animated_sprite = $AnimatedSprite2D
@onready var health_bar = $HealthBar if has_node("HealthBar") else null

# Villager properties
var villager_type: String = "female"
var speed: float = 100.0

# Resource collection states
enum VillagerState { IDLE, WALK, COLLECTING }
var current_state = VillagerState.IDLE
var selected = false

# Movement targets
var target_position: Vector2 = Vector2.ZERO
var target_resource: Node2D = null
var target_enemy: Node2D = null
var is_moving: bool = false
var is_harvesting: bool = false
var collection_timer: float = 0.0
const COLLECTION_INTERVAL: float = 1.0
var resource_type_collecting: String = ""

# ===== HEALTH & DEATH =====
var max_health: int = 50
var current_health: int = 50
var is_alive: bool = true

# ===== HEALTH BAR SIZE (tweak per unit in Inspector) =====
@export var health_bar_size: Vector2 = Vector2(45, 6)
@export var health_bar_offset: Vector2 = Vector2(-22, -55)

# ===== REGION =====
var owner_region: int = -1

# ===== COMMAND TRACKING =====
var is_player_command: bool = false
var auto_flee_timer: float = 0.0

# ===== ANIMATION MAPPING (Mughal specific) =====
var anim_names = {
	"idle": "",
	"walk": "",
	"wood": "",
	"coin": "",
	"food_farming": "",
	"die": ""
}

# ══════════════════════════════════════════════════════════
#  INITIALIZATION
# ══════════════════════════════════════════════════════════
func _ready():
	if name.begins_with("@"):
		name = "Mughal_Villager_R%d" % int(get_meta("owner_region", -1))
	collision_layer = 1
	collision_mask = 2

	current_health = max_health
	setup_animation_names()
	
	# ✅ Health bar setup FIRST
	_create_health_bar_textures()
	_setup_health_bar()
	
	z_index = 10
	z_as_relative = false
	
	# Get region from metadata
	if has_meta("owner_region"):
		owner_region = get_meta("owner_region")
	else:
		owner_region = GameManager.player_region if GameManager else -1
	_assign_groups()
	
	# Setup collision for physics
	if not $CollisionShape2D:
		var phys_shape = CollisionShape2D.new()
		var rect_shape = RectangleShape2D.new()
		rect_shape.size = Vector2(20, 20)
		phys_shape.shape = rect_shape
		add_child(phys_shape)
		print("✅ Physics collision added")
	
	# Setup click/touch detection
	_setup_click_detection()
	
	if animated_sprite and animated_sprite.sprite_frames:
		var idle_anim = anim_names.get("idle", "")
		if idle_anim != "" and animated_sprite.sprite_frames.has_animation(idle_anim):
			animated_sprite.play(idle_anim)
	
	add_to_group("units")
	add_to_group("villagers")


# ══════════════════════════════════════════════════════════
#  🎨 HEALTH BAR — CODE GENERATED
# ══════════════════════════════════════════════════════════
func _create_health_bar_textures():
	if not health_bar:
		print("❌ HealthBar node NOT FOUND in ", name)
		return
	
	var w = int(health_bar_size.x)
	var h = int(health_bar_size.y)
	
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	health_bar.texture_progress = ImageTexture.create_from_image(img)
	
	var img_bg = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img_bg.fill(Color(0.15, 0.15, 0.15))
	health_bar.texture_under = ImageTexture.create_from_image(img_bg)


func _setup_health_bar():
	if not health_bar:
		print("❌ Cannot setup health bar — node missing on ", name)
		return
	
	health_bar.size = health_bar_size
	health_bar.custom_minimum_size = health_bar_size
	health_bar.position = health_bar_offset
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	health_bar.min_value = 0
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	
	health_bar.tint_progress = Color(0.2, 0.9, 0.2)
	health_bar.tint_under = Color(0.15, 0.15, 0.15)
	
	health_bar.z_index = 100
	health_bar.z_as_relative = false
	health_bar.visible = false
	
	print("✅ Indian villager health bar setup: ", name)


func _update_health_bar():
	if not health_bar:
		return
	
	health_bar.value = current_health
	var ratio = float(current_health) / float(max_health)
	
	if ratio > 0.6:
		health_bar.tint_progress = Color(0.2, 0.9, 0.2)
	elif ratio > 0.3:
		health_bar.tint_progress = Color(1.0, 0.85, 0.1)
	else:
		health_bar.tint_progress = Color(1.0, 0.2, 0.2)
	
	if current_health < max_health:
		health_bar.visible = true


func _hide_health_bar_if_full():
	if not health_bar:
		return
	if current_health >= max_health and not selected:
		health_bar.visible = false


# ══════════════════════════════════════════════════════════
#  REGION / GROUPS
# ══════════════════════════════════════════════════════════
func _assign_groups():
	remove_from_group("player_units")
	remove_from_group("player")
	remove_from_group("enemy_units")
	remove_from_group("enemy")
	if owner_region == GameManager.player_region:
		add_to_group("player_units")
		add_to_group("player")
	else:
		add_to_group("enemy_units")
		add_to_group("enemy")

func get_enemy_group() -> String:
	return "enemy_units" if owner_region == GameManager.player_region else "player_units"


# ══════════════════════════════════════════════════════════
#  SELECTION & INPUT
# ══════════════════════════════════════════════════════════
func _setup_click_detection():
	input_pickable = true
	if not input_event.is_connected(_on_villager_input):
		input_event.connect(_on_villager_input)
	
	if not has_node("ClickArea"):
		var click_area = Area2D.new()
		click_area.name = "ClickArea"
		var area_shape = CollisionShape2D.new()
		var area_rect = RectangleShape2D.new()
		area_rect.size = Vector2(30, 30)
		area_shape.shape = area_rect
		click_area.add_child(area_shape)
		add_child(click_area)
		click_area.input_event.connect(_on_area_click)
		click_area.mouse_entered.connect(_on_mouse_entered)
		click_area.mouse_exited.connect(_on_mouse_exited)
		print("✅ ClickArea added for touch selection")

func _on_villager_input(viewport: Node, event: InputEvent, shape_idx: int):
	# Only player units can be selected
	if owner_region != GameManager.player_region:
		return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		select_villager()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.pressed:
		select_villager()
		get_viewport().set_input_as_handled()

func _on_area_click(viewport: Node, event: InputEvent, shape_idx: int):
	if owner_region != GameManager.player_region:
		return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		select_villager()
	elif event is InputEventScreenTouch and event.pressed:
		select_villager()

func _on_mouse_entered():
	if not selected and animated_sprite:
		animated_sprite.modulate = Color(1.2, 1.2, 0.9)

func _on_mouse_exited():
	if not selected and animated_sprite:
		animated_sprite.modulate = Color.WHITE

func select_villager():
	if owner_region != GameManager.player_region:
		return
	
	selected = true
	if animated_sprite:
		animated_sprite.modulate = Color(1, 1, 0.5)
	
	# ✅ SHOW + REFRESH health bar
	if health_bar:
		health_bar.visible = true
		health_bar.value = current_health
		
		var ratio = float(current_health) / float(max_health)
		if ratio > 0.6:
			health_bar.tint_progress = Color(0.2, 0.9, 0.2)
		elif ratio > 0.3:
			health_bar.tint_progress = Color(1.0, 0.85, 0.1)
		else:
			health_bar.tint_progress = Color(1.0, 0.2, 0.2)
	
	print("✅ Villager selected (", villager_type, ")")

func deselect_villager():
	selected = false
	if animated_sprite:
		animated_sprite.modulate = Color.WHITE
	_hide_health_bar_if_full()

func set_selected(is_selected: bool):
	selected = is_selected
	if animated_sprite:
		animated_sprite.modulate = Color(1, 1, 0.5) if selected else Color.WHITE
	if is_selected and health_bar:
		health_bar.visible = true
		health_bar.value = current_health
	elif not is_selected:
		_hide_health_bar_if_full()

const SEPARATION_RADIUS: float = 46.0
const SEP_SCAN_INTERVAL: float = 0.10
const SEP_MAX_PUSH: float = 5.0
var _sep_scan_timer: float = 0.0

func _apply_separation(delta: float) -> void:
	_sep_scan_timer -= delta
	if _sep_scan_timer > 0.0:
		return
	_sep_scan_timer = SEP_SCAN_INTERVAL

	var my_group := "player_units" if owner_region == GameManager.player_region else "enemy_units"
	var push := Vector2.ZERO
	var r2 := SEPARATION_RADIUS * SEPARATION_RADIUS

	for other in get_tree().get_nodes_in_group(my_group):
		if other == self or not is_instance_valid(other):
			continue
		if "is_alive" in other and not other.is_alive:
			continue
		var diff: Vector2 = global_position - other.global_position
		var d2 := diff.length_squared()
		if d2 > r2:
			continue

		if d2 < 0.01:
			# Exact overlap — nudge in a random direction so they can't stay stacked
			var nudge := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
			if nudge == Vector2.ZERO:
				nudge = Vector2.RIGHT
			push += nudge.normalized() * (SEPARATION_RADIUS * 0.5)
		else:
			var d := sqrt(d2)
			push += (diff / d) * (SEPARATION_RADIUS - d)

	if push == Vector2.ZERO:
		return

	if push.length() > SEP_MAX_PUSH:
		push = push.normalized() * SEP_MAX_PUSH
	global_position += push
# ══════════════════════════════════════════════════════════
#  GENDER SETUP
# ══════════════════════════════════════════════════════════
func set_gender(gender: String):
	villager_type = gender
	setup_animation_names()
	if gender == "male":
		add_to_group("male_villagers")
	else:
		add_to_group("female_villagers")
	
	if animated_sprite:
		var idle_anim = anim_names.get("idle", "")
		if idle_anim != "" and animated_sprite.sprite_frames.has_animation(idle_anim):
			animated_sprite.play(idle_anim)
	
	print("Gender set to: ", villager_type)

func setup_animation_names():
	if villager_type == "female":
		anim_names = {
			"idle": "female_idle",
			"walk": "female_walk",
			"wood": "female_wood",
			"coin": "female_wood",      # female reuses wood for coin
			"food_farming": "female_food_farming",
			"die": "female_die"
		}
	else:
		anim_names = {
			"idle": "male_idle",
			"walk": "male_walk",
			"wood": "male_wood",
			"coin": "male_wood",        # male reuses wood for coin
			"food_farming": "male_food_farming",
			"die": "male_die"
		}


# ══════════════════════════════════════════════════════════
#  COMMANDS
# ══════════════════════════════════════════════════════════
func move_to(pos: Vector2):
	is_player_command = true
	target_position = pos
	target_resource = null
	target_enemy = null
	is_moving = true
	is_harvesting = false
	current_state = VillagerState.WALK
	play_animation("walk")

func attack(enemy: Node2D):
	if not is_instance_valid(enemy):
		return
	target_enemy = enemy
	target_position = enemy.global_position
	target_resource = null
	is_moving = true
	is_harvesting = false
	current_state = VillagerState.WALK
	play_animation("walk")

func collect(resource: Node2D):
	if not is_instance_valid(resource):
		return
	target_resource = resource
	var direction = (global_position - resource.global_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	const APPROACH_DISTANCE = 55.0
	target_position = resource.global_position + direction * APPROACH_DISTANCE
	target_enemy = null
	is_moving = true
	is_harvesting = false
	current_state = VillagerState.WALK
	play_animation("walk")
	print("Moving to collect: ", resource.name)

func play_animation(anim_type: String):
	if not animated_sprite:
		return
	var anim = anim_names.get(anim_type, "")
	if anim != "" and animated_sprite.sprite_frames.has_animation(anim):
		animated_sprite.play(anim)


# ══════════════════════════════════════════════════════════
#  PHYSICS PROCESS
# ══════════════════════════════════════════════════════════
func _physics_process(delta):
	if not is_alive:
		return
	_apply_separation(delta) 	
	
	if is_moving and target_position != Vector2.ZERO:
		var direction = (target_position - global_position).normalized()
		velocity = direction * speed
		move_and_slide()
		
		if velocity.x != 0 and animated_sprite:
			animated_sprite.flip_h = velocity.x < 0
		
		if global_position.distance_to(target_position) < 25.0:
			is_moving = false
			velocity = Vector2.ZERO
			if target_resource and is_instance_valid(target_resource):
				_start_harvesting()
			elif target_enemy and is_instance_valid(target_enemy):
				_attack_target()
			else:
				target_position = Vector2.ZERO
				play_animation("idle")
	
	if is_harvesting and target_resource and is_instance_valid(target_resource):
		collection_timer -= delta
		if collection_timer <= 0.0:
			_harvest_resource()
			collection_timer = COLLECTION_INTERVAL
			var anim = ""
			match resource_type_collecting:
				"wood": anim = anim_names["wood"]
				"coin": anim = anim_names["coin"]
				"food": anim = anim_names["food_farming"]
			if anim != "" and animated_sprite and animated_sprite.animation != anim:
				animated_sprite.play(anim)
	elif is_harvesting and (not target_resource or not is_instance_valid(target_resource)):
		_stop_harvesting()


# ══════════════════════════════════════════════════════════
#  HARVESTING
# ══════════════════════════════════════════════════════════
func _start_harvesting():
	if not is_instance_valid(target_resource):
		_stop_harvesting()
		return
	
	if target_resource.is_in_group("trees"):
		resource_type_collecting = "wood"
	elif target_resource.is_in_group("bushes"):
		resource_type_collecting = "food"
	elif target_resource.is_in_group("stones"):
		resource_type_collecting = "coin"
	else:
		var name_lower = target_resource.name.to_lower()
		if "tree" in name_lower:
			resource_type_collecting = "wood"
		elif "bush" in name_lower:
			resource_type_collecting = "food"
		elif "stone" in name_lower:
			resource_type_collecting = "coin"
		else:
			resource_type_collecting = "wood"
	
	print("Started harvesting ", resource_type_collecting, " from ", target_resource.name)
	is_harvesting = true
	current_state = VillagerState.COLLECTING
	collection_timer = 0.0
	if animated_sprite:
		var dir = target_resource.global_position.x - global_position.x
		animated_sprite.flip_h = dir < 0

func _harvest_resource():
	if not is_instance_valid(target_resource):
		_stop_harvesting()
		return
	
	if target_resource.has_method("harvest"):
		var amount = await target_resource.harvest()
		if not is_instance_valid(target_resource):
			_stop_harvesting()
			return
		if amount > 0:
			if owner_region != -1 and ResourceManager:
				match resource_type_collecting:
					"wood": ResourceManager.add_resource(owner_region, "wood", amount)
					"food": ResourceManager.add_resource(owner_region, "food", amount)
					"coin": ResourceManager.add_resource(owner_region, "coin", amount)
				print("✅ Harvested ", amount, " ", resource_type_collecting, " for region ", owner_region)
			else:
				match resource_type_collecting:
					"wood": GameManager.add_resource("wood", amount)
					"food": GameManager.add_resource("food", amount)
					"coin": GameManager.add_resource("coin", amount)
				print("✅ Harvested ", amount, " ", resource_type_collecting, " for player (fallback)")
			
			var remaining = _get_remaining()
			if remaining <= 0:
				print("Resource depleted")
				_stop_harvesting()
		else:
			_stop_harvesting()
	else:
		_stop_harvesting()

func _get_remaining() -> int:
	if "current_wood" in target_resource:
		return target_resource.current_wood
	elif "current_berry" in target_resource:
		return target_resource.current_berry
	elif "current_stone" in target_resource:
		return target_resource.current_stone
	return 1

func _stop_harvesting():
	is_harvesting = false
	current_state = VillagerState.IDLE
	target_resource = null
	resource_type_collecting = ""
	play_animation("idle")

func _attack_target():
	print("Attacking: ", target_enemy.name if target_enemy else "enemy")
	target_enemy = null
	current_state = VillagerState.IDLE
	play_animation("idle")

func get_selection_rect() -> Rect2:
	if animated_sprite and anim_names["idle"] != "":
		var tex = animated_sprite.sprite_frames.get_frame_texture(anim_names["idle"], 0)
		if tex:
			var size = tex.get_size()
			return Rect2(global_position - size/2, size)
	return Rect2(global_position - Vector2(32,32), Vector2(64,64))

func print_status():
	if animated_sprite:
		print("Villager - Type:", villager_type, " State:", current_state, " Anim:", animated_sprite.animation)


# ══════════════════════════════════════════════════════════
#  DAMAGE & DEATH
# ══════════════════════════════════════════════════════════
func take_damage(amount: int) -> void:
	if not is_alive:
		return

	current_health = max(0, current_health - amount)
	print("💥 Mughal Villager hit! HP: ", current_health, "/", max_health)

	_update_health_bar()

	if current_health <= 0:
		die()
		return

	if animated_sprite:
		animated_sprite.modulate = Color.RED
		var t := get_tree().create_timer(0.12)
		t.timeout.connect(func():
			if is_instance_valid(self) and is_alive and animated_sprite:
				animated_sprite.modulate = Color.WHITE
		)


func die() -> void:
	if not is_alive:
		return
	is_alive = false

	is_moving = false
	is_harvesting = false
	target_position = Vector2.ZERO
	target_resource = null
	target_enemy = null
	velocity = Vector2.ZERO
	var world := get_tree().get_first_node_in_group("game_world")
	if world and "selected_units" in world:
		world.selected_units.erase(self)

	remove_from_group("units")
	remove_from_group("player_units")
	remove_from_group("enemy_units")
	remove_from_group("player")
	remove_from_group("enemy")
	remove_from_group("villagers")
	remove_from_group("male_villagers")
	remove_from_group("female_villagers")

	set_process(false)
	set_physics_process(false)
	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)

	if health_bar:
		health_bar.visible = false

	print("☠️ Mughal Villager has been killed!")

	var die_anim: String = anim_names.get("die", "")
	if animated_sprite and die_anim != "" \
			and animated_sprite.sprite_frames.has_animation(die_anim):
		animated_sprite.play(die_anim)
		var t := get_tree().create_timer(0.7)
		await t.timeout

	if animated_sprite:
		var tween := create_tween()
		tween.tween_property(animated_sprite, "modulate:a", 0.0, 0.5)
		await tween.finished
	else:
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 0.5)
		await tween.finished

	queue_free()


# ══════════════════════════════════════════════════════════
#  GETTERS
# ══════════════════════════════════════════════════════════
func get_team() -> String:
	return "player" if owner_region == GameManager.player_region else "enemy"

func get_health() -> int:
	return current_health

func get_is_alive() -> bool:
	return is_alive
