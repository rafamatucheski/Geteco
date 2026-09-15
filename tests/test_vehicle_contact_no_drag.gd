extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func body_at(world: Node, point: Vector2) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 2
	var hull := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(20,20)
	hull.shape = shape
	body.add_child(hull)
	world.add_child(body)
	body.position = point
	preload("res://VehicleMotionSafety.gd").configure(body)
	return body

func run() -> void:
	var safety = load("D:/geteco/artifacts/combat-vehicles-0913/before/VehicleMotionSafety.gd") if "--before" in OS.get_cmdline_user_args() else preload("res://VehicleMotionSafety.gd")
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var parked := body_at(world, Vector2.ZERO)
	var police := body_at(world, Vector2(-30,0))
	var peak := 0.0
	var contacts := 0
	for i in 90:
		await physics_frame
		police.velocity = Vector2(120,0)
		police.move_and_slide()
		parked.velocity = Vector2(0.1,0)
		safety.move(parked)
		peak = maxf(peak, parked.velocity.length())
		contacts += parked.get_slide_collision_count()
	check(contacts > 0, "moving viatura contacts coasting vehicle")
	check(peak <= 0.101, "contact cannot inject viatura velocity; peak=" + str(peak))
	parked.velocity = Vector2.ZERO
	var stopped := parked.position
	for i in 30:
		await physics_frame
		safety.move(parked)
	check(parked.position.distance_to(stopped) < 0.001, "parked vehicle stays parked after contact")
	police.position = Vector2(300,0)
	parked.position = Vector2(320,23)
	(police.get_child(0).shape as RectangleShape2D).size = Vector2(60,20)
	police.get_child(0).name = "CollisionShape2D"
	await physics_frame
	if "--before" in OS.get_cmdline_user_args():
		police.rotation = 0.6
	else:
		safety.rotate_clear(police, 0.6)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = police.get_child(0).shape
	query.transform = police.global_transform
	query.collision_mask = 2
	query.exclude = [police.get_rid()]
	check(police.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(), "viatura turn cannot overlap parked motorcycle hull")
	parked.position = Vector2(700,0)
	await physics_frame
	if not "--before" in OS.get_cmdline_user_args():
		safety.rotate_clear(police, 0.6)
		check(is_equal_approx(police.rotation,0.6), "viatura still turns when space is clear")
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
