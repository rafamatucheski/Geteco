extends SceneTree

var failures: Array[String] = []
var world: Node2D

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func pedestrian(point: Vector2) -> AnimatedPedestrian3D:
	var actor := AnimatedPedestrian3D.new()
	actor.defer_presentation = true
	actor.position = point
	world.add_child(actor)
	actor.is_gangster = false
	actor.set_physics_process(false)
	return actor

func run() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("WantedManager").set_process(false)
	root.get_node("PresentationBudget").set_process(false)
	var care = root.get_node("NPCMedicalCare")
	care.set_process(false)
	var patient := pedestrian(Vector2.ZERO)
	patient.is_dead = true
	patient.health = 0
	var people: Array[AnimatedPedestrian3D] = []
	for i in 12:
		people.append(pedestrian(Vector2.from_angle(TAU * i / 12.0) * 145.0))
	var player = load("res://Player.gd").new()
	player.name = "Player"
	player.position = Vector2(500, 0)
	player.collision_layer = 4
	player.collision_mask = 7
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	var collider := CollisionShape2D.new()
	var footprint := CircleShape2D.new()
	footprint.radius = 11.0
	collider.shape = footprint
	player.add_child(collider)
	world.add_child(player)
	player.is_control_disabled = true
	await physics_frame
	await physics_frame
	care.report_injury(patient)
	care._process(0.5)
	var observers := get_nodes_in_group("medical_observer")
	check(observers.size() == 4, "Medical incidents keep the surrounding crowd bounded to four people")
	var calls := 0
	for observer in observers:
		if observer.calls_for_help: calls += 1
		if observer.calls_for_help:
			check(observer.actor.global_position.distance_to(patient.global_position + observer.ring_offset) < .01, "Caller phones from the actual observation point")
		else:
			check(is_equal_approx(observer.ring_offset.length(), 80.0), "Bystanders stand outside the casualty's footprint")
		for other in observers:
			if other != observer:
				check(observer.ring_offset.distance_to(other.ring_offset) >= 32.0, "Ring reservations never overlap")
	check(calls == 1, "Only one witness calls the ambulance")
	check(not care.begin_carry(player, null, null), "Dante can never be carried as an NPC patient")
	check(not care._can_observe(player, patient), "The player cannot be taken over as a witness")
	var reached := false
	var min_distance := INF
	for frame in 240:
		await physics_frame
		for i in people.size():
			for j in range(i + 1, people.size()):
				min_distance = minf(min_distance, people[i].position.distance_to(people[j].position))
		reached = true
		for observer in observers:
			if observer.actor.position.distance_to(patient.position + observer.ring_offset) > 3.1:
				reached = false
		if reached: break
	check(reached, "Witnesses actually walk to the circle")
	check(min_distance >= 21.8, "People remain physically separate while gathering")
	patient.hide()
	await physics_frame
	await physics_frame
	check(get_nodes_in_group("medical_observer").is_empty(), "The circle releases everyone when the casualty is collected")
	for person in people: person.queue_free()
	await process_frame
	patient.show()
	var same_side: Array = []
	for i in 12:
		var person := pedestrian(Vector2.from_angle(-1.05 + 2.1 * i / 11.0) * 180.0)
		var response := preload("res://emergency/MedicalWitness.gd").new()
		response.actor = person
		response.patient = patient
		response.calls_for_help = false
		check(response.reserve_position(), "Same-side arrivals receive individual reservations")
		person.add_child(response)
		same_side.append(response)
	var extra := pedestrian(Vector2(0, -200))
	var overflow := preload("res://emergency/MedicalWitness.gd").new()
	overflow.actor = extra
	overflow.patient = patient
	overflow.calls_for_help = false
	check(not overflow.reserve_position(), "A full circle never assigns an occupied place")
	overflow.free()
	extra.queue_free()
	var all_arrived := false
	var same_side_gap := INF
	var arrivals := {}
	for frame in 650:
		await physics_frame
		all_arrived = true
		for index in same_side.size():
			var observer = same_side[index]
			if is_instance_valid(observer) and observer.phase != "approach": arrivals[index] = true
			if not arrivals.has(index): all_arrived = false
			if is_instance_valid(observer):
				for other in same_side:
					if other != observer and is_instance_valid(other):
						same_side_gap = minf(same_side_gap, observer.actor.position.distance_to(other.actor.position))
		if all_arrived: break
	if not all_arrived:
		for observer in same_side:
			if is_instance_valid(observer): print("RING_APPROACH ", observer.phase, " actor=", observer.actor.position, " slot=", observer.ring_offset)
	check(all_arrived, "People arriving from one side walk around to fill the circle")
	check(same_side_gap >= 21.8, "Same-side arrivals never overlap")
	patient.hide()
	await physics_frame
	await physics_frame

	# Approach a motionless real player from all four directions. This catches
	# grounded platform following as well as overlap recovery moving the player.
	var mover := pedestrian(Vector2(500, -80))
	var stationary: Vector2 = player.position
	var max_drift := 0.0
	for direction in [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT]:
		mover.position = stationary - direction * 60.0
		await physics_frame
		for frame in 45:
			await physics_frame
			mover.velocity = direction * 130.0
			preload("res://world/shared/pedestrians/PersonMotion.gd").move_actor(mover)
			max_drift = maxf(max_drift, player.position.distance_to(stationary))
		check(mover.position.distance_to(player.position) >= 21.8, "NPC stops at Dante's collision boundary")
	check(max_drift < 0.001, "NPC contact never moves a stationary Dante")

	var left := pedestrian(Vector2(750, 0))
	var right := pedestrian(Vector2(830, 0))
	var separation := INF
	for frame in 60:
		await physics_frame
		left.velocity = Vector2(130, 0)
		right.velocity = Vector2(-130, 0)
		preload("res://world/shared/pedestrians/PersonMotion.gd").move_actor(left)
		preload("res://world/shared/pedestrians/PersonMotion.gd").move_actor(right)
		separation = minf(separation, left.position.distance_to(right.position))
	check(separation >= 21.8, "Opposing pedestrians cannot pass through each other")
	print("PEOPLE_SPACE_AND_BODY_RING failures=", failures.size(), " ring_min_distance=", min_distance, " player_drift=", max_drift, " opposing_gap=", separation)
	world.queue_free()
	await process_frame
	care.incidents.clear()
	care.residents.clear()
	quit(0 if failures.is_empty() else 1)
