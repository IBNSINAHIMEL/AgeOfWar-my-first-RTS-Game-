# mughal_barracks_ui.gd — robust version (variadic bug fixed)
extends Control

# ══════════════════════════════════════════════════════════════
#  UI NODE REFERENCES (null-safe + find_child fallback)
#  NOTE: scene uses "SwardsMan" (capital M) for the button but
#        "Swardsman" (lowercase m) for the labels. Both handled.
# ══════════════════════════════════════════════════════════════
var pikeman_button:   Button = null
var swordsman_button: Button = null
var archer_button:    Button = null
var close_button:     Button = null

var training_progress: ProgressBar = null
var title_label:       Label = null

var pikeman_name:    Label = null
var swordsman_name:  Label = null
var archer_name:     Label = null

var pikeman_cost:    Label = null
var swordsman_cost:  Label = null
var archer_cost:     Label = null

var pikeman_stats:   Label = null
var swordsman_stats: Label = null
var archer_stats:    Label = null

# ===== STATE =====
var target_building: Node = null
var _is_connected: bool = false
var _poll_timer: Timer

# ==============================================================
func _ready() -> void:
	# Render on top
	z_index = 100
	z_as_relative = false
	var p = get_parent()
	if p is CanvasLayer:
		p.layer = 10

	visible = false

	_cache_nodes()
	_connect_internal_signals()

	if training_progress:
		training_progress.visible = false

	# Poll so button state stays honest while building is training
	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.1
	_poll_timer.timeout.connect(_on_poll_tick)
	add_child(_poll_timer)
	_poll_timer.start()

	print("🏰 MughalBarracksUI ready | pikeman=", pikeman_button,
		  " | swordsman=", swordsman_button,
		  " | archer=", archer_button,
		  " | close=", close_button,
		  " | progress=", training_progress)


func _cache_nodes() -> void:
	# Buttons
	pikeman_button   = _find_button(["PikemanButton"])
	swordsman_button = _find_button(["SwardsManButton", "SwordsmanButton"])
	archer_button    = _find_button(["ArcherButton"])
	close_button     = _find_button(["CloseButton"])

	# Progress bar
	training_progress = _find_by_name(["TrainingProgress", "ProgressBar"]) as ProgressBar

	# Title (nested under TitlePanel)
	title_label = _find_by_name(["Title"]) as Label

	# Names
	pikeman_name   = _find_by_name(["PikemanName"]) as Label
	swordsman_name = _find_by_name(["SwardsmanName", "SwordsmanName"]) as Label
	archer_name    = _find_by_name(["ArcherName"]) as Label

	# Costs
	pikeman_cost   = _find_by_name(["PikemanCostLabel"]) as Label
	swordsman_cost = _find_by_name(["SwardsmanCostLabel", "SwordsmanCostLabel"]) as Label
	archer_cost    = _find_by_name(["ArcherCostLabel"]) as Label

	# Stats
	pikeman_stats   = _find_by_name(["PikemanStatsLabel"]) as Label
	swordsman_stats = _find_by_name(["SwardsmanStatsLabel", "SwordsmanStatsLabel"]) as Label
	archer_stats    = _find_by_name(["ArcherStatsLabel"]) as Label


# Finds first node whose name matches any of the supplied candidates.
# Takes an Array (NOT variadic) to avoid passing a nested array into get_node_or_null.
func _find_by_name(candidates: Array) -> Node:
	# 1) Try direct child by name
	for n in candidates:
		var direct = get_node_or_null(String(n))
		if direct:
			return direct
	# 2) Fall back to deep find_child
	for n in candidates:
		var found = find_child(String(n), true, false)
		if found:
			return found
	return null


func _find_button(candidates: Array) -> Button:
	return _find_by_name(candidates) as Button


# ══════════════════════════════════════════════════════════════
#  SIGNAL CONNECTIONS
# ══════════════════════════════════════════════════════════════
func _connect_internal_signals() -> void:
	if _is_connected:
		return
	if pikeman_button and not pikeman_button.pressed.is_connected(_on_pikeman_pressed):
		pikeman_button.pressed.connect(_on_pikeman_pressed)
	if swordsman_button and not swordsman_button.pressed.is_connected(_on_swordsman_pressed):
		swordsman_button.pressed.connect(_on_swordsman_pressed)
	if archer_button and not archer_button.pressed.is_connected(_on_archer_pressed):
		archer_button.pressed.connect(_on_archer_pressed)
	if close_button and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)
	_is_connected = true


# ══════════════════════════════════════════════════════════════
#  PUBLIC API (called by MughalBarrack)
# ══════════════════════════════════════════════════════════════
func show_ui(building: Node) -> void:
	if not is_instance_valid(building):
		return
	target_building = building
	visible = true
	update_display()
	print("🏰 Mughal Barracks UI shown")


func hide_ui() -> void:
	visible = false
	if training_progress:
		training_progress.visible = false
	target_building = null
	print("🏰 Mughal Barracks UI hidden")


# ══════════════════════════════════════════════════════════════
#  DISPLAY
# ══════════════════════════════════════════════════════════════
func update_display() -> void:
	if not is_instance_valid(target_building):
		return

	var data: Dictionary = {}
	if target_building.has_method("get_ui_data"):
		data = target_building.get_ui_data()

	if title_label:    title_label.text    = data.get("title", "Barracks")

	if pikeman_name:   pikeman_name.text   = data.get("pikeman_name",   "Pikeman")
	if swordsman_name: swordsman_name.text = data.get("swordsman_name", "Swordsman")
	if archer_name:    archer_name.text    = data.get("archer_name",    "Archer")

	if pikeman_cost:   pikeman_cost.text   = data.get("pikeman_cost_text",   "")
	if swordsman_cost: swordsman_cost.text = data.get("swordsman_cost_text", "")
	if archer_cost:    archer_cost.text    = data.get("archer_cost_text",    "")

	if pikeman_stats:   pikeman_stats.text   = data.get("pikeman_stats",   "")
	if swordsman_stats: swordsman_stats.text = data.get("swordsman_stats", "")
	if archer_stats:    archer_stats.text    = data.get("archer_stats",    "")

	var operational: bool = data.get("is_operational", false)
	var training:    bool = data.get("is_training",    false)

	var can_click := operational and not training
	if pikeman_button:   pikeman_button.disabled   = not can_click
	if swordsman_button: swordsman_button.disabled = not can_click
	if archer_button:    archer_button.disabled    = not can_click


# ══════════════════════════════════════════════════════════════
#  POLL (keeps UI honest during awaits)
# ══════════════════════════════════════════════════════════════
func _on_poll_tick() -> void:
	if not visible or not is_instance_valid(target_building):
		return
	update_display()


# ══════════════════════════════════════════════════════════════
#  BUTTON HANDLERS
# ══════════════════════════════════════════════════════════════
func _on_pikeman_pressed() -> void:
	if not is_instance_valid(target_building): return
	if target_building.has_method("request_train_pikeman"):
		target_building.request_train_pikeman()
	if pikeman_button:   pikeman_button.disabled   = true
	if swordsman_button: swordsman_button.disabled = true
	if archer_button:    archer_button.disabled    = true


func _on_swordsman_pressed() -> void:
	if not is_instance_valid(target_building): return
	if target_building.has_method("request_train_swordsman"):
		target_building.request_train_swordsman()
	if pikeman_button:   pikeman_button.disabled   = true
	if swordsman_button: swordsman_button.disabled = true
	if archer_button:    archer_button.disabled    = true


func _on_archer_pressed() -> void:
	if not is_instance_valid(target_building): return
	if target_building.has_method("request_train_archer"):
		target_building.request_train_archer()
	if pikeman_button:   pikeman_button.disabled   = true
	if swordsman_button: swordsman_button.disabled = true
	if archer_button:    archer_button.disabled    = true


func _on_close_pressed() -> void:
	if is_instance_valid(target_building) and target_building.has_method("deselect"):
		target_building.call_deferred("deselect")
	else:
		hide_ui()


# ══════════════════════════════════════════════════════════════
#  PROGRESS BAR (called by MughalBarrack)
# ══════════════════════════════════════════════════════════════
func set_progress(value: float, max_value: float) -> void:
	if training_progress:
		training_progress.visible   = true
		training_progress.max_value = max_value
		training_progress.value     = value


func hide_progress() -> void:
	if training_progress:
		training_progress.visible = false
		training_progress.value   = 0


# MughalBarrack polls this to refresh the bar
func get_training_progress_node() -> ProgressBar:
	return training_progress
