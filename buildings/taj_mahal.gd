extends StaticBody2D
class_name TajMahal

# ══════════════════════════════════════════════════════════════
#  TAJ MAHAL  –  Mughal Empire Wonder (Era 2)
#  Pure cultural/generational building — no combat
# ══════════════════════════════════════════════════════════════

# ===== NODE REFS =====
@onready var animated_sprite    : AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: Node2D = $CollisionPolygon2D
@onready var reserved_area      : Area2D           = $Area2D
@onready var health_bar         : ProgressBar      = $ProgressBar
@onready var construction_timer : Timer            = $Timer
@onready var ambient_particles  : GPUParticles2D   = $GPUParticles2D

# ===== CONFIG =====
@export var max_health : int   = 1200
@export var build_time : float = 13.0

# ===== GENERATIONAL DATA =====
var building_key     : String = "taj_mahal"
var generation_level : int    = 2

# ===== REGION =====
enum Region { JAPANESE = 0, MUGHAL = 1, MONGOL = 2 }
var owner_region  : int = 1
var player_region : int = 0

# ===== STATE =====
var is_built     : bool = false
var is_selected  : bool = false
var is_destroyed : bool = false
var current_health : int = 0

enum TownState { CONSTRUCTING, IDLE, DAMAGED, DESTROYED }
enum DamageStage { NORMAL, LIGHT_DAMAGE, HEAVY_DAMAGE, DESTROYED }
var current_state        : int = TownState.CONSTRUCTING
var current_damage_stage : int = DamageStage.NORMAL

signal building_selected(building)
signal building_destroyed(building)

# ══════════════════════════════════════════════════════════════
#  READY
# ══════════════════════════════════════════════════════════════
func _ready() -> void:
	# --- Region: meta first, parent name fallback, Mughal default ---
	owner_region = Region.MUGHAL
	if has_meta("owner_region"):
		owner_region = int(get_meta("owner_region"))
	else:
		var parent = get_parent()
		if parent:
			var nl = parent.name.to_lower()
			if nl.contains("japanese"): owner_region = Region.JAPANESE
			elif nl.contains("mughal"): owner_region = Region.MUGHAL
			elif nl.contains("mongol"): owner_region = Region.MONGOL
		set_meta("owner_region", owner_region)

	if GameManager:
		player_region = GameManager.player_region

	print("🏛️ Taj Mahal owner region: ", owner_region)

	# --- Collision: buildings layer, no mask (decorative, no combat) ---
	collision_layer = 2
	collision_mask  = 0

	# --- State reset ---
	current_health       = max_health
	is_built             = false
	is_destroyed         = false
	is_selected          = false
	current_state        = TownState.CONSTRUCTING
	current_damage_stage = DamageStage.NORMAL

	# --- Health bar ---
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value     = max_health
		health_bar.visible   = false

	# --- Click / touch on ROOT StaticBody2D ---
	input_pickable = true
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)

	# --- Reserve Area2D (kept for future use, non-intrusive) ---
	if reserved_area:
		reserved_area.input_pickable  = false
		reserved_area.monitoring      = false
		reserved_area.monitorable     = false
		reserved_area.collision_layer = 0
		reserved_area.collision_mask  = 0

	# --- Decorative particles on ---
	if ambient_particles:
		ambient_particles.emitting = true
		ambient_particles.one_shot = false

	# --- Groups ---
	add_to_group("buildings")
	add_to_group("generational_buildings")
	add_to_group("mughal_buildings")

	if owner_region == player_region:
		add_to_group("player_buildings")
	else:
		add_to_group("enemy_buildings")

	# --- Construction ---
	start_construction()

# ══════════════════════════════════════════════════════════════
#  CONSTRUCTION
# ══════════════════════════════════════════════════════════════
func start_construction() -> void:
	if collision_shape:
		collision_shape.disabled = true            # sync

	if animated_sprite and animated_sprite.sprite_frames:
		if animated_sprite.sprite_frames.has_animation("construction"):
			animated_sprite.play("construction")
		elif animated_sprite.sprite_frames.has_animation("idle"):
			animated_sprite.play("idle")

	if build_time <= 0.0:
		_on_construction_complete()
		return

	if construction_timer:
		construction_timer.wait_time = build_time
		construction_timer.one_shot  = true
		if construction_timer.timeout.is_connected(_on_construction_complete):
			construction_timer.timeout.disconnect(_on_construction_complete)
		construction_timer.timeout.connect(_on_construction_complete)
		construction_timer.start()

func _on_construction_complete() -> void:
	if not is_instance_valid(self) or is_destroyed:
		return

	is_built      = true
	current_state = TownState.IDLE
	print("✅ Taj Mahal construction complete!")
	print("🏛️ This generational building advances your Mughal Empire to Colonial Age!")

	if collision_shape:
		collision_shape.disabled = false           # sync

	await get_tree().physics_frame

	if collision_shape:
		print("🔍 [TAJ] shape.disabled = ", collision_shape.disabled,
			  " | layer = ", collision_layer,
			  " | mask = ", collision_mask,
			  " | global = ", global_position)

	update_damage_animation()

	# Only the player's wonder advances generation
	if is_in_group("enemy_buildings"):
		return

	if GameManager and GameManager.has_method("register_generational_building"):
		var result = GameManager.register_generational_building(building_key)
		if result["success"]:
			print("🎉 ", result["message"])
			_show_floating_message(result["message"])
		else:
			print("⚠️ ", result["message"])

func _show_floating_message(text: String) -> void:
	var msg := Label.new()
	msg.text = text
	msg.position = Vector2(100, 100)
	msg.add_theme_color_override("font_color", Color.GOLD)
	msg.add_theme_font_size_override("font_size", 18)
	get_tree().root.add_child(msg)
	var tween := msg.create_tween()
	tween.tween_property(msg, "position", msg.position - Vector2(0, 80), 2.0)
	tween.parallel().tween_property(msg, "modulate", Color.TRANSPARENT, 2.0)
	await tween.finished
	msg.queue_free()

# ══════════════════════════════════════════════════════════════
#  CLICK / TOUCH
# ══════════════════════════════════════════════════════════════
func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not is_in_group("player_buildings"):
		return
	if not is_built or is_destroyed:
		return
	var is_mouse : bool = event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	var is_touch : bool = event is InputEventScreenTouch and event.pressed
	if is_mouse or is_touch:
		print("🎯 Taj Mahal clicked.")
		select_building()
		get_viewport().set_input_as_handled()

# ══════════════════════════════════════════════════════════════
#  SELECTION
# ══════════════════════════════════════════════════════════════
func select_building() -> void:
	if not is_built or is_destroyed:
		return
	is_selected = true
	if animated_sprite:
		animated_sprite.modulate = Color(1.1, 1.1, 0.7)
	if health_bar:
		health_bar.visible = true
	_show_info_message()
	emit_signal("building_selected", self)

func _show_info_message() -> void:
	var msg := Label.new()
	msg.text = "🏛️ TAJ MAHAL\nCultural Wonder\nGenerational Building\n✨ Advances Empire Era"
	msg.position = Vector2(100, 150)
	msg.add_theme_color_override("font_color", Color.CYAN)
	msg.add_theme_font_size_override("font_size", 16)
	add_child(msg)
	var tween := create_tween()
	tween.tween_property(msg, "position", msg.position - Vector2(0, 50), 2.0)
	tween.parallel().tween_property(msg, "modulate", Color.TRANSPARENT, 2.0)
	await tween.finished
	msg.queue_free()

func deselect() -> void:
	is_selected = false
	if animated_sprite:
		animated_sprite.modulate = Color.WHITE
	if health_bar and current_health >= max_health:
		health_bar.visible = false

# ══════════════════════════════════════════════════════════════
#  DAMAGE / DESTRUCTION
# ══════════════════════════════════════════════════════════════
func take_damage(amount: int) -> void:
	if is_destroyed:
		return

	# ✅ Damage counts even during construction
	current_health = max(0, current_health - amount)
	print("💥 Taj Mahal took ", amount, " damage! HP: ", current_health, "/", max_health)

	if health_bar:
		health_bar.value   = current_health
		health_bar.visible = true

	update_damage_stage()

	# ✅ Death check BEFORE any await
	if current_health <= 0:
		destroy()
		return

	# Flash — no await, fire-and-forget
	if animated_sprite:
		animated_sprite.modulate = Color.RED
		var t := get_tree().create_timer(0.12)
		t.timeout.connect(func():
			if is_instance_valid(self) and not is_destroyed and animated_sprite:
				animated_sprite.modulate = Color(1.1, 1.1, 0.7) if is_selected else Color.WHITE
		)


func destroy() -> void:
	if is_destroyed:
		return
	is_destroyed   = true
	is_built       = false
	current_health = 0

	# ✅ Remove from every group joined in _ready
	remove_from_group("buildings")
	remove_from_group("generational_buildings")
	remove_from_group("mughal_buildings")
	remove_from_group("player_buildings")
	remove_from_group("enemy_buildings")

	# ✅ Stop all logic and physics
	set_process(false)
	set_physics_process(false)

	if construction_timer and not construction_timer.is_stopped():
		construction_timer.stop()

	if collision_shape:
		collision_shape.disabled = true
	if health_bar:
		health_bar.visible = false

	if ambient_particles:
		ambient_particles.emitting = false

	emit_signal("building_destroyed", self)
	print("💥 Taj Mahal destroyed!")

	# Destroyed animation — timer, NOT animation_finished
	if animated_sprite and animated_sprite.sprite_frames \
			and animated_sprite.sprite_frames.has_animation("destroyed"):
		animated_sprite.play("destroyed")
		var t := get_tree().create_timer(1.0)   # match your destroyed animation length
		await t.timeout
	else:
		var t := get_tree().create_timer(0.1)
		await t.timeout

	queue_free()

func update_damage_stage() -> void:
	var pct := float(current_health) / float(max_health)
	if pct <= 0.0:
		current_damage_stage = DamageStage.DESTROYED
		current_state        = TownState.DESTROYED
	elif pct <= 0.3:
		current_damage_stage = DamageStage.HEAVY_DAMAGE
		current_state        = TownState.DAMAGED
	elif pct <= 0.7:
		current_damage_stage = DamageStage.LIGHT_DAMAGE
		current_state        = TownState.DAMAGED
	else:
		current_damage_stage = DamageStage.NORMAL
		current_state        = TownState.IDLE
	update_damage_animation()

func update_damage_animation() -> void:
	if not is_built or is_destroyed or not animated_sprite: return
	if not animated_sprite.sprite_frames: return
	match current_damage_stage:
		DamageStage.NORMAL:
			if animated_sprite.sprite_frames.has_animation("idle"):
				animated_sprite.play("idle")
		DamageStage.LIGHT_DAMAGE:
			if animated_sprite.sprite_frames.has_animation("destruction1"):
				animated_sprite.play("destruction1")
		DamageStage.HEAVY_DAMAGE:
			if animated_sprite.sprite_frames.has_animation("destruction2"):
				animated_sprite.play("destruction2")



# ══════════════════════════════════════════════════════════════
#  GETTERS
# ══════════════════════════════════════════════════════════════
func is_operational() -> bool:
	return is_built and not is_destroyed

func get_health_percent() -> float:
	return float(current_health) / float(max_health) if max_health > 0 else 0.0

func get_owner_region() -> int:
	return owner_region

func get_status_text() -> String:
	if is_destroyed:  return "DESTROYED"
	if not is_built:  return "CONSTRUCTING"
	return "OPERATIONAL"
