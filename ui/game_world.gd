extends Node2D

# ══════════════════════════════════════════════════════════════
#  GAME WORLD CONTROLLER – Age of Empires Style
#  PC + Android  |  Godot 4.6+ Integrated Setup
# ══════════════════════════════════════════════════════════════

@onready var camera          = $Camera2D
@onready var bases_container = $Bases
@onready var resources_node  = $Resources

# ─── Platform ────────────────────────────────────────────────
var is_mobile: bool = false

# ─── Selection ───────────────────────────────────────────────
var selected_units: Array    = []
var selection_box:  ColorRect = null

# ─── PC Drag-box ─────────────────────────────────────────────
var mouse_start:  Vector2 = Vector2.ZERO
var is_dragging:  bool    = false
const DRAG_THRESHOLD: float = 8.0

# Playable area in world coordinates.
# Set these to match the visible green rectangle of your tilemap.
@export var play_left:   float = -6800.0
@export var play_right:  float =  16000.0
@export var play_top:    float = -5900.0
@export var play_bottom: float =  5000.0
# Playable area — set these in the Inspector to match your tilemap's
# visible green rectangle. These are WORLD coordinates, not tiles.

# ─── PC Multi-click (AoE style) ──────────────────────────────
var last_click_time:   float  = 0.0
var last_clicked_unit: Node2D = null
var click_count:       int    = 0
const MULTI_CLICK_TIME: float = 0.35

# ─── PC Camera Movement ──────────────────────────────────────
var edge_scroll_margin: int   = 30
var keyboard_pan_speed: float = 600.0

# ─── Middle-Mouse Pan ────────────────────────────────────────
var mmb_panning: bool = false

# ─── Touch / Mobile Controls ─────────────────────────────────
var touch_points:          Dictionary = {}
var initial_zoom:          float      = 1.0
var initial_distance:      float      = 0.0
var is_panning:            bool       = false
var touch_click_count:     int        = 0
var touch_last_click_time: float      = 0.0
var touch_last_unit:       Node2D     = null
const TOUCH_MULTI_TAP_TIME: float = 0.4

# ─── Zoom Boundaries ─────────────────────────────────────────
var zoom_speed: float = 0.1
var min_zoom:   float = 0.4
var max_zoom:   float = 2.5

# ─── Game Data Cache ─────────────────────────────────────────
var player_region: int    = 0
var enemy_regions: Array  = []
var difficulty:    String = ""

# ─── Camera Bounds (Dynamic tile tracking) ───────────────────
var map_left:   float = -7000.0
var map_right:  float =  2000.0
var map_top:    float = -4000.0
var map_bottom: float =  2000.0

# ─── Smooth Camera Jump ──────────────────────────────────────
var cam_jump_target: Vector2 = Vector2.ZERO
var cam_is_jumping:  bool    = false
const CAM_JUMP_SPEED: float  = 8.0   # Lerp speed multiplier

# ══════════════════════════════════════════════════════════════
#  READY & RUNTIME SYSTEM INITIALIZATION
# ══════════════════════════════════════════════════════════════
func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("game_world")

	# ✅ Make every non-UI child respect pause (units, buildings, AI, resources)
	for child in get_children():
		_mark_child_pausable(child)
	child_entered_tree.connect(_on_child_entered_tree)

	is_mobile = OS.get_name() == "Android" or OS.get_name() == "iOS"
	print("Platform Registered: ", "Mobile" if is_mobile else "PC")

	_load_game_data()
	print("🧭 [DEBUG] Player region from GameData = ", player_region)
	_setup_existing_town_centers()
	_setup_existing_resources()
	_setup_camera_bounds_from_tilemap()
	_setup_camera()
	_apply_difficulty_settings()
	_setup_selection_box()

	cam_jump_target = camera.global_position

	call_deferred("_late_init")
	_initialize_resource_collectors()
	_initialize_builders()

	await get_tree().create_timer(2.0).timeout
	debug_all_collisions()

	print("═".repeat(50))
	print(" Castle Map Core Framework Loaded Successfully")
	print(" Player Active Region : ", _get_region_name(player_region))
	print(" Engine Camera Location : ", camera.global_position)
	print("═".repeat(50))
		
func _late_init():
	_connect_ui_auto_positioning()
func _initialize_resource_collectors():
	# Get enemy regions from GameData
	var enemy_regions = GameData.get_enemy_regions() if GameData else [1, 2]
	print("🧪 [DEBUG] enemy_regions from GameData: ", enemy_regions)
	
	# If empty, use fallback
	if enemy_regions.is_empty():
		enemy_regions = [1, 2]
		print("🧪 [DEBUG] Using fallback enemy_regions: ", enemy_regions)
	
	var villager_scene_paths = {
		0: "res://scenes/units/japanese_villager.tscn",
		1: "res://scenes/units/indian_villager.tscn",
		2: "res://scenes/units/mongolian_villager.tscn",
	}
	
	for region in enemy_regions:
		print("🧪 [DEBUG] Looking for town center for region: ", region)
		var tc = _get_enemy_town_center(region)
		if not tc:
			print("🧪 [DEBUG] ❌ No town center found for region: ", region)
			continue
		
		print("🧪 [DEBUG] ✅ Town center found for region: ", region, " - ", tc.name)
		
		# Create the node
		var collector = AIResourceGatherer.new()
		collector.name = "ResourceCollector_Region_" + str(region)
		add_child(collector)
		
		var scene_path = villager_scene_paths.get(region, "")
		collector.setup(region, tc, scene_path)
		print("🧺 Resource Collector initialized for region ", region)
# ══════════════════════════════════════════════════════════════
#  CORE RENDERING MANIPULATION & INTERACTION SETUP
# ══════════════════════════════════════════════════════════════
func _initialize_builders():
	var enemy_regions = GameData.get_enemy_regions() if GameData else [1, 2]
	
	for region in enemy_regions:
		var tc = _get_enemy_town_center(region)
		if not tc:
			continue
		
		var builder = AI_Builder.new()
		builder.name = "Builder_Region_" + str(region)
		add_child(builder)
		builder.setup(region, tc)
		print("🏗️ AI Builder initialized for region ", region)
func _setup_selection_box():
	selection_box         = ColorRect.new()
	selection_box.color   = Color(0.3, 0.7, 1.0, 0.25)
	selection_box.visible = false
	var cl = CanvasLayer.new()
	cl.layer = 10
	add_child(cl)
	cl.add_child(selection_box)
func _get_enemy_town_center(region: int):
	for tc in get_tree().get_nodes_in_group("town_centers"):
		if not is_instance_valid(tc):
			continue
		if tc.is_in_group("enemy_buildings"):
			var parent = tc.get_parent()
			if parent:
				var name_lower = parent.name.to_lower()
				if (region == 0 and "japanese" in name_lower) or \
				   (region == 1 and "mughal" in name_lower) or \
				   (region == 2 and "mongol" in name_lower):
					return tc
	return null
func _setup_camera_bounds_from_tilemap():
	# Camera limits = play area + small padding so the edge tiles aren't
	# hidden under the HUD. The play_* values are the source of truth.
	const PAD := 0.0   # set to 200.0 if you want a little slack around the edge

	map_left   = play_left   - PAD
	map_right  = play_right  + PAD
	map_top    = play_top    - PAD
	map_bottom = play_bottom + PAD

	print("🗺️ Play area:    L=%d R=%d T=%d B=%d" % [play_left, play_right, play_top, play_bottom])
	print("🗺️ Camera limits: L=%d R=%d T=%d B=%d" % [map_left, map_right, map_top, map_bottom])
func _setup_camera():
	if not camera: return
	camera.make_current()
	camera.limit_left   = int(map_left)
	camera.limit_right  = int(map_right)
	camera.limit_top    = int(map_top)
	camera.limit_bottom = int(map_bottom)

	var tc_pos = _get_player_hometown_position()
	camera.global_position = tc_pos
	camera.zoom            = Vector2(1.0, 1.0)

func _on_child_entered_tree(node: Node) -> void:
	# Defer 1 frame so the new node's _ready() runs and groups get populated
	call_deferred("_mark_child_pausable", node)


func _mark_child_pausable(node: Node) -> void:
	if not is_instance_valid(node):
		return

	# Leave these two running so the HUD + camera still work while paused
	if node.name == "main_game_ui":
		return
	if node is Camera2D:
		return

	# Everything else (units, buildings, AI, resources, timers)
	# → freeze the instant the tree is paused
	node.process_mode = Node.PROCESS_MODE_PAUSABLE

func _setup_existing_town_centers():
	if not bases_container: return
	print("🔎 [_setup_existing_town_centers] player_region=", player_region,
		  " enemy_regions=", enemy_regions, " difficulty=", difficulty)
	for base in bases_container.get_children():
		var tc: Node = null
		for child in base.get_children():
			var cn = child.name.to_lower()
			if cn.contains("hometown") or cn.contains("towncenter") or \
			   cn.contains("town_center") or child is StaticBody2D:
				tc = child
				break
		if not tc:
			print("   ⚠️ No TC child found in ", base.name)
			continue

		var region = -1
		var bn = base.name.to_lower()
		if   bn.contains("japanese"): region = 0
		elif bn.contains("mughal"):   region = 1
		elif bn.contains("mongol"):   region = 2

		if region == -1:
			print("   ⚠️ Unknown base name: ", base.name)
			continue

		# ✅ CRITICAL: stamp ownership on the TC node itself
		tc.set_meta("owner_region", region)
		if "owner_region" in tc:
			tc.set("owner_region", region)

		if region == player_region:
			tc.remove_from_group("enemy_buildings")
			tc.add_to_group("player_buildings")
			tc.add_to_group("town_centers")
			tc.add_to_group("buildings")
			print("   ✅ PLAYER TC: ", base.name, " region=", region)
		else:
			var should_show = (difficulty == "2v1") or (region in enemy_regions)
			if should_show:
				tc.add_to_group("enemy_buildings")
				tc.add_to_group("town_centers")
				tc.add_to_group("buildings")
				tc.remove_from_group("player_buildings")
				print("   ✅ ENEMY TC: ", base.name, " region=", region)
			else:
				tc.visible = false
				tc.set_process_mode(Node.PROCESS_MODE_DISABLED)
				for t in tc.find_children("*", "Timer", true, false):
					(t as Timer).stop()
				print("   🚫 HIDDEN TC: ", base.name, " region=", region)
func _setup_existing_resources():
	if resources_node:
		_find_and_group_resources(resources_node)

func _find_and_group_resources(parent: Node):
	for child in parent.get_children():
		if child is StaticBody2D:
			var nl = child.name.to_lower()
			if   nl.contains("tree"):  child.add_to_group("trees");  child.add_to_group("resources")
			elif nl.contains("bush"):  child.add_to_group("bushes"); child.add_to_group("resources")
			elif nl.contains("stone"): child.add_to_group("stones"); child.add_to_group("resources")
		if child.get_child_count() > 0:
			_find_and_group_resources(child)
## Returns the playable world rectangle in world coordinates.
## Used by the minimap and the placement validation.
func get_play_bounds() -> Rect2:
	return Rect2(
		Vector2(play_left, play_top),
		Vector2(play_right - play_left, play_bottom - play_top)
	)
func _load_game_data():
	if GameData:
		player_region = GameData.get_user_region()
		enemy_regions = GameData.get_enemy_regions()
		difficulty = GameData.get_difficulty()
		if GameManager:
			GameManager.player_region = player_region
			
	else:
		print("⚠️ GameData not found! Using default region 0.")		

func _apply_difficulty_settings():
	if difficulty == "2v1" and GameManager:
		GameManager.add_resource("food", 500)
		GameManager.add_resource("wood", 500)
		GameManager.add_resource("coin", 200)

# ══════════════════════════════════════════════════════════════
#  ★ PUBLIC API – INTEGRATED HOOKS FOR MAIN_GAME_UI.GD
# ══════════════════════════════════════════════════════════════

## Pans camera view instantly over your base via structural center point vectors
func center_camera_on_hometown() -> void:
	jump_to_player_hometown()

## Fetch base positioning calculations using standard system regions
func _get_town_center_position(target_region: int) -> Vector2:
	for tc in get_tree().get_nodes_in_group("town_centers"):
		var base_node = tc.get_parent()
		if base_node:
			var bn = base_node.name.to_lower()
			if target_region == 0 and bn.contains("japanese"): return tc.global_position
			if target_region == 1 and bn.contains("mughal"):   return tc.global_position
			if target_region == 2 and bn.contains("mongol"):   return tc.global_position
	return _get_player_hometown_position()

## Smoothly translate camera transform elements
func jump_to_player_hometown() -> void:
	cam_jump_target = _get_player_hometown_position()
	cam_is_jumping  = true

## Determines building spawn preview locations depending on active input modes
func get_building_spawn_position() -> Vector2:
	if is_mobile:
		return camera.global_position
	return get_global_mouse_position()

## Ensures any Control UI container context stays clamped inside viewing rectangles
func ensure_panel_in_viewport(panel: Control) -> void:
	if not is_instance_valid(panel) or not panel.visible: return

	var vp = get_viewport().get_visible_rect()
	var sz = panel.size if panel.size.length() > 20 else Vector2(420, 320)

	var in_canvas_layer = false
	var p = panel.get_parent()
	while p:
		if p is CanvasLayer: in_canvas_layer = true; break
		p = p.get_parent()

	const SAFE_TOP:    float = 85.0
	const SAFE_BOTTOM: float = 110.0

	var cx = clamp((vp.size.x - sz.x) * 0.5, 8.0, vp.size.x - sz.x - 8.0)
	var cy = clamp(SAFE_TOP + (vp.size.y - SAFE_TOP - SAFE_BOTTOM - sz.y) * 0.5, SAFE_TOP, vp.size.y - SAFE_BOTTOM - sz.y)

	if in_canvas_layer:
		panel.position = Vector2(cx, cy)
	else:
		panel.global_position = camera.global_position + Vector2(cx, cy) - vp.size * 0.5

func get_viewport_world_rect() -> Rect2:
	var vp   = get_viewport().get_visible_rect()
	var half = vp.size * 0.5 / camera.zoom.x
	return Rect2(camera.global_position - half, vp.size / camera.zoom.x)

# ══════════════════════════════════════════════════════════════
#  UI LAYOUT CONTAINER SIGNAL ROUTERS
# ══════════════════════════════════════════════════════════════
func _connect_ui_auto_positioning():
	var ui = get_node_or_null("main_game_ui")
	if not ui: ui = find_child("main_game_ui", true, false)
	if not ui: return

	for child in ui.get_children():
		if child is Control:
			if not child.is_connected("visibility_changed", _on_panel_visible.bind(child)):
				child.connect("visibility_changed", _on_panel_visible.bind(child))
		for sub in child.get_children():
			if sub is Control:
				if not sub.is_connected("visibility_changed", _on_panel_visible.bind(sub)):
					sub.connect("visibility_changed", _on_panel_visible.bind(sub))

func _on_panel_visible(panel: Control):
	if panel.visible:
		call_deferred("ensure_panel_in_viewport", panel)

# ══════════════════════════════════════════════════════════════
#  INTERNAL ENGINE GEOMETRIC UTILITIES
# ══════════════════════════════════════════════════════════════
func _get_region_name(r: int) -> String:
	match r:
		0: return "Japanese Empire"
		1: return "Mughal Empire"
		2: return "Mongol Empire"
	return "Unknown"

func _get_player_hometown_position() -> Vector2:
	for tc in get_tree().get_nodes_in_group("town_centers"):
		if tc.is_in_group("player_buildings"):
			return tc.global_position

	if bases_container:
		for base in bases_container.get_children():
			var bn = base.name.to_lower()
			var matches: bool = \
				(player_region == 0 and bn.contains("japanese")) or \
				(player_region == 1 and bn.contains("mughal"))   or \
				(player_region == 2 and bn.contains("mongol"))
			if not matches: continue

			for child in base.get_children():
				var cn = child.name.to_lower()
				if cn.contains("hometown") or cn.contains("towncenter") or cn.contains("town_center"):
					return child.global_position
			return base.global_position

	return Vector2.ZERO

func _clamp_camera():
	camera.position.x = clamp(camera.position.x, map_left,  map_right)
	camera.position.y = clamp(camera.position.y, map_top,   map_bottom)

func _clamp_zoom():
	var clamped_x = clamp(camera.zoom.x, min_zoom, max_zoom)
	var clamped_y = clamp(camera.zoom.y, min_zoom, max_zoom)
	camera.zoom = Vector2(clamped_x, clamped_y)

func _screen_to_world(s: Vector2) -> Vector2:
	var vp = get_viewport().get_visible_rect().size
	return camera.global_position + (s - vp * 0.5) / camera.zoom.x

func toggle_pause_game():
	var pp = find_child("*PausePanel*", true, false)
	if not pp: pp = get_node_or_null("CanvasLayer/PausePanel")
	var next = not get_tree().paused
	get_tree().paused = next
	if pp: pp.visible = next

# ══════════════════════════════════════════════════════════════
#  GLOBAL INPUT SYSTEM DISPATCHERS
# ══════════════════════════════════════════════════════════════
func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			toggle_pause_game()
			return
		if not is_mobile and event.keycode == KEY_H:
			jump_to_player_hometown()
			return

	if not camera: return

	if is_mobile:
		_handle_touch_input(event)
	else:
		_handle_pc_input(event)
# ══════════════════════════════════════════════════════════════
#  PC HARDWARE CAPTURE (MOUSE + KEYBOARD)
# ══════════════════════════════════════════════════════════════
func _handle_pc_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_issue_command(get_global_mouse_position())
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			mouse_start = event.position
			is_dragging = false
		else:
			if is_dragging and event.position.distance_to(mouse_start) > DRAG_THRESHOLD:
				_end_drag_selection()
			else:
				_handle_pc_click(get_global_mouse_position())
			is_dragging = false
			if selection_box: selection_box.visible = false
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		mmb_panning = event.pressed
		return

	if event is InputEventMouseMotion and mmb_panning:
		camera.position -= event.relative / camera.zoom.x
		_clamp_camera()
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom += Vector2(zoom_speed, zoom_speed)
			_clamp_zoom()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom -= Vector2(zoom_speed, zoom_speed)
			_clamp_zoom()
		return

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if event.position.distance_to(mouse_start) > DRAG_THRESHOLD:
			is_dragging = true
		if is_dragging:
			_update_drag_box(mouse_start, event.position)

func _handle_pc_click(world_pos: Vector2):
	var now  = Time.get_ticks_msec() / 1000.0
	var unit = _get_unit_at_position(world_pos)   # Already filters out enemy units
	
	if now - last_click_time <= MULTI_CLICK_TIME and unit == last_clicked_unit and unit != null:
		click_count += 1
	else:
		click_count = 1
	last_click_time   = now
	last_clicked_unit = unit
	
	match click_count:
		1:
			if unit and unit.is_in_group("player_units"):
				_clear_selection()
				_select_unit(unit)
			else:
				_clear_selection()
		2:
			if unit and unit.is_in_group("player_units"):
				_select_nearby_same_type(world_pos, unit)
		3:
			_select_all_combat_units()
			click_count = 0
func _update_drag_box(s: Vector2, e: Vector2):
	if not selection_box: return
	var r = Rect2(s, e - s).abs()
	selection_box.position = r.position
	selection_box.size      = r.size
	selection_box.visible   = true

func _end_drag_selection():
	var vp   = get_viewport().get_visible_rect()
	var zoom = camera.zoom.x
	var tl   = camera.global_position + (mouse_start - vp.size * 0.5) / zoom
	var br   = camera.global_position + (get_viewport().get_mouse_position() - vp.size * 0.5) / zoom
	var rect = Rect2(tl, br - tl).abs()
	_clear_selection()
	for u in get_tree().get_nodes_in_group("player_units"):
		if rect.has_point(u.global_position): _select_unit(u)

# ══════════════════════════════════════════════════════════════
#  UPDATES LOOPS (CAMERA PANS + JUMPS RENDERING)
# ══════════════════════════════════════════════════════════════
func _process(delta: float):
	if not camera: return

	if cam_is_jumping:
		var t = min(CAM_JUMP_SPEED * delta, 0.25)
		camera.global_position = camera.global_position.lerp(cam_jump_target, t)
		if camera.global_position.distance_to(cam_jump_target) < 4.0:
			camera.global_position = cam_jump_target
			cam_is_jumping = false
		
	if not selected_units.is_empty():
		selected_units = selected_units.filter(func(u): return is_instance_valid(u))
			
	
		
	if not is_mobile:
		_pc_camera_movement(delta)
		
	if BuildingPlacement.placement_active and BuildingPlacement.preview_node:
		var can_place = BuildingPlacement._can_place_at_position(BuildingPlacement.preview_node.global_position)
		if can_place:
			BuildingPlacement.preview_node.modulate = Color(0.5, 1, 0.5, 0.6)
		else:
			BuildingPlacement.preview_node.modulate = Color(1, 0.3, 0.3, 0.6)
		  
func _draw():
	if BuildingPlacement.placement_active and BuildingPlacement.preview_node:
		var pos = BuildingPlacement.preview_node.global_position
		draw_circle(pos, 30, Color(0, 1, 0, 0.3))
func _pc_camera_movement(delta: float):
	var move = Vector2.ZERO
	var vp   = get_viewport().get_visible_rect()
	var mp   = get_viewport().get_mouse_position()

	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  move.y += 1

	if get_window().has_focus() and vp.has_point(mp):
		if mp.x <= edge_scroll_margin:               move.x -= 1
		elif mp.x >= vp.size.x - edge_scroll_margin: move.x += 1
		if mp.y <= edge_scroll_margin:               move.y -= 1
		elif mp.y >= vp.size.y - edge_scroll_margin: move.y += 1

	if move != Vector2.ZERO:
		cam_is_jumping = false
		camera.position += move.normalized() * (keyboard_pan_speed / camera.zoom.x) * delta
		_clamp_camera()

# ══════════════════════════════════════════════════════════════
#  MOBILE CAPTURE MECHANICS (PINCH & SWIPE ZOOM)
# ══════════════════════════════════════════════════════════════
func _handle_touch_input(event):
	if event is InputEventScreenTouch and event.pressed:
		touch_points[event.index] = event.position

		if event.index == 0:
			var wp   = _screen_to_world(event.position)
			var now  = Time.get_ticks_msec() / 1000.0
			var unit = _get_unit_at_position(wp)
			if unit and unit.is_in_group("enemy_units"):
				return

			if now - touch_last_click_time <= TOUCH_MULTI_TAP_TIME and unit == touch_last_unit and unit != null:
				touch_click_count += 1
			else:
				touch_click_count = 1
			touch_last_click_time = now
			touch_last_unit       = unit

			match touch_click_count:
				1:
					if unit and unit.is_in_group("player_units"):
						if selected_units.is_empty(): _clear_selection(); _select_unit(unit)
						else: _issue_command(wp)
					elif not selected_units.is_empty(): _issue_command(wp)
					else: _clear_selection()
				2:
					if unit and unit.is_in_group("player_units"):
						_select_nearby_same_type(wp, unit)
				3:
					_select_all_combat_units(); touch_click_count = 0
		return

	if event is InputEventScreenTouch and not event.pressed:
		touch_points.erase(event.index)
		if touch_points.is_empty():
			is_panning = false; initial_distance = 0.0
		return

	if event is InputEventScreenDrag:
		touch_points[event.index] = event.position

		if touch_points.size() == 2:
			var pts  = touch_points.values()
			var dist = pts[0].distance_to(pts[1])
			if initial_distance == 0.0:
				initial_distance = dist; initial_zoom = camera.zoom.x
			else:
				var z = initial_zoom * (initial_distance / dist)
				camera.zoom = Vector2(z, z)
				_clamp_zoom()
			if event.index == 0:
				camera.position -= event.relative / camera.zoom.x; _clamp_camera()

		elif touch_points.size() == 1 and event.index == 0:
			if selected_units.is_empty():
				camera.position -= event.relative / camera.zoom.x; _clamp_camera()

# ══════════════════════════════════════════════════════════════
#  UNIT BEHAVIOR ACTION DISPATCHERS
# ══════════════════════════════════════════════════════════════
func _issue_command(world_pos: Vector2) -> void:
	# Clean dead units first
	selected_units = selected_units.filter(func(u): return is_instance_valid(u))

	if selected_units.is_empty():
		return

	var clicked_building = _get_building_at_position(world_pos)

	# Don't attack our own buildings
	if clicked_building and clicked_building.is_in_group("player_buildings"):
		return

	# Priority 1: enemy building
	if clicked_building and clicked_building.is_in_group("enemy_buildings"):
		for u in selected_units:
			if not is_instance_valid(u): continue     # ← guard
			if u.has_method("attack"):
				u.attack(clicked_building)
		return

	# Priority 2: enemy unit
	var enemy = _get_enemy_at_position(world_pos)
	if enemy:
		for u in selected_units:
			if not is_instance_valid(u): continue     # ← guard
			if u.has_method("attack"):
				u.attack(enemy)
		return

	# Priority 3: resource
	var resource = _get_resource_at_position(world_pos)
	if resource:
		for u in selected_units:
			if not is_instance_valid(u): continue     # ← guard
			if u.has_method("collect"):
				u.collect(resource)
		return

	# Priority 4: move
	for u in selected_units:
		if not is_instance_valid(u): continue         # ← guard
		if u.has_method("move_to"):
			u.move_to(world_pos)
func _get_building_at_position(pos: Vector2) -> Node2D:
	return _closest("buildings", pos, 45.0)
# ══════════════════════════════════════════════════════════════
#  GROUP ENGINE ASSIGNMENTS HELPERS
# ══════════════════════════════════════════════════════════════
func _select_unit(unit: Node2D):
	if unit not in selected_units:
		selected_units.append(unit)
		if unit.has_method("set_selected"): unit.set_selected(true)

func _clear_selection():
	for u in selected_units:
		if is_instance_valid(u) and u.has_method("set_selected"): u.set_selected(false)
	selected_units.clear()

func _select_nearby_same_type(world_pos: Vector2, center: Node2D):
	var ut = center.get("unit_type") if "unit_type" in center else "villager"
	_clear_selection()
	for u in get_tree().get_nodes_in_group("player_units"):
		var t = u.get("unit_type") if "unit_type" in u else "villager"
		if t == ut and u.global_position.distance_to(world_pos) <= 250.0:
			_select_unit(u)

func _select_all_combat_units():
	_clear_selection()
	for u in get_tree().get_nodes_in_group("player_units"):
		var t = u.get("unit_type") if "unit_type" in u else "villager"
		if t != "villager": _select_unit(u)

# ══════════════════════════════════════════════════════════════
#  SPATIAL QUERIES
# ══════════════════════════════════════════════════════════════
func _get_unit_at_position(pos: Vector2) -> Node2D:
	# ✅ Only return player-owned units
	var all_units = get_tree().get_nodes_in_group("player_units")
	var best: Node2D = null
	var bd = 45.0
	
	for unit in all_units:
		# Skip enemy units
		if unit.is_in_group("enemy_units"):
			continue
		var d = unit.global_position.distance_to(pos)
		if d < bd:
			bd = d
			best = unit
	return best
func _get_enemy_at_position(pos: Vector2)    -> Node2D: return _closest("enemy_units",  pos, 45.0)
func _get_resource_at_position(pos: Vector2) -> Node2D: return _closest("resources",    pos, 45.0)

func _closest(group: String, pos: Vector2, max_d: float) -> Node2D:
	var best: Node2D = null
	var bd          = max_d
	for n in get_tree().get_nodes_in_group(group):
		var d = n.global_position.distance_to(pos)
		if d < bd: bd = d; best = n
	return best

# ══════════════════════════════════════════════════════════════
#  BUILDING PLACEMENT ENGINE
# ══════════════════════════════════════════════════════════════
# in game_world.gd

func get_map_bounds() -> Rect2:
	return Rect2(
		Vector2(map_left,  map_top),
		Vector2(map_right - map_left, map_bottom - map_top)
	)
# in game_world.gd

func clamp_to_map(pos: Vector2, margin: float = 24.0) -> Vector2:
	var r := get_map_bounds()
	return Vector2(
		clamp(pos.x, r.position.x + margin, r.end.x - margin),
		clamp(pos.y, r.position.y + margin, r.end.y - margin)
	)	
## Main handler for building construction placement routines
func handle_building_placement(building_key: String, target_position: Vector2) -> void:
	# ✅ TC cap gate — must run FIRST, before any scene is loaded or cost paid.
	# Uses the live per-region count from ResourceManager, not the stale
	# GameManager.town_center_count which is never incremented.
	if building_key == "hometown":
		var pr := GameManager.player_region if GameManager else 0
		if ResourceManager.get_region_tc_count(pr) >= ResourceManager.MAX_TOWN_CENTERS_PER_REGION:
			print("🚨 Placement refused: region ", pr,
				  " already has ", ResourceManager.get_region_tc_count(pr),
				  "/", ResourceManager.MAX_TOWN_CENTERS_PER_REGION, " TCs")
			return

	var path = GameManager.get_building_scene_path(building_key)
	if path.is_empty():
		print("❌ No scene path for building: ", building_key)
		return
	var scene_resource = load(path)
	if not scene_resource:
		print("❌ Failed to load building scene: ", path)
		return

	var new_building = scene_resource.instantiate()

	# ✅ Stamp player ownership BEFORE add_child
	var player_region = GameManager.player_region if GameManager else 0
	new_building.set_meta("owner_region", player_region)

	new_building.global_position = target_position
	add_child(new_building)

	new_building.add_to_group("buildings")
	new_building.add_to_group("player_buildings")

	if building_key == "hometown":
		new_building.add_to_group("town_centers")
		var count := ResourceManager.get_region_tc_count(player_region)
		var cap := ResourceManager.MAX_TOWN_CENTERS_PER_REGION
		print("🏛️ Town Center placed. Region ", player_region,
			  " now has ", count, "/", cap)
## Shortcut helper for explicit town center instantiation
func place_town_center(position: Vector2) -> void:
	handle_building_placement("hometown", position)
func debug_all_collisions():
	print("\n" + "=".repeat(50))
	print("🔍 FULL COLLISION DEBUG")
	print("=".repeat(50))
	
	# Check villagers
	print("\n🧑 VILLAGERS:")
	for unit in get_tree().get_nodes_in_group("player_units"):
		print("   ", unit.name)
		print("      Layer: ", unit.collision_layer)
		print("      Mask: ", unit.collision_mask)
		var shape = unit.get_node_or_null("CollisionShape2D")
		print("      Has CollisionShape: ", shape != null)
	
	# Check buildings
	print("\n🏛️ BUILDINGS:")
	for building in get_tree().get_nodes_in_group("buildings"):
		print("   ", building.name)
		print("      Layer: ", building.collision_layer)
		var shape = building.get_node_or_null("CollisionShape2D")
		print("      Has CollisionShape: ", shape != null)
	
	# Check resources
	print("\n🌲 RESOURCES:")
	for res in get_tree().get_nodes_in_group("resources"):
		print("   ", res.name)
		print("      Layer: ", res.collision_layer)
		var shape = res.get_node_or_null("CollisionShape2D")
		print("      Has CollisionShape: ", shape != null)
	
	print("=".repeat(50))	
# Call this to check collision setup on all objects
