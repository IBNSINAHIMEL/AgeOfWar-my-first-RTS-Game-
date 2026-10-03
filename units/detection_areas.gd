# detection_area.gd
extends Area2D

@export var detection_range = 1000.0
@export var team = "player"

var units_in_range = []

func _ready():
	# Create collision shape
	var collision_shape = CollisionShape2D.new()
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = detection_range
	collision_shape.shape = circle_shape
	add_child(collision_shape)
	
	# Set collision
	collision_layer = 1
	collision_mask = 1
	monitoring = true
	monitorable = true
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	print(get_parent().name, " Detection ready - Range: ", detection_range)

func _on_body_entered(body):
	print("🔴 ", get_parent().name, " BODY ENTERED: ", body.name, " (", body.get_class(), ")")
	
	# Try to find the unit
	var unit = null
	if body.has_method("get_team"):
		unit = body
	elif body.get_parent() and body.get_parent().has_method("get_team"):
		unit = body.get_parent()
		print("  Found parent unit: ", unit.name)
	
	if unit and unit.has_method("get_team"):
		var body_team = unit.get_team()
		print("  Unit team: ", body_team, " | My team: ", team)
		
		if body_team != team:
			if unit not in units_in_range:
				units_in_range.append(unit)
				print("  ✅✅✅ ENEMY DETECTED! ✅✅✅")
				if get_parent().has_method("enemy_detected"):
					get_parent().enemy_detected(unit)
	else:
		print("  Not a unit - ignoring")

func _on_body_exited(body):
	var unit = null
	if body.has_method("get_team"):
		unit = body
	elif body.get_parent() and body.get_parent().has_method("get_team"):
		unit = body.get_parent()
	
	if unit and unit in units_in_range:
		units_in_range.erase(unit)
		if get_parent().has_method("enemy_left"):
			get_parent().enemy_left(unit)

func get_closest_enemy():
	var closest = null
	var closest_dist = INF
	
	for enemy in units_in_range:
		if is_instance_valid(enemy):
			var dist = global_position.distance_to(enemy.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = enemy
	
	return closest
