# combat_test_fixed.gd
extends Node2D

@export var samurai_scene: PackedScene
@export var enemy_scene: PackedScene

func _ready():
	print("🎯 COMBAT TEST - DEBUG MODE")
	
	# Clear any existing units first
	for child in get_children():
		if child is CharacterBody2D:
			child.queue_free()
	
	# Spawn samurai ONLY ONCE
	var samurai = samurai_scene.instantiate()
	samurai.position = Vector2(300, 300)
	samurai.name = "PlayerSamurai"
	add_child(samurai)
	print("✅ Samurai instantiated")
	
	# Spawn enemy
	var enemy = enemy_scene.instantiate()
	enemy.position = Vector2(500, 300)
	enemy.name = "TestEnemy"
	add_child(enemy)
	print("✅ Enemy instantiated")
	
	# DEBUG: List all nodes in scene
	print("\n📋 SCENE TREE:")
	for node in get_tree().get_nodes_in_group(""):
		print("  -", node.name, " | Type:", node.get_class(), " | Groups:", node.get_groups())
	
	# DEBUG: Specifically check for enemies
	print("\n🔍 LOOKING FOR ENEMIES IN GROUP:")
	var enemies = get_tree().get_nodes_in_group("enemy")
	print("Found", enemies.size(), "enemies in 'enemy' group:")
	for e in enemies:
		print("  -", e.name, " at position:", e.position)
	
	# If no enemies found, add them manually
	if enemies.size() == 0:
		print("⚠️ No enemies in group! Adding enemy to group...")
		for child in get_children():
			if "Enemy" in child.name:
				child.add_to_group("enemy")
				print("✅ Added", child.name, "to 'enemy' group")
	
	print("\n🎮 PRESS 'A' TO ATTACK")
