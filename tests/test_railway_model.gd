extends SceneTree
const MODEL = preload("res://world/railway/TrainModel.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var train := MODEL.new()
	world.add_child(train)
	await physics_frame
	await physics_frame
	var space := world.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.7
	capsule.radius = .32
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY, MODEL.PASSENGER_FOOT + Vector3.UP * .9)
	check(space.intersect_shape(query).is_empty(), "passenger capsule free including roof/head clearance")
	var floor_ray := PhysicsRayQueryParameters3D.create(MODEL.PASSENGER_FOOT + Vector3.UP * .3, MODEL.PASSENGER_FOOT - Vector3.UP * .2, 1)
	var hit := space.intersect_ray(floor_ray)
	check(not hit.is_empty() and absf(hit.position.y - .83) < .001, "passenger floor supported at .83 metres")
	query.transform.origin = Vector3(.89, 1.74, 1.8)
	check(not space.intersect_shape(query).is_empty(), "full chair volume blocks standing capsule")
	var window := PhysicsRayQueryParameters3D.create(MODEL.WINDOW_EYE, Vector3(2,2.35,-2.2), 1)
	check(space.intersect_ray(window).is_empty(), "window camera ray exits real opening")
	var actor := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = .9
	actor.collision_mask = 1
	actor.collision_layer = 2
	actor.add_child(shape)
	world.add_child(actor)
	actor.position = Vector3(0,.84,1.8)
	await physics_frame
	var collision := actor.move_and_collide(Vector3(3,0,0))
	check(collision != null and actor.position.x < .25, "swept movement cannot pass through seat")
	actor.position = Vector3(0,.84,0)
	await physics_frame
	var aisle := actor.move_and_collide(Vector3(0,0,3))
	check(aisle == null, "human capsule travels along unobstructed centre aisle")
	check(train.solids.size() > 25, "classified coach and engine solid inventory present")
	print("TRAIN_MODEL_RESULT failures=", failures)
	world.queue_free()
	quit(1 if failures else 0)
