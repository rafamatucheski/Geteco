extends SceneTree

var failures := 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var hospital = load("res://world/harbor/hospital/HarborHospital.gd").new()
	hospital.name = "Clinic"
	hospital.footprint = Vector2(260, 230)
	hospital.building_kind = "hospital"
	world.add_child(hospital)
	await physics_frame
	await physics_frame
	# These points lie on the visible north roof, beyond the ground footprint.
	for point in [Vector2(-50, -145), Vector2(80, -140), Vector2(-50, 0)]:
		var query := PhysicsPointQueryParameters2D.new()
		query.position = point
		query.collision_mask = 1
		if world.get_world_2d().direct_space_state.intersect_point(query).is_empty():
			failures += 1
			print("FAIL roof is walkable at ", point)
	# Actual swept body motion must stop at the north edge of both wards.
	var actor := CharacterBody2D.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 9
	shape.shape = circle
	actor.add_child(shape)
	world.add_child(actor)
	for x in [-50.0, 80.0]:
		actor.position = Vector2(x, -210)
		await physics_frame
		var hit := actor.move_and_collide(Vector2(0, 90))
		if hit == null or actor.position.y > -150:
			failures += 1
			print("FAIL north approach crosses roof at ", actor.position)
	print("HOSPITAL_ROOF_GEODATA failures=", failures)
	quit(0 if failures == 0 else 1)
