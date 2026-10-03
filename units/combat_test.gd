# combat_test_clean.gd
extends Node2D

@export var samurai_scene: PackedScene
@export var enemy_scene: PackedScene

@onready var camera = $Camera2D

func _ready():
	print("🧹 CLEANING COMBAT TEST")
	
	# FIRST: Remove ALL existing CharacterBody2D nodes
	var nodes_to_remove = []
	for child in get_children():
		if child is CharacterBody2D:
			print("🗑️ Removing old node:", child.name)
			nodes_to_remove.append(child)
	
	for node in nodes_to_remove:
		node.queue_free()
	
	# Wait for cleanup
	await get_tree().process_frame
	print("✅ Scene cleaned")
	
	# NOW spawn fresh units
	var samurai = samurai_scene.instantiate()
	samurai.position = Vector2(200, 300)
	samurai.name = "Samurai"
	add_child(samurai)
	print("✅ Fresh Samurai at (200, 300)")
	
	var enemy = enemy_scene.instantiate()
	enemy.position = Vector2(600, 300)
	enemy.name = "Enemy"
	add_child(enemy)
	print("✅ Fresh Enemy at (600, 300)")
	
	# Camera setup
	if camera:
		camera.make_current()
		camera.global_position = samurai.global_position
	
	# Verify
	print("\n🔍 FINAL SCENE CHECK:")
	print("Children count:", get_child_count())
	for child in get_children():
		if child is CharacterBody2D:
			print("  -", child.name, "at", child.position)
	
	print("\n🎮 Move RIGHT to attack enemy at (600, 300)")
