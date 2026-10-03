extends Control

# ══════════════════════════════════════════════════════════════
#  MONGOL TOWN CENTER UI
#  - Preserves manual editor layout (no anchor / position overrides)
#  - No _setup_ui_style() interference
#  - Reads gift state from the building (single source of truth)
# ══════════════════════════════════════════════════════════════

# ===== NODE PATHS =====
@onready var background = $Background
@onready var title_label = get_node_or_null("TitleBar/MongolTownCenter")

@onready var health_bar      = get_node_or_null("BuildingStatus/HealthBar")
@onready var era_label       = get_node_or_null("BuildingStatus/EraLabel")
@onready var condition_label = get_node_or_null("BuildingStatus/ConditionLabel")

@onready var train_button     = get_node_or_null("VillagerSpawnSection/TrainButton")
@onready var populace_label   = get_node_or_null("VillagerSpawnSection/PopulaceLabel")
@onready var cooldown_bar     = get_node_or_null("VillagerSpawnSection/CooldownBar")

@onready var gen_1_button          = get_node_or_null("GenerationBonusSection/Gen1Button")
@onready var gen_2_button          = get_node_or_null("GenerationBonusSection/Gen2Button")
@onready var gen_3_button          = get_node_or_null("GenerationBonusSection/Gen3Button")
@onready var milestone_hint_label  = get_node_or_null("GenerationBonusSection/MilestoneHint")

@onready var close_button = $CloseButton

# ===== INSTANCE TRACKERS =====
var target_building: Node = null
var is_producing: bool = false
var production_timer: float = 0.0
const PRODUCTION_DURATION: float = 2.0
var update_timer: Timer

# ===== INITIALIZATION =====
func _ready():
	# ⚠️ NO _setup_ui_style() call — the editor-designed layout is preserved as-is.
	_connect_signals()
	visible = false
	if cooldown_bar:
		cooldown_bar.visible = false

	update_timer = Timer.new()
	update_timer.wait_time = 0.05
	update_timer.timeout.connect(_on_update_timer_tick)
	add_child(update_timer)

func _connect_signals():
	if train_button and not train_button.pressed.is_connected(_on_train_pressed):
		train_button.pressed.connect(_on_train_pressed)

	if gen_1_button and not gen_1_button.pressed.is_connected(_on_milestone_pressed.bind(1)):
		gen_1_button.pressed.connect(_on_milestone_pressed.bind(1))
	if gen_2_button and not gen_2_button.pressed.is_connected(_on_milestone_pressed.bind(2)):
		gen_2_button.pressed.connect(_on_milestone_pressed.bind(2))
	if gen_3_button and not gen_3_button.pressed.is_connected(_on_milestone_pressed.bind(3)):
		gen_3_button.pressed.connect(_on_milestone_pressed.bind(3))

	if close_button and not close_button.pressed.is_connected(hide_ui):
		close_button.pressed.connect(hide_ui)

# ===== PER-FRAME UI REFRESH =====
func _process(_delta: float) -> void:
	if visible and is_instance_valid(target_building):
		update_ui()

func _on_update_timer_tick():
	if not is_producing or not target_building:
		return
	production_timer -= 0.05
	if cooldown_bar:
		cooldown_bar.value = (PRODUCTION_DURATION - production_timer) / PRODUCTION_DURATION

	if production_timer <= 0.0:
		is_producing = false
		if cooldown_bar:
			cooldown_bar.visible = false
		update_timer.stop()
		_complete_production()

# ===== SHOW / HIDE =====
func show_ui(building_node: Node):
	if not is_instance_valid(building_node):
		return
	if is_instance_valid(target_building) and target_building != building_node:
		target_building.deselect()

	target_building = building_node
	visible = true
	_connect_signals()
	update_ui()
	print("🏯 Mongol Command Panel Activated")

func hide_ui():
	visible = false
	if is_producing:
		is_producing = false
		update_timer.stop()

	# ═══════════════════════════════════════════════════════════
	# ✅ DO NOT call target_building.deselect() here — that creates
	#    infinite recursion because TC.deselect() calls hide_ui().
	#    Just clear the reference.
	# ═══════════════════════════════════════════════════════════
	target_building = null

	print("🏯 Mongol Command Panel Dismissed")
# ===== MAIN UI UPDATE =====
func update_ui():
	if not is_instance_valid(target_building) or not visible:
		return

	# 1. Health
	var hp_pct: float = 1.0
	if target_building.has_method("get_health_percent"):
		hp_pct = target_building.get_health_percent()
		if hp_pct > 1.0: hp_pct /= 100.0
	if health_bar:
		health_bar.max_value = 1.0
		health_bar.value     = hp_pct
		health_bar.modulate  = Color.GREEN if hp_pct > 0.6 else (Color.ORANGE if hp_pct > 0.28 else Color.RED)

	# 2. Condition
	if condition_label and target_building.has_method("get_status_text"):
		condition_label.text = "Condition: " + target_building.get_status_text()

	# 3. Era
	var current_era = 0
	if target_building.has_method("get_current_generation"):
		current_era = target_building.get_current_generation()
		if era_label:
			era_label.text = "⚡ Era Milestone: " + str(current_era) + " / 3"

	# 4. Population
	if populace_label and target_building.has_method("get_villager_counts"):
		var census = target_building.get_villager_counts()
		populace_label.text = "👥 Populace: %d (♂️ %d | ♀️ %d)" % [
			census["total"], census["male"], census["female"]]

	# 5. Train button
	if train_button and target_building.has_method("get_food"):
		if is_producing:
			train_button.disabled = true
			train_button.text     = "⏳ Training Subject..."
		else:
			var budget = target_building.get_food()
			train_button.text     = "⚒️ Train (Cost: 100 Food | Treasury: %d)" % budget
			train_button.disabled = false

	_render_milestone_buttons(current_era)

# ===== MILESTONE BUTTON RENDERING =====
func _render_milestone_buttons(current_era: int):
	var button_set = [gen_1_button, gen_2_button, gen_3_button]

	for i in range(3):
		var target_rank = i + 1
		var target_btn  = button_set[i]
		if not target_btn:
			continue

		# ✅ Read claim state from the BUILDING (single source of truth)
		var claimed := false
		if is_instance_valid(target_building) and "claimed_generations" in target_building:
			claimed = target_building.claimed_generations.get(target_rank, false)

		if claimed:
			target_btn.disabled = true
			target_btn.text     = "✓ Era " + str(target_rank) + " Claimed"
			target_btn.modulate = Color(0.5, 0.5, 0.5)
		elif target_rank <= current_era:
			target_btn.disabled = false
			target_btn.modulate = Color.WHITE
			match target_rank:
				1: target_btn.text = "🎁 Claim Era 1: 8 Swordsmen"
				2: target_btn.text = "🎁 Claim Era 2: 8 Horse Archers"
				3: target_btn.text = "🎁 Claim Era 3: 4 Flaming Arrows"
		else:
			target_btn.disabled = true
			target_btn.modulate = Color(0.4, 0.4, 0.4)
			match target_rank:
				1: target_btn.text = "🔒 Build Porcelain Tower"
				2: target_btn.text = "🔒 Build Confunction Academy"
				3: target_btn.text = "🔒 Build Great Buddha"

	if milestone_hint_label:
		match current_era:
			0:
				milestone_hint_label.text     = "✨ Build Porcelain Tower to advance to Era 1 ✨"
				milestone_hint_label.modulate = Color.CYAN
			1:
				milestone_hint_label.text     = "⚔️ Era 1 Unlocked! Claim your 8 Swordsmen! ⚔️"
				milestone_hint_label.modulate = Color.YELLOW
			2:
				milestone_hint_label.text     = "🏹 Era 2 Unlocked! Claim your 8 Horse Archers! 🏹"
				milestone_hint_label.modulate = Color.ORANGE
			3:
				milestone_hint_label.text     = "🔥 Final Era Unlocked! Claim your Flaming Arrows! 🔥"
				milestone_hint_label.modulate = Color.GOLD

# ===== INTERACTION =====
func _on_train_pressed():
	if is_producing or not is_instance_valid(target_building):
		return

	var can_afford := true
	if target_building.has_method("can_afford_food_cost"):
		can_afford = target_building.can_afford_food_cost()
	elif target_building.has_method("get_food"):
		can_afford = target_building.get_food() >= 100

	if not can_afford:
		_display_feedback("❌ Insufficient Food! Need 100.", Color.RED)
		return

	if target_building.has_method("spawn_villager"):
		is_producing     = true
		production_timer = PRODUCTION_DURATION
		if cooldown_bar:
			cooldown_bar.visible   = true
			cooldown_bar.max_value = 1.0
			cooldown_bar.value     = 0.0
		if train_button:
			train_button.disabled = true
			train_button.text     = "⏳ Training Subject..."
		update_timer.start()

func _complete_production():
	if target_building and target_building.has_method("spawn_villager"):
		var success = target_building.spawn_villager()
		if success:
			_display_feedback("✨ New Subject Has Arrived! ✨", Color.GREEN)
			_visual_effect_at_button()
	update_ui()
	if train_button:
		train_button.disabled = false
		train_button.text     = "⚒️ Train Subject (Cost: 100 Food)"

func _on_milestone_pressed(tier: int):
	print("🎯 Milestone pressed for tier ", tier)
	if not is_instance_valid(target_building):
		print("❌ No target building")
		return
	if not target_building.has_method("get_current_generation"):
		print("❌ No get_current_generation method")
		return

	var current_era = target_building.get_current_generation()

	if current_era < tier:
		_display_feedback("⚠️ Build the generational building first!", Color.ORANGE)
		return

	# Read claimed state from the BUILDING, not local cache
	var already_claimed := false
	if "claimed_generations" in target_building:
		already_claimed = target_building.claimed_generations.get(tier, false)

	if already_claimed:
		_display_feedback("⚠️ Gift already claimed!", Color.ORANGE)
		return

	if target_building.has_method("trigger_generation_bonus"):
		var outcome = target_building.trigger_generation_bonus(tier)
		print("Outcome of trigger_generation_bonus: ", outcome)
		if outcome:
			var reward_desc = ["", "8 Swordsmen", "8 Horse Archers", "4 Flaming Arrows"]
			_display_feedback("🎉 Era %d Gift Claimed! %s Joined! 🎉" % [tier, reward_desc[tier]], Color.GOLD)
			_celebration_ripple()
			update_ui()

# ===== UI FEEDBACK EFFECTS =====
func _display_feedback(message: String, text_color: Color):
	var msg := Label.new()
	msg.text = message
	msg.position = Vector2(80, 200)
	msg.add_theme_color_override("font_color", text_color)
	msg.add_theme_font_size_override("font_size", 18)
	add_child(msg)

	var drift := create_tween()
	drift.tween_property(msg, "position", msg.position - Vector2(0, 45), 1.2)
	drift.parallel().tween_property(msg, "modulate", Color.TRANSPARENT, 1.2)
	drift.tween_callback(msg.queue_free)

func _visual_effect_at_button():
	if not train_button:
		return
	var spark := Label.new()
	spark.text = "+1 🧑‍🌾"
	spark.position = train_button.position + Vector2(20, -15)
	spark.add_theme_color_override("font_color", Color.LIME_GREEN)
	add_child(spark)
	var flight := create_tween()
	flight.tween_property(spark, "position", spark.position - Vector2(0, 30), 0.8)
	flight.parallel().tween_property(spark, "modulate", Color.TRANSPARENT, 0.8)
	flight.tween_callback(spark.queue_free)

func _celebration_ripple():
	if not background:
		return
	for wave in range(12):
		var glitter := Label.new()
		glitter.text = ["✨", "⭐", "🎉", "🌸"][randi() % 4]
		glitter.position = Vector2(randf_range(20, 280), randf_range(20, 180))
		background.add_child(glitter)
		var motion := create_tween()
		motion.tween_property(glitter, "position", glitter.position + Vector2(0, -40), 1.0)
		motion.parallel().tween_property(glitter, "modulate", Color.TRANSPARENT, 1.0)
		motion.tween_callback(glitter.queue_free)
