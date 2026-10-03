# cannon.gd - Siege Unit (Anti-Building) - REGION AWARE
extends CharacterBody2D

@onready var animated_sprite = $AnimatedSprite2D
@onready var detection_area = $DetectionArea
@onready var health_bar = $TextureProgressBar if has_node("TextureProgressBar") else null

# ===== CONFIGURABLE STATS =====
@export var speed: float = 80.0
@export var attack_range: float = 180.0
@export var attack_damage: int = 50
@export var max_health: int = 150
@export var attack_cooldown: float = 3.0
@export var auto_attack_cooldown: float = 2.0

# ===== HEALTH BAR SIZE =====
@export var health_bar_size: Vector2 = Vector2(65, 8)
@export var health_bar_offset: Vector2 = Vector2(-32, -70)

# ===== REGION =====
var owner_region: int = -1

# ===== STATE VARIABLES =====
enum UnitState { IDLE, WALK, ATTACKING }
var current_state = UnitState.IDLE
var selected = false

var target_position: Vector2 = Vector2.ZERO
var target_building: Node2D = null
var is_moving: bool = false
var is_attacking: bool = false
var can_attack: bool = true
var current_health: int
var is_alive: bool = true
var attack_timer: float = 0.0

# ===== COMMAND TRACKING =====
var is_player_command: bool = false
var auto_attack_timer: float = 0.0
var has_auto_attacked: bool = false






# ===== TOUCH INPUT VARIABLES =====
var touch_start_pos = null
var touch_is_moving = false
var long_press_timer = 0.0
const LONG_PRESS_TIME = 0.5

# ===== ANIMATION MAPPING =====
var anim_names = {
	"idle": "idle",
	"walk": "walk",
	"attack_front": "attack_front",
	"attack_back": "attack_back",
	"hurt": "hurt",
	"die": "die"
}

# ══════════════════════════════════════════════════════════
#  INITIALIZATION
# ══════════════════════════════════════════════════════════
func _ready():
	if name.begins_with("@"):
		name = "Cannon_R%d" % int(get_meta("owner_region", -1))
	# ✅ Unit collision — don't block other units
	collision_layer = 1
	collision_mask = 2
	
	current_health = max_health
	setup_animation_names()
	_sep_scan_timer = randf() * SEP_SCAN_INTERVAL  
	
	# ✅ Health bar setup
	_create_health_bar_textures()
	_setup_health_bar()
	
	z_index = 101
	z_as_relative = false
	
	if not $CollisionShape2D:
		var phys_shape = CollisionShape2D.new()
		var rect_shape = RectangleShape2D.new()
		rect_shape.size = Vector2(20, 20)
		phys_shape.shape = rect_shape
		add_child(phys_shape)
	
	_setup_click_detection()
	
	if animated_sprite and animated_sprite.sprite_frames:
		animated_sprite.play(anim_names["idle"])
	
	# ✅ Read owner region
	if has_meta("owner_region"):
		owner_region = get_meta("owner_region")
	else:
		owner_region = GameManager.player_region if GameManager else -1
	
	# ✅ Apply region tint
	_apply_region_tint()
	
	# ✅ Assign groups
	_assign_groups()
	
	add_to_group("units")
	add_to_group("cannon")
	
	# ✅ DetectionArea setup — use custom shape from scene
	if detection_area:
		detection_area.input_pickable = false
		detection_area.collision_layer = 0
		detection_area.collision_mask = 1
		detection_area.body_entered.connect(_on_building_detected)
		detection_area.body_exited.connect(_on_building_exited)


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

# ===== ANTI-STACK SEPARATION =====



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

func get_enemy_buildings_group() -> String:
	return "enemy_buildings" if owner_region == GameManager.player_region else "player_buildings"


# ══════════════════════════════════════════════════════════
#  REGION TINT
# ══════════════════════════════════════════════════════════
func _apply_region_tint():
	if not animated_sprite:
		return
	
	match owner_region:
		0:  # Japanese
			animated_sprite.modulate = Color(1.0, 1.0, 1.0)
		1:  # Mughal
			animated_sprite.modulate = Color(1.0, 0.85, 0.5)
		2:  # Mongol
			animated_sprite.modulate = Color(1.0, 0.4, 0.4)
		_:
			animated_sprite.modulate = Color.WHITE


func setup_animation_names():
	anim_names = {
		"idle": "idle",
		"walk": "walk",
		"attack_front": "attack_front",
		"attack_back": "attack_back",
		"hurt": "hurt",
		"die": "die"
	}

func set_owner_region(region: int):
	owner_region = region
	_apply_region_tint()
	_assign_groups()


# ══════════════════════════════════════════════════════════
#  SELECTION & INPUT
# ══════════════════════════════════════════════════════════
func _setup_click_detection():
	input_pickable = true
	if not input_event.is_connected(_on_unit_input):
		input_event.connect(_on_unit_input)
	
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

func _on_unit_input(viewport: Node, event: InputEvent, shape_idx: int):
	if owner_region != GameManager.player_region:
		return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		select_me()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.pressed:
		select_me()
		get_viewport().set_input_as_handled()

func _on_area_click(viewport: Node, event: InputEvent, shape_idx: int):
	if owner_region != GameManager.player_region:
		return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		select_me()
	elif event is InputEventScreenTouch and event.pressed:
		select_me()

func _on_mouse_entered():
	if not selected and animated_sprite:
		animated_sprite.modulate = Color(1.2, 1.2, 0.9)

func _on_mouse_exited():
	if not selected and animated_sprite:
		_apply_region_tint()

func select_me():
	if owner_region != GameManager.player_region:
		return
	
	var all_units = get_tree().get_nodes_in_group("player")
	for unit in all_units:
		if unit != self and unit.has_method("deselect"):
			unit.deselect()
	
	selected = true
	if animated_sprite:
		animated_sprite.modulate = Color(1, 1, 0.5)
	
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
	
	print("✅ Cannon selected (Region: ", owner_region, ")")

func deselect():
	selected = false
	_apply_region_tint()
	target_position = Vector2.ZERO
	target_building = null
	is_moving = false
	current_state = UnitState.IDLE
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


# ══════════════════════════════════════════════════════════
#  COMMANDS (Player Priority)
# ══════════════════════════════════════════════════════════
func move_to(pos: Vector2):
	_clear_auto_attack()
	target_position = pos
	target_building = null
	is_moving = true
	is_attacking = false
	current_state = UnitState.WALK
	is_player_command = true
	has_auto_attacked = false
	auto_attack_timer = auto_attack_cooldown
	play_animation("walk")
	print("🚶 Player move command to: ", pos)

func attack(target: Node2D):
	if not is_instance_valid(target):
		return
	
	# Only attack enemy buildings from OTHER regions
	if target.is_in_group("enemy_buildings") or target.is_in_group("buildings"):
		var target_region = target.get_meta("owner_region") if target.has_meta("owner_region") else -1
		if target_region == owner_region:
			print("⚠️ Cannot attack own region's building!")
			return
		
		_clear_auto_attack()
		target_building = target
		target_position = target.global_position
		is_moving = true
		is_attacking = false
		current_state = UnitState.WALK
		is_player_command = true
		has_auto_attacked = false
		auto_attack_timer = auto_attack_cooldown
		play_animation("walk")
		print("💥 Player attack command (building): ", target.name)
	else:
		move_to(target.global_position)

func stop_command():
	_clear_auto_attack()
	target_position = Vector2.ZERO
	target_building = null
	is_moving = false
	is_attacking = false
	current_state = UnitState.IDLE
	is_player_command = true
	play_animation("idle")
	velocity = Vector2.ZERO
	print("🛑 Stop command")

func _clear_auto_attack():
	has_auto_attacked = false
	is_player_command = true


# ══════════════════════════════════════════════════════════
#  ANIMATION HELPERS
# ══════════════════════════════════════════════════════════
func play_animation(anim_type: String):
	if not animated_sprite:
		return
	var anim = anim_names.get(anim_type, "")
	if anim and animated_sprite.sprite_frames.has_animation(anim):
		animated_sprite.play(anim)


# ══════════════════════════════════════════════════════════
#  AUTO-FIND BUILDING (signal + proximity scan)
# ══════════════════════════════════════════════════════════
func auto_find_building():
	if owner_region == -1:
		return

	if is_player_command:
		if auto_attack_timer > 0:
			auto_attack_timer -= get_process_delta_time()
		else:
			is_player_command = false

	# ── Keep current target if still valid ────────────────────
	if target_building and is_instance_valid(target_building):
		var still_ok := true
		if "is_destroyed" in target_building and target_building.is_destroyed:
			still_ok = false
		if still_ok:
			return

	# ── Scan buildings only ───────────────────────────────────
	var buildings := get_tree().get_nodes_in_group(get_enemy_buildings_group())

	var best: Node2D = null
	var best_score := INF

	for b in buildings:
		if not is_instance_valid(b): continue
		if b == self: continue
		if "is_built" in b and not b.is_built:       continue
		if "is_destroyed" in b and b.is_destroyed:   continue
		var r = b.get_meta("owner_region") if b.has_meta("owner_region") else -1
		if r == owner_region: continue

		var dist = global_position.distance_to(b.global_position)
		if dist > 600.0: continue

		var score: float = dist
		if   b.is_in_group("town_centers"):           score *= 0.2
		elif b.is_in_group("generational_buildings"): score *= 0.3
		elif b.is_in_group("forts"):                  score *= 0.5
		elif b.is_in_group("outposts"):               score *= 0.7
		elif b.is_in_group("barracks"):               score *= 0.85

		if score < best_score:
			best_score = score
			best       = b

	if best:
		if best != target_building:
			print("🎯 ", name, " sieging ", best.name, " at ",
				  int(global_position.distance_to(best.global_position)), " px")
			_auto_attack_building(best)


func _auto_attack_building(building: Node2D):
	if not is_instance_valid(building):
		return
	
	target_building = building
	target_position = building.global_position
	is_moving = true
	is_attacking = false
	current_state = UnitState.WALK
	has_auto_attacked = true
	is_player_command = false
	play_animation("walk")

func handle_long_press(touch_pos):
	print("📱 Mobile: Long press detected")


# ══════════════════════════════════════════════════════════
#  PHYSICS PROCESS
# ══════════════════════════════════════════════════════════
func _physics_process(delta):
	if not is_alive:
		return
	_apply_separation(delta) 	
	
	if touch_start_pos:
		long_press_timer += delta
		if long_press_timer >= LONG_PRESS_TIME and not touch_is_moving:
			handle_long_press(touch_start_pos)
			touch_start_pos = null
	
	if not target_building or not is_instance_valid(target_building):
		auto_find_building()
	
	if target_building and is_instance_valid(target_building):
		if is_moving and is_player_command and target_position != target_building.global_position:
			if target_position:
				move_to_target()
				return
		handle_combat()
		
		return
	
	if target_position:
		move_to_target()
		return
	
	if animated_sprite:
		animated_sprite.play("idle")
	velocity = Vector2.ZERO

func move_to_target():
	var distance = global_position.distance_to(target_position)
	
	if distance < 5:
		target_position = Vector2.ZERO
		if animated_sprite:
			animated_sprite.play("idle")
		velocity = Vector2.ZERO
		if is_player_command:
			is_player_command = false
		return
	
	var direction = (target_position - global_position).normalized()
	velocity = direction * speed
	
	if direction.x != 0 and animated_sprite:
		animated_sprite.flip_h = direction.x < 0
	
	if animated_sprite:
		animated_sprite.play("walk")
	move_and_slide()

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
#  COMBAT
# ══════════════════════════════════════════════════════════
func handle_combat():
	if not target_building or not is_instance_valid(target_building):
		_stop_attacking()
		return
	
	var distance = global_position.distance_to(target_building.global_position)
	
	if distance > attack_range:
		var direction = (target_building.global_position - global_position).normalized()
		velocity = direction * speed
		if animated_sprite:
			animated_sprite.play("walk")
			animated_sprite.flip_h = direction.x < 0
		move_and_slide()
	else:
		velocity = Vector2.ZERO
		if not is_attacking and can_attack:
			_start_attacking()

func _start_attacking():
	if not target_building or not is_instance_valid(target_building):
		_stop_attacking()
		return
	is_attacking = true
	current_state = UnitState.ATTACKING
	can_attack = true
	attack_timer = 0.0
	if animated_sprite:
		var dir = target_building.global_position.x - global_position.x
		animated_sprite.flip_h = dir < 0
	var attack_anim = "attack_front" if animated_sprite.flip_h == false else "attack_back"
	play_animation(attack_anim)
	
	# ✅ CRITICAL: Actually perform the attack
	_perform_attack()

func _perform_attack():
	if not is_instance_valid(target_building):
		_stop_attacking()
		return
	can_attack = false
	attack_timer = attack_cooldown
	
	if target_building.has_method("take_damage"):
		target_building.take_damage(attack_damage)
		print("💥 Cannon dealt ", attack_damage, " damage to ", target_building.name)
		
		if target_building.has_method("get_is_alive") and not target_building.get_is_alive():
			_stop_attacking()
			return
	else:
		print("⚠️ Target building has no take_damage method")
	
	if animated_sprite:
		animated_sprite.modulate = Color(1.5, 1.5, 1.5)
		await get_tree().create_timer(0.1).timeout
		if is_instance_valid(self) and animated_sprite and is_alive:
			_apply_region_tint()
	
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true
	if is_instance_valid(target_building) and is_attacking:
		var dist = global_position.distance_to(target_building.global_position)
		if dist <= attack_range:
			_perform_attack()
		else:
			target_position = target_building.global_position
			is_moving = true
			is_attacking = false
			current_state = UnitState.WALK
			play_animation("walk")

func _stop_attacking():
	is_attacking = false
	current_state = UnitState.IDLE
	can_attack = true
	play_animation("idle")
	target_building = null
	target_position = Vector2.ZERO
	is_moving = false


# ══════════════════════════════════════════════════════════
#  DETECTION
# ══════════════════════════════════════════════════════════
func _on_building_detected(body: Node2D):
	if not is_alive:
		return
	
	if is_player_command and auto_attack_timer > 0:
		return
	
	if body.is_in_group("buildings") and (not target_building or not is_instance_valid(target_building)):
		var target_region = body.get_meta("owner_region") if body.has_meta("owner_region") else -1
		if target_region == owner_region:
			return  # Same region — don't attack
		
		if is_moving and is_player_command and target_position != Vector2.ZERO:
			return
		
		print("🔍 Cannon detected enemy building: ", body.name)
		_auto_attack_building(body)

func _on_building_exited(body: Node2D):
	if target_building == body:
		print("👋 Building left detection area")
		target_building = null
		if is_attacking:
			_stop_attacking()


# ══════════════════════════════════════════════════════════
#  DAMAGE & DEATH
# ══════════════════════════════════════════════════════════
func take_damage(amount: int) -> void:
	if not is_alive:
		return

	current_health = max(0, current_health - amount)
	print("💥 Cannon hit! HP: ", current_health, "/", max_health)

	_update_health_bar()

	# ✅ Death check BEFORE any await
	if current_health <= 0:
		die()
		return

	# Hurt flash — no await, fire-and-forget
	if animated_sprite and animated_sprite.sprite_frames \
			and animated_sprite.sprite_frames.has_animation(anim_names.get("hurt", "")):
		play_animation("hurt")
		var t := get_tree().create_timer(0.25)
		t.timeout.connect(func():
			if is_instance_valid(self) and is_alive and animated_sprite:
				play_animation("idle")
		)
	elif animated_sprite:
		animated_sprite.modulate = Color.RED
		var t := get_tree().create_timer(0.1)
		t.timeout.connect(func():
			if is_instance_valid(self) and is_alive and animated_sprite:
				_apply_region_tint()
		)


func die() -> void:
	if not is_alive:
		return

	# ✅ Kill flag + state reset FIRST
	is_alive = false
	is_attacking = false
	is_moving = false
	target_building = null
	target_position = Vector2.ZERO
	velocity = Vector2.ZERO
	
	var world := get_tree().get_first_node_in_group("game_world")
	if world and "selected_units" in world:
		world.selected_units.erase(self)

	# ✅ Remove from every group joined in _ready / _assign_groups
	remove_from_group("units")
	remove_from_group("cannon")
	remove_from_group("player_units")
	remove_from_group("enemy_units")
	remove_from_group("player")
	remove_from_group("enemy")

	# ✅ Stop all logic and physics
	set_process(false)
	set_physics_process(false)
	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)

	if health_bar:
		health_bar.visible = false

	print("☠️ Cannon destroyed!")

	# Death animation — timer, NOT animation_finished
	var die_anim: String = anim_names.get("die", "")
	if animated_sprite and die_anim != "" \
			and animated_sprite.sprite_frames.has_animation(die_anim):
		play_animation("die")
		var t := get_tree().create_timer(0.7)   # match your die animation length
		await t.timeout

	# Fade out
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

func get_region() -> int:
	return owner_region
