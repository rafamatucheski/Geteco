extends SceneTree

const LIFE := preload("res://world/harbor/HarborLife.gd")
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func walker(route: PackedVector2Array, location: Vector2) -> AuthoredSidewalkPedestrian:
	var person := LIFE.HarborWalker.new()
	person.configure_authored_route(route, "living_navigation")
	person.pause_at_destinations = false
	person.defer_presentation = true
	root.add_child(person)
	person.position = location
	person.is_gangster = false
	person.visit_cooldown = 1000.0
	person._normal_walk_speed = 48.0
	person.lateral_offset = 0.0
	person._route_segment = 0
	person.walk_target = route[1]
	return person

func wall(location: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.position = location
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	return body

func frames(count: int) -> void:
	for i in count: await physics_frame

func _run() -> void:
	create_timer(35.0).timeout.connect(func(): quit(2))
	seed(812)
	root.get_node("WantedManager").set_process(false)
	var route := PackedVector2Array([Vector2(0, 0), Vector2(300, 0)])
	var a := walker(route, Vector2(60, 0))
	var reversed := route.duplicate()
	reversed.reverse()
	var b := walker(reversed, Vector2(160, 0))
	await frames(2)
	var initial_a := a.position
	var initial_b := b.position
	var min_gap := INF
	for i in 180:
		await physics_frame
		min_gap = minf(min_gap, a.position.distance_to(b.position))
	check(a.position.x > b.position.x + 15.0, "Opposing residents physically pass instead of deadlocking")
	check(min_gap >= 19.0, "Passing walkers retain body-sized personal clearance")
	check(a.position.distance_to(initial_a) > 50.0 and b.position.distance_to(initial_b) > 50.0, "Both pedestrians make progress on narrow sidewalk")
	a.free()
	b.free()
	await frames(1)

	var turn_route := PackedVector2Array([Vector2(0, 300), Vector2(300, 300), Vector2(300, 600)])
	var returning := walker(turn_route, Vector2(260, 500))
	returning._route_segment = 0
	returning._route_direction = 1
	returning._route_target_ready = true
	returning.walk_target = Vector2(300, 300)
	var start := returning.position
	returning._resume_after_panic()
	check(returning._route_segment == 1, "After panic selects nearby sidewalk leg, not stale corner")
	check(returning.position == start, "Returning to routine never teleports resident")
	await frames(150)
	check(not returning._rejoining_route and returning.position.y > start.y + 15.0, "Citizen physically rejoins and continues routine after escape")
	check(absf(returning.position.x - 300.0) <= 14.1, "Recovered walker follows authored sidewalk corridor")
	returning.free()

	var top := wall(Vector2(70, 870), Vector2(280, 10))
	var bottom := wall(Vector2(70, 930), Vector2(280, 10))
	var trapped := walker(PackedVector2Array([Vector2(0, 900), Vector2(200, 900)]), Vector2(0, 900))
	trapped.set_physics_process(false)
	await frames(2)
	trapped.hear_gunfire(Vector2(-100, 800), Vector2(-100, 800))
	var escaped := trapped.danger_response.movement(trapped, 0.016, 100.0)
	check(escaped.length() > 1.0, "Frightened citizen finds short escape step in narrow alley")
	check(escaped.x > 0.0, "Escape progresses away from danger along open corridor")
	var ray := PhysicsRayQueryParameters2D.create(trapped.position, trapped.danger_response.destination, 1, [trapped.get_rid()])
	check(trapped.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(), "Escape step respects physical walls")
	trapped.free()
	top.free()
	bottom.free()
	await frames(2)
	print("LIVING_PEDESTRIAN_NAVIGATION failures=%d" % failures)
	quit(0 if failures == 0 else 1)
