extends SceneTree

class Actor extends CharacterBody2D:
	var collectibles_found: Array[String] = []
	func add_collectible(id: String, _label: String, _at: Vector2 = Vector2.ZERO) -> bool:
		if id.is_empty() or id in collectibles_found: return false
		collectibles_found.append(id)
		return true

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var actor := Actor.new()
	actor.collision_layer = 4
	actor.collision_mask = 0
	actor.position = Vector2(100, 0)
	actor.add_to_group("player")
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 5
	actor.add_child(shape)
	world.add_child(actor)
	var item := preload("res://economy/Collectible.gd").new()
	item.collectible_id = "physics_pickup"
	world.add_child(item)
	await physics_frame
	actor.position = Vector2.ZERO
	for i in 5: await physics_frame
	var ok := actor.collectibles_found == ["physics_pickup"] and item._is_collected
	print("COLLECTIBLE PHYSICS PICKUP: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
