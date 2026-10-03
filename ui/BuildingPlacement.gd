extends Node

# ===== PLACEMENT STATE =====
var placement_active: bool = false
var current_building_key: String = ""
var preview_node: Node2D = null

# ===== VALIDATION SETTINGS =====
const MIN_DISTANCE_FROM_BUILDINGS: float = 50.0
const MIN_DISTANCE_FROM_RESOURCES: float = 30.0
const MIN_DISTANCE_FROM_OTHER: float = 10.0

# ===== SIGNALS =====
signal placement_started(building_key: String)
signal placement_cancelled()
signal placement_confirmed(building_key: String, position: Vector2)

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

# ===== START PLACEMENT =====
func start_placement(building_key: String):
	print("🏗️ BuildingPlacement.start_placement called for: ", building_key)
	
	if placement_active:
		stop_placement()
	
	var scene_path = GameManager.get_building_scene_path(building_key)
	if scene_path.is_empty():
		print("❌ No scene path for: ", building_key)
		return
	
	var scene = load(scene_path)
	if not scene:
		print("❌ Failed to load scene: ", scene_path)
		return
	
	current_building_key = building_key
	placement_active = true
	
	# Create preview ghost
	preview_node = scene.instantiate()
	preview_node.modulate = Color(0.5, 1, 0.5, 0.6)
	preview_node.set_script(null)  # Disable scripts for preview
	
	# Disable collision on preview
	for child in preview_node.get_children():
		if child is CollisionShape2D or child is Area2D:
			child.set_deferred("disabled", true)
	
	# Add to scene
	get_tree().current_scene.add_child(preview_node)
	
	# Center on camera initially
	var camera = get_tree().current_scene.get_node_or_null("Camera2D")
	if camera:
		preview_node.global_position = camera.global_position
	
	emit_signal("placement_started", building_key)
	print("✅ Placement mode active for: ", building_key)

# ===== STOP PLACEMENT =====
func stop_placement():
	if preview_node:
		preview_node.queue_free()
		preview_node = null
	
	placement_active = false
	current_building_key = ""
	emit_signal("placement_cancelled")
	print("🛑 Placement mode stopped")

# ===== PROCESS - Update ghost position =====
func _process(_delta):
	if not placement_active or not preview_node:
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var world_pos = get_viewport().get_canvas_transform().affine_inverse() * mouse_pos
	preview_node.global_position = world_pos
	
	# Update color based on validity
	var can_place = _can_place_at_position(world_pos)
	if can_place:
		preview_node.modulate = Color(0.5, 1, 0.5, 0.6)  # Green
	else:
		preview_node.modulate = Color(1, 0.3, 0.3, 0.6)  # Red

# ===== INPUT HANDLING =====
func _input(event):
	if not placement_active:
		return
	
	# Left click - Try to place
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_place_building()
		get_viewport().set_input_as_handled()
	
	# Right click - Cancel
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		stop_placement()
		get_viewport().set_input_as_handled()
	
	# Escape key - Cancel
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		stop_placement()
		get_viewport().set_input_as_handled()

func _can_place_at_position(position: Vector2) -> bool:
	# Get the building's collision shape from the preview
	var my_region = GameManager.player_region if GameManager else 0
	if _is_in_foreign_tc_zone(position, my_region):
		return false
	var collision_shape = null
	for child in preview_node.get_children():
		if child is CollisionShape2D:
			collision_shape = child
			break	
	
	# If no collision shape found, fallback to center distance check
	if not collision_shape:
		return _simple_distance_check(position)
	
	# Create a shape query for overlap checking
	var space_state = get_tree().current_scene.get_world_2d().direct_space_state
	var shape = collision_shape.shape.duplicate()
	var transform = Transform2D(0, position)
	
	var params = PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = transform
	params.collision_mask = 1  # Layer 1 for buildings
	params.exclude = [preview_node]
	
	var results = space_state.intersect_shape(params)
	
	# Also check resource overlap
	var resource_params = PhysicsShapeQueryParameters2D.new()
	resource_params.shape = shape
	resource_params.transform = transform
	resource_params.collision_mask = 2  # Layer 2 for resources
	resource_params.exclude = [preview_node]
	
	var resource_results = space_state.intersect_shape(resource_params)
	
	# Also check if within map bounds
	var can_place = results.is_empty() and resource_results.is_empty()
	
	if not can_place:
		# Debug: print what's blocking
		for result in results:
			if result.collider:
				print("⚠️ Blocked by: ", result.collider.name)
	
	return can_place

func _simple_distance_check(position: Vector2) -> bool:
	# Fallback: center distance check
	var buildings = get_tree().get_nodes_in_group("buildings")
	for building in buildings:
		if is_instance_valid(building):
			var dist = building.global_position.distance_to(position)
			if dist < 50.0:
				return false
	
	var resources = get_tree().get_nodes_in_group("resources")
	for resource in resources:
		if is_instance_valid(resource):
			var dist = resource.global_position.distance_to(position)
			if dist < 30.0:
				return false
	
	return true

# ══════════════════════════════════════════════════════════════
#  TOWN CENTER NO-BUILD ZONE CHECK
#  Returns true if `pos` falls inside any TC's $Area2D circle
#  where that TC's region != builder_region.
# ══════════════════════════════════════════════════════════════
func _is_in_foreign_tc_zone(pos: Vector2, builder_region: int) -> bool:
	for tc in get_tree().get_nodes_in_group("town_centers"):
		if not is_instance_valid(tc):
			continue
		# Skip destroyed / still-under-construction TCs
		if "is_destroyed" in tc and tc.is_destroyed:
			continue
		if "is_built" in tc and not tc.is_built:
			continue

		# Read the TC's region
		var tc_region := -1
		if tc.has_meta("owner_region"):
			tc_region = int(tc.get_meta("owner_region"))
		elif "my_region" in tc:
			tc_region = int(tc.my_region)
		if tc_region == -1:
			continue

		# Same team → this zone doesn't block us
		if tc_region == builder_region:
			continue

		# Locate the TC's Area2D and its CollisionShape2D
		var area := tc.get_node_or_null("Area2D") as Area2D
		if not area:
			# Fallback: scan children for any Area2D
			for child in tc.get_children():
				if child is Area2D:
					area = child
					break
		if not area:
			continue

		var shape_node := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if not shape_node or not shape_node.shape:
			continue

		# Read the radius from the shape
		var radius := 0.0
		if shape_node.shape is CircleShape2D:
			radius = (shape_node.shape as CircleShape2D).radius
		elif shape_node.shape is RectangleShape2D:
			var s := (shape_node.shape as RectangleShape2D).size
			radius = max(s.x, s.y) * 0.5
		else:
			continue

		if radius <= 0.0:
			continue

		# Compare distance
		if tc.global_position.distance_to(pos) < radius:
			print("🚫 Blocked: inside ", tc.name,
				  "'s TC no-build zone (radius=", radius, ")")
			return true

	return false

func _get_placement_warning(position: Vector2) -> String:
	var my_region = GameManager.player_region if GameManager else 0
	if _is_in_foreign_tc_zone(position, my_region):
		return "🚫 Can't build inside enemy Town Center area!"
		
	# Get building footprint
	var footprint_size = Vector2(64, 64)
	var footprint_rect = Rect2(position - footprint_size / 2, footprint_size)
	
	var buildings = get_tree().get_nodes_in_group("buildings")
	for building in buildings:
		if is_instance_valid(building):
			var building_rect = Rect2(building.global_position - footprint_size / 2, footprint_size)
			var expanded_rect = Rect2(building.global_position - footprint_size / 2 - Vector2(10, 10), footprint_size + Vector2(20, 20))
			if footprint_rect.intersects(expanded_rect):
				return "⚠️ Too close to another building!"
	
	var resources = get_tree().get_nodes_in_group("resources")
	for resource in resources:
		if is_instance_valid(resource):
			var resource_rect = Rect2(resource.global_position - Vector2(30, 30), Vector2(60, 60))
			var expanded_rect = Rect2(resource.global_position - Vector2(40, 40), Vector2(80, 80))
			if footprint_rect.intersects(expanded_rect):
				return "⚠️ Too close to a resource!"
	
	return ""

# ══════════════════════════════════════════════════════════════
#  TOWN CENTER CAP HELPERS
#  Per-region cap (3 per empire). Uses ResourceManager's live count
#  of TC nodes in the world so it stays accurate even after
#  destruction / rebuilding.
# ══════════════════════════════════════════════════════════════
func _get_player_region() -> int:
	return GameManager.player_region if GameManager else 0

func _region_tc_count(region: int) -> int:
	if ResourceManager:
		return ResourceManager.get_region_tc_count(region)
	# Fallback — count nodes directly if ResourceManager is missing
	var n := 0
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
			n += 1
	return n

func _region_tc_cap() -> int:
	if ResourceManager:
		return ResourceManager.MAX_TOWN_CENTERS_PER_REGION
	return 3

## Returns true if the player can still place another TC in their region.
## Also shows a floating error if the cap is reached, and returns false.
func _can_place_town_center() -> bool:
	var region := _get_player_region()
	var current := _region_tc_count(region)
	var cap := _region_tc_cap()
	if current >= cap:
		print("🚫 [TC CAP] Region ", region, " already has ", current, "/", cap, " TCs")
		_notify_tc_cap(region, current, cap)
		return false
	return true

func _notify_tc_cap(region: int, current: int, cap: int) -> void:
	# Fire the same signal the population toast uses, but with a TC-specific
	# meta so the HUD can print the right message.
	if ResourceManager:
		ResourceManager.set_meta("last_cap_kind", "town_center")
		ResourceManager.set_meta("last_cap_current", current)
		ResourceManager.set_meta("last_cap_max", cap)
		ResourceManager.population_cap_reached.emit(region)

# ===== TRY TO PLACE BUILDING =====
func _try_place_building():
	if not preview_node:
		return
	
	var position = preview_node.global_position
	
	# ✅ TC CAP CHECK — must come BEFORE validity, affordability, and spending.
	if current_building_key == "hometown":
		if not _can_place_town_center():
			return
	
	if not _can_place_at_position(position):
		var warning = _get_placement_warning(position)
		_show_floating_message(warning, Color.ORANGE)
		return
	
	# Check if player can afford
	var data = GameManager.building_data[current_building_key]
	if not GameManager.can_afford(data["cost"]):
		_show_floating_message("❌ Cannot afford this building!", Color.RED)
		return
	
	# Place the building
	_place_building(position)

func _place_building(position: Vector2):
	print("📍 Placing building at: ", position)
	var data = GameManager.building_data[current_building_key]

	# Spend resources
	for res in data["cost"]:
		GameManager.spend_resource(res, data["cost"][res])
		print("  Spent: ", data["cost"][res], " ", res)

	var scene_path = GameManager.get_building_scene_path(current_building_key)
	var scene = load(scene_path)
	var building = scene.instantiate()

	# ✅ Stamp player ownership BEFORE add_child
	var player_region = GameManager.player_region if GameManager else 0
	building.set_meta("owner_region", player_region)

	building.global_position = position
	get_tree().current_scene.add_child(building)

	building.add_to_group("buildings")
	building.add_to_group("player_buildings")

	if current_building_key == "hometown":
		building.add_to_group("town_centers")
		var count := _region_tc_count(player_region)
		var cap := _region_tc_cap()
		print("🏛️ Town Center built. Region ", player_region,
			  " now has ", count, "/", cap)

	if data.get("generational", false):
		var result = GameManager.register_generational_building(current_building_key)
		print("  Generational result: ", result["message"])
		_show_floating_message(result["message"], Color.GOLD if result["success"] else Color.ORANGE)
	else:
		_show_floating_message("✅ " + current_building_key.replace("_", " ").capitalize() + " built!", Color.GREEN)

	emit_signal("placement_confirmed", current_building_key, position)
	stop_placement()

# ===== UI HELPERS =====
func _show_floating_message(text: String, color: Color):
	var label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_outline_modulate", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	
	# Add to a CanvasLayer for screen space
	var canvas = get_tree().current_scene.find_child("MainHUD", true, false)
	if canvas:
		canvas.add_child(label)
		var viewport_size = get_viewport().get_visible_rect().size
		label.position = Vector2(viewport_size.x / 2.0 - 100, viewport_size.y / 2.0)
	else:
		get_tree().root.add_child(label)
		label.position = Vector2(400, 300)
	
	var tween = label.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(label, "position", label.position - Vector2(0, 100), 1.5)
	tween.parallel().tween_property(label, "modulate", Color.TRANSPARENT, 1.5)
	await tween.finished
	label.queue_free()

# ===== CONFIRM PLACEMENT AT POSITION (for double-click) =====
func confirm_placement_at(position: Vector2):
	if not placement_active or not preview_node:
		return
	
	preview_node.global_position = position
	_try_place_building()
