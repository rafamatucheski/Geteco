extends SceneTree

const PERIMETER := preload("res://world/harbor/WorldPerimeter.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fixture := Node2D.new()
	var integrated := "integrated" in OS.get_cmdline_user_args()
	if integrated:
		fixture.free()
		fixture = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(fixture)
	var perimeter: Node2D
	if integrated:
		current_scene = fixture
		while not fixture.get("world_build_ready"): await process_frame
		perimeter = get_first_node_in_group("world_perimeter")
	else:
		perimeter = PERIMETER.new()
		fixture.add_child(perimeter)
		var waterfront := preload("res://world/harbor/HarborWaterfront.gd").new()
		fixture.add_child(waterfront)
	var walker := CharacterBody2D.new()
	walker.collision_layer = 4
	walker.collision_mask = 1
	var collision := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 5.0
	capsule.height = 16.0
	collision.shape = capsule
	walker.add_child(collision)
	fixture.add_child(walker)
	await physics_frame

	# This is the outside of the waterfront turn shown in the regression image.
	# It starts on the road, rounds the bend on the paved shoulder and continues
	# south without crossing the relocated coastal guardrail.
	walker.position = Vector2(3000, 2200)
	var shoulder_route := PackedVector2Array([
		Vector2(3000, 2090), Vector2(3180, 2090), Vector2(3258, 2122),
		Vector2(3388, 2252), Vector2(3420, 2330), Vector2(3420, 2600),
	])
	for point in shoulder_route:
		_sweep(walker, point, "Waterfront shoulder")
		_check(perimeter.contains_point(point), "Shoulder route left authored land at %s" % point)

	# The perimeter still has a physical purpose: moving from the new shoulder
	# into the water must meet the seawall instead of opening the map boundary.
	walker.position = Vector2(3420, 2500)
	var water_hit := walker.move_and_collide(Vector2(80, 0))
	_check(water_hit != null and (water_hit.get_collider() as Node).is_in_group("world_boundary"), "Coastal guardrail no longer blocks the water edge")
	# Full vehicle hull on both lanes, crossing the old y=2140 water-band seam.
	walker.position = Vector2(3160, 2160)
	var car_hull := RectangleShape2D.new()
	car_hull.size = Vector2(72, 31)
	collision.shape = car_hull
	if integrated:
		walker.queue_free()
		walker = fixture.get_node("PlayerCar") as CharacterBody2D
		walker.set_physics_process(false)
		walker.position = Vector2(3160,2160)
		# Isolate the static barrier while retaining the production car and mask.
		for other in get_nodes_in_group("vehicle"):
			if other is PhysicsBody2D and other != walker:
				walker.add_collision_exception_with(other)
	var car_route := PackedVector2Array([
		Vector2(3180, 2160), Vector2(3350, 2330), Vector2(3350, 2700),
	])
	for point in car_route:
		walker.rotation = (point - walker.position).angle()
		_sweep(walker, point, "Inbound car")
	walker.position = Vector2(3290, 2700)
	for point in [Vector2(3290, 2338), Vector2(3172, 2220), Vector2(3000, 2220)]:
		walker.rotation = (point - walker.position).angle()
		_sweep(walker, point, "Outbound car")
	print("HARBOR_SOUTH_PORT_CURVE integrated=%s route_points=%d failures=%d" % [integrated, shoulder_route.size(), failures.size()])
	for failure in failures:
		push_error(failure)
	fixture.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _sweep(body: CharacterBody2D, target: Vector2, label: String) -> void:
	for _step in 200:
		var motion := target - body.position
		if motion.length() < 0.1:
			return
		var hit := body.move_and_collide(motion.limit_length(4.0))
		if hit != null:
			_check(false, "%s blocked at %s toward %s by %s" % [label, body.position, target, hit.get_collider()])
			return
	_check(false, "%s sweep exceeded its finite step budget" % label)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
