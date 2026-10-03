# flaming_arraw.gd - Flaming Arrow Unit (Anti-Unit + Anti-Building)
extends CharacterBody2D

@onready var animated_sprite = $AnimatedSprite2D
@onready var detection_area = $DetectionArea
@onready var health_bar = $TextureProgressBar if has_node("TextureProgressBar") else null

# ===== CONFIGURABLE STATS =====
@export var speed: float = 160.0
@export var attack_range: float = 150.0
@export var attack_damage: int = 20
@export var max_health: int = 100
@export var attack_cooldown: float = 1.2
@export var auto_attack_cooldown: float = 2.0

# ===== HEALTH BAR SIZE =====
@export var health_bar_size: Vector2 = Vector2(55, 7)
@export var health_bar_offset: Vector2 = Vector2(-27, -65)

# ===== REGION =====
var owner_region: int = -1

# ===== STATE VARIABLES =====
enum UnitState { IDLE, WALK, ATTACKING }
var current_state = UnitState.IDLE
var selected = false

var target_position: Vector2 = Vector2.ZERO
var target_enemy: Node2D = null
var is_moving: bool = false
var is_attacking: bool = false
var can_attack: bool = true
var current_health: int
var is_alive: bool = true
var attack_timer: float = 0.0
var player_command_timer: float = 0.0
const PLAYER_COMMAND_MAX: float = 20.0
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
		name = "FlamingArrow_R%d" % int(get_meta("owner_region", -1))
	collision_layer = 1
	collision_mask = 2

	current_health = max_health
	setup_animation_names()

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

	# Read owner region
	if has_meta("owner_region"):
		owner_region = int(get_meta("owner_region"))
	else:
		owner_region = GameManager.player_region if GameManager else -1

	_apply_region_tint()
	_assign_groups()

	add_to_group("units")
	add_to_group("flaming_arrow")

	# DetectionArea — must see BOTH units (1) and buildings (2)
	if detection_area:
		detection_area.input_pickable = false
		detection_area.collision_layer = 0
		detection_area.collision_mask = 3
		if not detection_area.body_entered.is_connected(_on_enemy_detected):
			detection_area.body_entered.connect(_on_enemy_detected)
		if not detection_area.body_exited.is_connected(_on_enemy_exited):
			detection_area.body_exited.connect(_on_enemy_exited)


# ══════════════════════════════════════════════════════════
#  HEALTH BAR
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

	if owner_region == -1:
		return

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

	print("✅ Flaming Arrow selected (Region: ", owner_region, ")")


func deselect():
	selected = false
	_apply_region_tint()
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
#  PLAYER COMMANDS
# ══════════════════════════════════════════════════════════

func attack(target: Node2D) -> void:
	if not is_instance_valid(target):
		return
	if target == self:
		return

	# Reject unknown / own team
	var target_region := -1
	if target.has_meta("owner_region"):
		target_region = int(target.get_meta("owner_region"))

	if target_region == -1:
		# Group fallback
		if owner_region == GameManager.player_region:
			if not (target.is_in_group("enemy_units") or target.is_in_group("enemy_buildings")):
				return
		else:
			if not (target.is_in_group("player_units") or target.is_in_group("player_buildings")):
				return
	elif target_region == owner_region:
		print("⚠️ Cannot attack own region's assets!")
		return

	# Must be a valid combat target
	var is_building := target.is_in_group("buildings")
	var is_unit     := target.is_in_group("units")
	if not (is_building or is_unit):
		return

	# Lock on permanently (with safety timeout)
	target_enemy         = target
	target_position      = target.global_position
	is_moving            = true
	is_attacking         = false
	current_state        = UnitState.WALK
	has_auto_attacked    = false
	is_player_command    = true                    # ← #1
	player_command_timer = PLAYER_COMMAND_MAX      # ← #2
	play_animation("walk")
	print("🔥 Player attack command: ", target.name)


func stop_command():
	target_position = Vector2.ZERO
	target_enemy = null
	is_moving = false
	is_attacking = false
	current_state = UnitState.IDLE
	is_player_command = false
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
#  AUTO-TARGETING
# ══════════════════════════════════════════════════════════
func auto_find_enemy() -> void:
	if owner_region == -1:
		return

	# ── Player command: obey, but only for PLAYER_COMMAND_MAX seconds ──
	if is_player_command:
		player_command_timer -= get_physics_process_delta_time()
		if player_command_timer > 0.0:
			return
		# Timed out — release control back to AI
		is_player_command = false
		player_command_timer = 0.0

	# ── Keep current auto-target if still valid ───────────────
	if target_enemy and is_instance_valid(target_enemy):
		var still_ok := true
		if "is_destroyed" in target_enemy and target_enemy.is_destroyed:
			still_ok = false
		if target_enemy.has_method("get_is_alive") and not target_enemy.get_is_alive():
			still_ok = false
		if still_ok:
			return
		else:
			_stop_attacking()

	# ── Scan for target ───────────────────────────────────────
	var buildings := get_tree().get_nodes_in_group(get_enemy_buildings_group())
	var units     := get_tree().get_nodes_in_group(get_enemy_group())

	var best_building: Node2D = null
	var best_building_score: float = INF
	var best_unit: Node2D = null
	var best_unit_dist: float = INF

	# --- Buildings -------------------------------------------
	for b in buildings:
		if not is_instance_valid(b): continue
		if b == self:                continue
		if "is_built" in b and not b.is_built:       continue
		if "is_destroyed" in b and b.is_destroyed:   continue

		# Region check — meta first, group fallback
		var is_enemy_bldg: bool
		if b.has_meta("owner_region"):
			is_enemy_bldg = int(b.get_meta("owner_region")) != owner_region
		else:
			if owner_region == GameManager.player_region:
				is_enemy_bldg = b.is_in_group("enemy_buildings")
			else:
				is_enemy_bldg = b.is_in_group("player_buildings")

		if not is_enemy_bldg:
			continue

		var dist: float = global_position.distance_to(b.global_position)
		if dist > 1500.0: continue

		# Priority weighting — the lower the score, the higher the priority
		var score: float = dist
		if   b.is_in_group("town_centers"):           score *= 0.2
		elif b.is_in_group("generational_buildings"): score *= 0.3
		elif b.is_in_group("forts"):                  score *= 0.5
		elif b.is_in_group("outposts"):               score *= 0.7
		elif b.is_in_group("barracks"):               score *= 0.85

		if score < best_building_score:
			best_building_score = score
			best_building       = b

	# --- Units -----------------------------------------------
	for u in units:
		if not is_instance_valid(u): continue
		if u == self:                continue

		# Region check — meta first, group fallback
		var is_enemy_unit: bool
		if u.has_meta("owner_region"):
			is_enemy_unit = int(u.get_meta("owner_region")) != owner_region
		else:
			if owner_region == GameManager.player_region:
				is_enemy_unit = u.is_in_group("enemy_units")
			else:
				is_enemy_unit = u.is_in_group("player_units")

		if not is_enemy_unit:
			continue

		var dist: float = global_position.distance_to(u.global_position)
		if dist < best_unit_dist and dist <= 500.0:
			best_unit_dist = dist
			best_unit      = u

	# ── Choose: buildings win absolutely ──────────────────────
	var chosen: Node2D = null
	if best_building:
		chosen = best_building
	elif best_unit:
		chosen = best_unit

	if chosen and chosen != target_enemy:
		print("🎯 ", name, " targeting ", chosen.name, " at ",
			  int(global_position.distance_to(chosen.global_position)), " px")
		_auto_attack_enemy(chosen)


func move_to(pos: Vector2) -> void:
	target_position      = pos
	target_enemy         = null
	is_moving            = true
	is_attacking         = false
	current_state        = UnitState.WALK
	is_player_command    = true                    # ← #1
	player_command_timer = PLAYER_COMMAND_MAX      # ← #2
	play_animation("walk")


func _auto_attack_enemy(enemy: Node2D) -> void:
	if not is_instance_valid(enemy):
		return
	target_enemy         = enemy
	target_position      = enemy.global_position
	is_moving            = true
	is_attacking         = false
	current_state        = UnitState.WALK
	has_auto_attacked    = true
	is_player_command    = false                   # AI-issued, not a player command
	player_command_timer = 0.0
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
	if is_player_command:
		player_command_timer -= delta
		if player_command_timer <= 0.0:
			is_player_command = false	
	 
	if touch_start_pos:
		long_press_timer += delta
		if long_press_timer >= LONG_PRESS_TIME and not touch_is_moving:
			handle_long_press(touch_start_pos)
			touch_start_pos = null

	if not target_enemy or not is_instance_valid(target_enemy):
		auto_find_enemy()

	if target_enemy and is_instance_valid(target_enemy):
		if is_moving and is_player_command and target_position != target_enemy.global_position:
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


func move_to_target() -> void:
	var distance = global_position.distance_to(target_position)

	if distance < 5:
		target_position      = Vector2.ZERO
		velocity             = Vector2.ZERO
		is_moving            = false
		is_player_command    = false               # ← RELEASE control
		player_command_timer = 0.0                 # ← and clear timer
		if animated_sprite:
			animated_sprite.play("idle")
		return

	var direction = (target_position - global_position).normalized()
	velocity = direction * speed

	if direction.x != 0 and animated_sprite:
		animated_sprite.flip_h = direction.x < 0

	if animated_sprite:
		animated_sprite.play("walk")
	move_and_slide()


# ══════════════════════════════════════════════════════════
#  COMBAT
# ══════════════════════════════════════════════════════════
func handle_combat():
	if not target_enemy or not is_instance_valid(target_enemy):
		_stop_attacking()
		return

	# Drop dead / destroyed targets
	if "is_destroyed" in target_enemy and target_enemy.is_destroyed:
		_stop_attacking()
		return
	if target_enemy.has_method("get_is_alive") and not target_enemy.get_is_alive():
		_stop_attacking()
		return

	var distance = global_position.distance_to(target_enemy.global_position)

	if distance > attack_range:
		var direction = (target_enemy.global_position - global_position).normalized()
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
	if not target_enemy or not is_instance_valid(target_enemy):
		_stop_attacking()
		return

	is_attacking = true
	current_state = UnitState.ATTACKING
	can_attack = true
	attack_timer = 0.0

	if animated_sprite:
		var dir = target_enemy.global_position.x - global_position.x
		animated_sprite.flip_h = dir < 0
	var attack_anim = "attack_front" if animated_sprite.flip_h == false else "attack_back"
	play_animation(attack_anim)

	_perform_attack()


func _perform_attack() -> void:
	while is_alive and is_attacking and is_instance_valid(target_enemy):
		if "is_destroyed" in target_enemy and target_enemy.is_destroyed:
			_stop_attacking()
			return
		if target_enemy.has_method("get_is_alive") and not target_enemy.get_is_alive():
			_stop_attacking()
			return

		can_attack = false
		attack_timer = attack_cooldown
		var cached_target_name: String  = target_enemy.name
		var cached_target_pos:  Vector2 = target_enemy.global_position

		print("🔥 Flaming Arrow firing at ", cached_target_name)

		if animated_sprite:
			animated_sprite.modulate = Color(1.5, 1.5, 1.5)
			await get_tree().create_timer(0.1).timeout
			if not is_alive:
				return
			if animated_sprite:
				_apply_region_tint()

		await get_tree().create_timer(0.3).timeout
		if not is_alive:
			return

		var target_valid := is_instance_valid(target_enemy)
		var target_dead := false
		if target_valid and "is_destroyed" in target_enemy:
			target_dead = target_enemy.is_destroyed

		if target_valid and not target_dead:
			var dist := global_position.distance_to(target_enemy.global_position)
			if dist <= attack_range and target_enemy.has_method("take_damage"):
				target_enemy.take_damage(attack_damage)
				print("🔥 Flaming Arrow dealt ", attack_damage, " damage to ", cached_target_name)
				_splash_damage_at(cached_target_pos, target_enemy)   # ← pass primary

		await get_tree().create_timer(attack_cooldown).timeout
		if not is_alive:
			return
		can_attack = true

		if not is_instance_valid(target_enemy):
			_stop_attacking()
			return

		var dist2 := global_position.distance_to(target_enemy.global_position)
		if dist2 > attack_range:
			target_position = target_enemy.global_position
			is_moving = true
			is_attacking = false
			current_state = UnitState.WALK
			play_animation("walk")
			return


func _splash_damage_at(splash_center: Vector2, primary: Node2D = null) -> void:
	var splash_radius: float = 50.0
	var splash_dmg: float    = attack_damage * 0.5

	var targets := get_tree().get_nodes_in_group(get_enemy_group())
	targets += get_tree().get_nodes_in_group(get_enemy_buildings_group())

	for e in targets:
		if not is_instance_valid(e):
			continue
		if e == self:
			continue
		if e == primary:
			continue

		if "is_destroyed" in e and e.is_destroyed:
			continue
		if e.has_method("get_is_alive") and not e.get_is_alive():
			continue

		# Region check — meta first, group fallback
		var is_enemy: bool
		if e.has_meta("owner_region"):
			is_enemy = int(e.get_meta("owner_region")) != owner_region
		else:
			if owner_region == GameManager.player_region:
				is_enemy = e.is_in_group("enemy_units") or e.is_in_group("enemy_buildings")
			else:
				is_enemy = e.is_in_group("player_units") or e.is_in_group("player_buildings")

		if not is_enemy:
			continue

		if splash_center.distance_to(e.global_position) > splash_radius:
			continue

		if e.has_method("take_damage"):
			e.take_damage(splash_dmg)
			print("💥 Splash damage to ", e.name)

func _stop_attacking():
	is_attacking = false
	current_state = UnitState.IDLE
	can_attack = true
	play_animation("idle")
	target_enemy = null
	target_position = Vector2.ZERO
	is_moving = false
	is_player_command = false
	


# ══════════════════════════════════════════════════════════
#  DETECTION
# ══════════════════════════════════════════════════════════
func _on_enemy_detected(body: Node2D):
	if not is_alive:
		return

	# Player command owns the unit — ignore auto-detection entirely
	if is_player_command:
		return

	# Region validation is MANDATORY
	var body_region := -1
	if body.has_meta("owner_region"):
		body_region = int(body.get_meta("owner_region"))
	if body_region == -1:
		return
	if body_region == owner_region:
		return

	# Skip dead / destroyed
	if "is_destroyed" in body and body.is_destroyed:
		return
	if body.has_method("get_is_alive") and not body.get_is_alive():
		return

	# Already have an auto-target? Don't override.
	if target_enemy and is_instance_valid(target_enemy):
		return

	print("🔍 ", name, " detected enemy: ", body.name)
	_auto_attack_enemy(body)


func _on_enemy_exited(body: Node2D):
	if target_enemy == body:
		print("👋 Enemy left detection area")
		target_enemy = null
		if is_attacking:
			_stop_attacking()


# ══════════════════════════════════════════════════════════
#  DAMAGE & DEATH
# ══════════════════════════════════════════════════════════
func take_damage(amount: int) -> void:
	if not is_alive:
		return

	current_health = max(0, current_health - amount)
	print("💥 flaming_arrow hit! HP: ", current_health, "/", max_health)

	_update_health_bar()

	if current_health <= 0:
		die()
		return

	if animated_sprite and animated_sprite.sprite_frames \
			and animated_sprite.sprite_frames.has_animation(anim_names["hurt"]):
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
			if is_instance_valid(self) and animated_sprite:
				_apply_region_tint()
		)


func die() -> void:
	if not is_alive:
		return

	is_alive = false
	is_attacking = false
	is_moving = false
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
	remove_from_group("flaming_arrow")

	set_process(false)
	set_physics_process(false)

	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)
	if detection_area:
		detection_area.set_deferred("monitoring", false)

	if health_bar:
		health_bar.visible = false

	print("☠️ flaming_arrow has fallen!")

	if animated_sprite and animated_sprite.sprite_frames \
			and animated_sprite.sprite_frames.has_animation(anim_names["die"]):
		animated_sprite.play(anim_names["die"])
		var t := get_tree().create_timer(0.7)
		await t.timeout
	else:
		var t := get_tree().create_timer(0.1)
		await t.timeout

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
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
