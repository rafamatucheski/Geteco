extends SceneTree

class Actor extends CharacterBody2D:
	var armor := 0
	var grants := 0
	func add_armor(amount: int) -> void:
		armor = mini(100, armor + amount)
		grants += 1

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
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 5
	actor.add_child(shape)
	world.add_child(actor)
	var item = load("res://legacy/city_demo/scenes/pickups/BodyArmorPickup.tscn").instantiate()
	world.add_child(item)
	for i in 3: await physics_frame
	var ok: bool = actor.armor == 0
	var fixed_position: Vector2 = item.position
	var angle: float = item._art_root.rotation
	await create_timer(0.05).timeout
	ok = ok and item.position == fixed_position and item._art_root.rotation != angle
	actor.position = Vector2.ZERO
	for i in 5: await physics_frame
	ok = ok and actor.armor == 50 and actor.grants == 1
	await create_timer(0.4).timeout
	ok = ok and not is_instance_valid(item)
	# A drop appearing under the player must also grant armor exactly once.
	var dropped = load("res://legacy/city_demo/scenes/pickups/BodyArmorPickup.tscn").instantiate()
	world.add_child(dropped)
	for i in 5: await physics_frame
	ok = ok and actor.armor == 100 and actor.grants == 2
	await create_timer(0.7).timeout
	print("ARMOR WALK-OVER PICKUP: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
