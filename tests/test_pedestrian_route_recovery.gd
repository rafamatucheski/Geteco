extends SceneTree

const LIFE := preload("res://world/harbor/HarborLife.gd")
const NAV := preload("res://emergency/ResponderNavigation.gd")
const WALK_SPACE := preload("res://world/shared/pedestrians/PedestrianWalkSpace.gd")
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func walker(route: PackedVector2Array, at: Vector2) -> AuthoredSidewalkPedestrian:
	var person := LIFE.HarborWalker.new()
	person.configure_authored_route(route, "recovery")
	person.pause_at_destinations = false
	person.defer_presentation = true
	root.add_child(person)
	person.position = at
	person.is_gangster = false
	person.visit_cooldown = 1000.0
	person._normal_walk_speed = 48.0
	person.lateral_offset = 0.0
	person._route_segment = 0
	person._route_direction = 1
	person.walk_target = route[1]
	return person

func obstacle(at: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.position = at
	var hull := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	hull.shape = shape
	body.add_child(hull)
	root.add_child(body)
	return body

func frames(count: int) -> void:
	for i in count: await physics_frame

func run() -> void:
	create_timer(75.0).timeout.connect(func(): quit(2))
	seed(913)
	root.get_node("WantedManager").set_process(false)
	var route := PackedVector2Array([Vector2.ZERO, Vector2(280, 0), Vector2(280, 220)])
	var person := walker(route, Vector2(20, 0))
	var space := WALK_SPACE.new()
	var network := Node2D.new()
	root.add_child(network)
	# A 120px road, sidewalk centre 22px beyond asphalt, like HarborGame.
	space.configure(network, {"roads": [{"points": PackedVector2Array([Vector2(-500, -82), Vector2(500, -82)]), "width": 120.0}]})
	network.free()
	if OS.get_cmdline_user_args().has("--curb-only"):
		person.free()
		await curb_case(space)
		quit(0 if failures == 0 else 1)
		return
	person.walk_space = space
	person._corridor_segment = -1
	var post := obstacle(Vector2(95, 0), Vector2(10, 10))
	await frames(2)
	var farthest := person.position.x
	var maximum_side := 0.0
	var minimum_side := 0.0
	var largest_step := 0.0
	for i in 420:
		var before := person.position
		await physics_frame
		farthest = maxf(farthest, person.position.x)
		maximum_side = maxf(maximum_side, person.position.y)
		minimum_side = minf(minimum_side, person.position.y)
		largest_step = maxf(largest_step, before.distance_to(person.position))
	check(farthest > 200.0, "Resident passes pole on authored sidewalk: x=%.1f" % farthest)
	check(maximum_side > 16.0 and maximum_side <= 28.1, "Detour has body clearance and stays in sidewalk envelope")
	check(minimum_side >= -10.6, "Pole detour never places the body in the road")
	check(largest_step < 1.2, "Obstacle recovery moves physically without teleporting")
	person.free()
	post.free()
	await frames(2)

	person = walker(route, Vector2(50, 0))
	var wall := obstacle(Vector2(110, 0), Vector2(20, 100))
	var reversed := false
	var reached_back := false
	for i in 660:
		await physics_frame
		reversed = reversed or person._route_direction == -1
		reached_back = reached_back or (reversed and person.position.x < 40.0)
	check(reversed and reached_back, "Blocked leg produces a physical retreat instead of endless retries")
	check(person.position.x < 100.0 and absf(person.position.y) <= 28.1, "Recovery cannot skip a blocked corner through the block")
	person.free()
	wall.free()
	await frames(2)

	# Simulate foot shuffling while path search is repeatedly sliced/retried.
	person = walker(route, Vector2(40, 0))
	person.set_physics_process(false)
	wall = obstacle(Vector2(110, 0), Vector2(20, 100))
	await frames(2)
	var nav := NAV.new()
	nav.search_budget = 1
	for i in 210:
		await physics_frame
		person.position.x = 40.0 + (1.0 if i % 2 else -1.0)
		nav.movement(person, Vector2(200, 0), 48.0, 1.0 / 60.0)
	check(nav.stuck_time > 3.0, "Search slices and lateral shuffling cannot erase no-progress history")
	person.free()
	wall.free()
	await frames(2)

	person = walker(route, Vector2(20, 0))
	person._destination_pause = 1.0
	await frames(30)
	check(person.position.distance_to(Vector2(20, 0)) < 0.5 and person.locomotion_state == &"paused", "Intentional pause has its own state and no locomotion")
	await frames(100)
	check(person.position.x > 40.0 and person.recovery_count == 0, "Timed pause resumes walking without triggering recovery")
	person.free()
	await frames(2)

	await curb_case(space)
	await crossing_case()
	print("PEDESTRIAN_ROUTE_RECOVERY failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func curb_case(space: RefCounted) -> void:
	# Two pedestrians meet where the road prevents one of the usual right turns.
	var reverse_route := PackedVector2Array([Vector2(280, 0), Vector2.ZERO])
	var person := walker(PackedVector2Array([Vector2.ZERO, Vector2(280, 0)]), Vector2(50, 0))
	var other := walker(reverse_route, Vector2(160, 0))
	person.walk_space = space
	other.walk_space = space
	person._corridor_segment = -1
	other._corridor_segment = -1
	var passed := false
	var min_gap := INF
	for i in 420:
		await physics_frame
		if OS.get_cmdline_user_args().has("--curb-only") and i % 60 == 0:
			print("CURB ", i, " ", person.position, " ", other.position, " ", person.locomotion_state, " ", other.locomotion_state)
		min_gap = minf(min_gap, person.position.distance_to(other.position))
		if person.position.x > other.position.x + 20.0:
			passed = true
			break
	check(passed, "Opposing residents negotiate the road-side restriction: %s / %s" % [person.position, other.position])
	check(min_gap >= 23.0, "Road-side passing preserves personal clearance")
	person.free()
	other.free()
	await frames(2)

func crossing_case() -> void:
	var crossing := preload("res://geodata/roads/safety/RoadCrossingArea2D.gd").new()
	crossing.configure({"id":"recovery_crossing", "junction_id":"test", "position":Vector2(1000,1000), "road_width":120.0})
	root.add_child(crossing)
	crossing.set_signal_state(true, false)
	var person := walker(PackedVector2Array([Vector2(1000,918), Vector2(1000,1082)]), Vector2(1000,918))
	await frames(240)
	check(person.position.distance_to(Vector2(1000,918)) < 0.1 and person.recovery_count == 0 and person.locomotion_state == &"waiting_crossing", "Red signal is an intentional wait, not a blocked route")
	crossing.set_signal_state(false, true)
	await frames(90)
	check(person.position.y > 945.0, "Green signal resumes physical crossing")
	person.free()
	crossing.free()
	await frames(2)
