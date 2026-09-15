extends SceneTree
var failures: Array[String] = []
var world: Node2D
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)
func solid(point: Vector2,size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = point
	var visible_shape := Polygon2D.new()
	visible_shape.polygon = PackedVector2Array([-size*.5,Vector2(size.x,-size.y)*.5,size*.5,Vector2(-size.x,size.y)*.5])
	body.add_child(visible_shape)
	var collision := CollisionPolygon2D.new()
	collision.polygon = visible_shape.polygon
	body.add_child(collision)
	world.add_child(body)
func run() -> void:
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("NPCMedicalCare").set_process(false)
	root.get_node("WantedManager").set_process(false)
	var unit := CharacterBody2D.new()
	unit.position = Vector2(-500,-500)
	var hull := CollisionShape2D.new()
	hull.name = "CollisionShape2D"
	hull.shape = RectangleShape2D.new()
	hull.shape.size = Vector2(100,46)
	unit.add_child(hull)
	world.add_child(unit)
	var target := Node2D.new()
	target.position = Vector2(170,160)
	world.add_child(target)
	# A U open to the right: no direct or single-elbow route from the rear
	# staging point can reach the patient, but the complete team fits around it.
	solid(Vector2(100,160),Vector2(10,150))
	solid(Vector2(160,90),Vector2(130,10))
	solid(Vector2(160,230),Vector2(130,10))
	await physics_frame
	await physics_frame
	var planner := preload("res://world/shared/emergency/AmbulanceApproach.gd").new()
	var accepted := false
	var yielded := false
	for frame in 600:
		accepted = planner.service_clear(unit,target,Transform2D.IDENTITY)
		yielded = yielded or planner._walk_pending
		if accepted or not planner._walk_pending: break
		await process_frame
	check(yielded,"Parking route search yields between frames")
	check(accepted,"Parking can authorize a real multi-corner route for the full team")
	var right_exit := false
	var clear := true
	solid(Vector2.ZERO,Vector2(100,46))
	await physics_frame
	await physics_frame
	var circle := CircleShape2D.new()
	circle.radius = 34
	for i in range(1,planner.walk_route.size()):
		var a: Vector2 = planner.walk_route[i-1]
		var b: Vector2 = planner.walk_route[i]
		right_exit = right_exit or b.x>259
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = circle
		query.transform.origin = a
		query.motion = b-a
		query.collision_mask = 1
		var space := unit.get_world_2d().direct_space_state
		clear = clear and space.intersect_shape(query,1).is_empty() and space.cast_motion(query)[0] == 1
	check(accepted and right_exit and clear,"Route goes through the opening and sweeps clear of walls and the future parked hull")
	planner.reset()
	await process_frame
	check(unit.get_child_count()==1,"Parking probe is released without invisible colliders or renderers")
	print("MEDICAL_PARKING_WALK failures=",failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
