extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var depot := preload("res://world/harbor/HarborStorageArt.gd").new()
	depot.position = Vector2(320, 240)
	world.add_child(depot)
	await process_frame
	var cargo := get_nodes_in_group("physical_cargo")
	check(cargo.size() == 11, "Each floor load has an independent body; stacked cargo has one support")
	var wood: CharacterBody2D
	var metal: CharacterBody2D
	for body in cargo:
		if body.cargo_material == "wood": wood = body
		if body.cargo_material == "metal" and body.mass_kg == 24.0: metal = body
	check(wood != null and metal != null, "Both wood and drums are physical")
	if wood == null or metal == null:
		quit(1)
		return
	var old_position: Vector2 = metal.position
	metal.receive_vehicle_impact(20, Vector2.RIGHT)
	for i in 10: await physics_frame
	check(metal.position.distance_to(old_position) > 0.1, "Gentle contact moves a barrel")
	check(metal.dent == 0.0, "Gentle contact does not dent metal")
	metal.receive_vehicle_impact(240, Vector2.RIGHT)
	check(metal.dent > 0.0 and not metal.broken and metal.collision_layer != 0, "Hard impact dents metal and retains solid remains")
	check(metal.view.model.scale.x < 1.0, "Damage changes the visible model")
	wood.push_by_person(Vector2.LEFT, 120)
	check(wood.velocity.x < 0, "People can push cargo")
	wood.take_damage(100, true)
	check(wood.broken and wood.collision_layer == 0, "Damage breaks wood and removes blocking collision")
	var debris: Node2D
	for child in depot.get_children():
		if child.get_script() == preload("res://guns/ImpactDebris.gd"):
			debris = child
	check(debris != null, "Broken wood leaves fragments")
	if debris != null:
		check(not debris.z_as_relative and debris.z_index < 8, "Fragments stay below cars despite the depot Z layer")
		check(not debris is CollisionObject2D, "Cars can drive over fragments")
		for i in 240: debris._process(1.0 / 60.0)
		for piece in debris.pieces:
			check(piece.h == 0.0 and piece.up == 0.0, "Wood settles on the ground after bouncing")
	var wall := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(10, 300)
	collision.shape = rectangle
	wall.add_child(collision)
	wall.position = metal.global_position + Vector2(45, 0)
	world.add_child(wall)
	metal.velocity = Vector2(300, 0)
	for i in 30: await physics_frame
	check(metal.global_position.x < wall.position.x, "Moving cargo cannot pass through a wall")
	if not DisplayServer.get_name() == "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/storage-physics.png")
	print("Storage physics: ", failures, " failures")
	quit(failures)
