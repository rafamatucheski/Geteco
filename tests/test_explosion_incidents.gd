extends SceneTree
const TRAFFIC := preload("res://cars/traffic/TrafficVehicle.tscn")
const BLAST := preload("res://guns/combat/VehicleBlast.gd")
var failures := 0
var world: Node2D
var capture := "--capture" in OS.get_cmdline_user_args()

func screenshot(label: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/explosion-" + label + ".png")

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for i in count: await physics_frame

func person_at(point: Vector2) -> Node2D:
	var person = load("res://characters/AnimatedPedestrian3D.gd").new()
	world.add_child(person)
	person.position = point
	person.set_physics_process(false)
	return person

func _run() -> void:
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	if capture:
		root.size = Vector2i(1280, 720)
		var ground := Polygon2D.new()
		ground.polygon = PackedVector2Array([Vector2(-400, -100), Vector2(1000, -100), Vector2(1000, 750), Vector2(-400, 750)])
		ground.color = Color("30383b")
		ground.z_index = -10
		world.add_child(ground)
		var camera := Camera2D.new()
		camera.position = Vector2(310, 335)
		camera.zoom = Vector2.ONE * 2.2
		world.add_child(camera)
		camera.make_current()
	var director := EmergencyDepotDirector.new()
	world.add_child(director)
	for service in ["fire", "coroner"]:
		var depot := EmergencyDepotMarker.new()
		depot.service_key = service
		depot.depot_id = "test_" + service
		depot.position = Vector2(-800, -800)
		director.add_child(depot)
		director.register_depot(depot)
	await frames(3)
	var cars: Array[Node2D] = []
	var first: Node
	for i in 7:
		var car = TRAFFIC.instantiate()
		world.add_child(car)
		car.configure_as_parked()
		car.position = Vector2(1000 + i * 60, 1000)
		car.is_broken = true
		cars.append(car)
		var unit := director.request_dispatch("fire", car, false)
		if unit: unit.set_physics_process(false)
		if i == 0: first = unit
		if i < 3: check(unit == first, "One truck covers cars 1–3")
		if i == 3: check(unit != null and unit != first, "Fourth fire may receive second finite unit")
		if i == 6: check(unit == null, "Seventh fire queues when both trucks are occupied")
	check(first.service_targets.size() == 3, "First truck owns exactly three fire targets")
	var count := 0
	for unit in root.get_node("EmergencyPool")._pool.fire:
		if unit.visible: count += 1
	check(count == 2, "Hard cap of two active dispatched fire trucks")
	check(director.request_dispatch("fire", cars[0]) == first, "Repeated request never duplicates truck")
	cars[0].set_meta("service_complete", true)
	check(first._advance_service_target() and first.target == cars[1], "Crew proceeds to next burning car")
	cars[1].set_meta("service_complete", true)
	check(first._advance_service_target() and first.target == cars[2], "Third fire stays on same truck")
	cars[2].set_meta("service_complete", true)
	check(not first._advance_service_target(), "Incident finishes after its last fire")
	root.get_node("EmergencyPool").return_vehicle(first)
	director._service_incidents._process(1.1)
	check(cars[6].get_meta("fire_response_assigned", false), "Queued fire remains registered")
	var queued = director._service_incidents.incidents.back().vehicle
	check(is_instance_valid(queued) and queued.target == cars[6], "Released truck serves queued incident")
	if queued: queued.set_physics_process(false)
	# Actual explosion: visible actors, a wall, a nearby vehicle, a far survivor.
	var source = TRAFFIC.instantiate()
	world.add_child(source)
	source.apply_archetype("sedan_classic", Color("ad522a"))
	source.configure_as_parked()
	source.position = Vector2(280, 320)
	var near_person = person_at(source.position + Vector2(80, 0))
	var far_person = person_at(source.position + Vector2(205, 70))
	var protected_person = person_at(source.position + Vector2(0, -95))
	var wall := StaticBody2D.new()
	wall.position = source.position + Vector2(0, -50)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(90, 10)
	shape.shape = rect
	wall.add_child(shape)
	world.add_child(wall)
	var nearby_car = TRAFFIC.instantiate()
	world.add_child(nearby_car)
	nearby_car.configure_as_parked()
	nearby_car.position = source.position + Vector2(0, 110)
	await frames(3)
	var near_health: int = nearby_car.health
	source._explode()
	check(near_person.is_dead and near_person.has_meta("explosion_remains"), "Near blast death creates remains")
	check(not far_person.is_dead and far_person.health < far_person.max_health, "Outer blast damages but does not automatically kill")
	check(protected_person.health == protected_person.max_health, "Wall protects people from blast damage")
	check(nearby_car.health < near_health, "Blast damages nearby cars even outside damageable group")
	check(far_person.has_node("BlastImpulse"), "Survivor receives collision-resolved knockback")
	var remains: Node2D = near_person.get_meta("explosion_remains")
	check(remains.pieces.size() >= 4 and remains.pieces.size() <= 6 and not near_person.visible, "Variable anatomical pieces replace the intact corpse")
	await frames(8)
	await screenshot("01-blast")
	BLAST.apply(source)
	check(get_nodes_in_group("explosion_remains").size() == 1, "Repeated blast does not duplicate remains")
	await frames(120)
	await screenshot("02-remains")
	for piece in remains.pieces:
		check(piece.height == 0 and piece.velocity == Vector2.ZERO, "Fragments land and stop")
	var hearse: Node = director.request_dispatch("coroner", remains)
	check(hearse != null, "One IML vehicle responds to all four pieces")
	if hearse:
		hearse.set_physics_process(false)
		hearse.position = remains.position + Vector2(110, -60)
		hearse.rotation = 0
		hearse._deploy_morticians()
		var original_count: int = remains.pieces.size()
		for i in 1100:
			await physics_frame
			if i == 120: await screenshot("03-iml")
			if not is_instance_valid(remains): break
		check(not is_instance_valid(remains), "Actual IML crew approaches and collects all four parts")
		print("IML_PARTS original=%d collected=%s" % [original_count, not is_instance_valid(remains)])
	print("EXPLOSION_INCIDENTS failures=%d" % failures)
	quit(0 if failures == 0 else 1)
