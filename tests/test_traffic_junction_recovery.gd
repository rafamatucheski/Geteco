extends SceneTree

class Authority:
	extends Node2D
	var graph_source: Node
	var reservation_vehicle: Node
	func evaluate_lane_motion(vehicle: Node, _path: Path2D, _follow: PathFollow2D, advance: float, _length: float, _speed: float, _braking: float) -> Dictionary:
		return {"controlled": true, "reservation_granted": vehicle == reservation_vehicle, "allowed_advance": advance if vehicle == reservation_vehicle else 0.0, "target_speed": INF if vehicle == reservation_vehicle else 0.0}

var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures += 1
func lane(world: Node, start: Vector2, finish: Vector2) -> Path2D:
	var path := Path2D.new()
	path.curve = Curve2D.new()
	path.curve.add_point(start)
	path.curve.add_point(finish)
	world.add_child(path)
	return path
func block(world: Node, at: Vector2) -> StaticBody2D:
	var obstacle := StaticBody2D.new()
	obstacle.position = at
	obstacle.collision_layer = 4
	var hull := CollisionShape2D.new()
	hull.shape = CircleShape2D.new()
	hull.shape.radius = 10.0
	obstacle.add_child(hull)
	world.add_child(obstacle)
	return obstacle
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var road := lane(world, Vector2.ZERO, Vector2(1000, 0))
	var cross := lane(world, Vector2(300, -300), Vector2(300, 500))
	var owner := ModernTrafficFactory.spawn_moving_vehicle(road, "Owner", "taxi_yellow", 0.2, 75, 0)
	var other := ModernTrafficFactory.spawn_moving_vehicle(cross, "Yielding", "taxi_yellow", 0.375, 75, 0)
	var authority := Authority.new()
	authority.graph_source = world
	authority.reservation_vehicle = owner
	world.add_child(authority)
	for car in [owner, other]:
		car.set_process(false)
		car.set_physics_process(false)
		car._junction_traffic_controller = authority
		car._lane_motion_initialized = true
		car._lane_motion_speed = 0.0
		car._last_lane_motion_contract = {"controlled": true, "reservation_granted": car == owner}
	var follow := other.get_parent() as PathFollow2D
	var initial := follow.progress
	await physics_frame
	await physics_frame
	check(not owner._accept_clearance_request(other), "Waiting stream cannot order reservation owner to retreat")
	var rear := block(world, other.global_position - other.global_transform.x * 50.0)
	await physics_frame
	await physics_frame
	check(not other._accept_clearance_request(owner), "Vehicle refuses reverse when a pedestrian occupies its rear clearance")
	rear.queue_free()
	await physics_frame
	await physics_frame
	var lowest := initial
	var overlap := false
	for frame in 780:
		await physics_frame
		owner.advance_on_lane(1.0 / 60.0)
		other.advance_on_lane(1.0 / 60.0)
		lowest = minf(lowest, follow.progress)
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = owner.collision.shape
		query.transform = owner.collision.global_transform
		query.collision_mask = 2
		query.exclude = [owner.get_rid()]
		overlap = overlap or not world.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()
	check(lowest < initial - 20.0, "Blocked junction automatically requests and performs a short reverse")
	check(lowest >= initial - 48.1, "Reverse stays bounded instead of repeatedly backing down the road")
	check(owner.global_position.x > 450.0, "Reservation owner physically exits the blocked junction")
	check(not overlap, "Recovery keeps the two vehicle hulls separated")
	check(follow.progress <= initial, "Yielding vehicle still respects its red light after recovery")
	other._clearance_requester = null
	other._clearance_last_requester = 0
	other._clearance_retreat = 0.0
	check(other._accept_clearance_request(owner), "A fresh maneuver starts with clear rear space")
	var before := follow.progress
	var half_length: float = other.collision.shape.size.x * 0.5
	var arriving := block(world, other.global_position - other.global_transform.x * (half_length + 10.2))
	await physics_frame
	await physics_frame
	other.advance_on_lane(0.1)
	check(is_equal_approx(follow.progress, before) and other._clearance_retreat == 0.0, "Reverse aborts if a pedestrian enters behind after planning")
	arriving.queue_free()
	world.queue_free()
	await process_frame
	quit(1 if failures else 0)

