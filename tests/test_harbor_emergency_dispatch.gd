extends SceneTree

const PREVIEW := preload("res://district/harbor_preview/HarborPreview.tscn")
const ADAPTER := preload("res://district/harbor_preview/HarborEmergencyDirector.gd")
var failures: Array[String] = []
var foreign_units: Array[Node] = []
var foreign_target: Node2D

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error(label)

func _run() -> void:
	seed(4183)
	var scene := PREVIEW.instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in 5:
		await physics_frame
	var director := get_first_node_in_group("emergency_depot_director")
	check(director != null and director.get_script() == ADAPTER, "Production preview integrates Harbor emergency adapter")
	if director == null:
		await _finish(scene)
		return
	var audit: Dictionary = director.get_harbor_depot_audit()
	# 4, not 3: the coroner now shares the clinic apron too (previously no
	# depot was registered for "coroner" at all, so request_dispatch always
	# returned null and the IML never responded to a death -- see
	# HarborEmergencyDirector.gd's DEPOTS dict and tests/test_rescue_and_burial_flow.gd).
	check(audit.size() == 4, "All four Harbor service depots register (fire/police/ambulance/coroner)")
	for service in audit:
		check(audit[service].spawn_clear, "Exterior apron spawn clear: " + service)
	check(director.request_dispatch("fire", null, false) == null, "Missing incident target cannot dispatch")
	var probe_target := Node2D.new()
	probe_target.position = Vector2(1100, 2230)
	scene.add_child(probe_target)
	var obstruction := StaticBody2D.new()
	obstruction.position = audit.police.spawn
	obstruction.collision_layer = 1
	var obstruction_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(110, 110)
	obstruction_shape.shape = rectangle
	obstruction.add_child(obstruction_shape)
	scene.add_child(obstruction)
	await physics_frame
	await physics_frame
	check(director.request_dispatch("police", probe_target, false) == null,
		"Occupied depot refuses spawn rather than overlapping obstacle")
	obstruction.queue_free()
	await physics_frame
	await physics_frame
	var pool := root.get_node("EmergencyPool")
	# Reserve the complete finite medical pool before any real incident. These
	# fixture reservations remain active and unchanged when a third is refused.
	var reserved: Array[Node] = []
	for index in 2:
		var unit: Node = pool.get_vehicle("ambulance")
		if unit:
			unit.target = probe_target
			reserved.append(unit)
	check(reserved.size() == 2 and director.request_dispatch("ambulance", probe_target, false) == null,
		"Exhausted finite pool returns null without instantiating extra units")
	for unit in reserved:
		check(unit.visible and unit.target == probe_target, "Refused dispatch preserves already reserved service")
		pool.return_vehicle(unit)
	var interior: Node = scene.get_node("Interiors").fire_station_interior
	var interior_count: int = interior.get("bay_trucks").size()
	var fire_car: CharacterBody2D = scene.get_node("PlayerCar")
	fire_car.global_position = Vector2(5250, -1130)
	fire_car.rotation = PI
	fire_car.set_physics_process(false)
	# Real vehicle damage starts production combustion and requests the director.
	fire_car.take_damage(fire_car.max_health)
	await physics_frame
	var truck: Node2D
	for vehicle in get_nodes_in_group("emergency_vehicle"):
		if vehicle.visible and vehicle.type == 2 and vehicle.target == fire_car:
			truck = vehicle
	check(truck != null, "Real burning car requests pooled fire engine")
	if truck == null:
		await _finish(scene)
		return
	check(truck.global_position.distance_to(fire_car.global_position) > 400, "Response proves road travel, not adjacent spawn")
	check(director.request_dispatch("fire", fire_car, false) == truck, "Duplicate incident never consumes another engine")
	var last := truck.global_position
	var distance := 0.0
	var deployed := false
	var extinguished := false
	var max_jump := 0.0
	for frame in 3600:
		await physics_frame
		if not is_instance_valid(truck) or not truck.visible:
			break
		var step := last.distance_to(truck.global_position)
		max_jump = maxf(max_jump, step)
		distance += step
		last = truck.global_position
		deployed = deployed or truck.deployed_firefighters == 2
		if deployed and not fire_car.flame_particles.emitting and not fire_car._fire_truck_dispatched:
			extinguished = true
			break
	check(distance > 400 and max_jump < 30, "Fire response travels physically without recycling/teleport")
	check(deployed and extinguished, "Real firefighters deploy, approach and extinguish production fire")
	check(interior.get("bay_trucks").size() == interior_count, "Dispatch preserves three independently playable interior trucks")
	var target := Node2D.new()
	target.position = Vector2(1100, 2230)
	scene.add_child(target)
	var police: Node2D = director.request_dispatch("police", target, false)
	check(police != null and police.global_position.distance_to(audit.police.spawn) < 0.01, "Police departs authored clear precinct apron")
	var ambulance: Node2D = director.request_dispatch("ambulance", target, false)
	check(ambulance != null and ambulance.global_position.distance_to(audit.ambulance.spawn) < 0.01, "Ambulance departs authored clinic apron")
	# Simulate a timeout/recycle followed by another scene claiming the units.
	# Old incident mappings must neither deduplicate to them nor reclaim them.
	foreign_target = Node2D.new()
	foreign_target.position = Vector2(-50000, -50000)
	root.add_child(foreign_target)
	for entry in [[police, "police"], [ambulance, "ambulance"]]:
		if not is_instance_valid(entry[0]):
			continue
		pool.return_vehicle(entry[0])
		var reused: Node = pool.get_vehicle(entry[1])
		check(reused == entry[0], "Fixture reuses the exact pooled instance")
		reused.target = foreign_target
		reused.home_depot_id = "fixture_other_scene"
		reused.set_physics_process(false)
		foreign_units.append(reused)
	var replacement: Node = director.request_dispatch("police", target, false)
	check(replacement != null and replacement != police and replacement.target == target,
		"Stale timeout mapping cannot deduplicate an unrelated retargeted unit")
	print("HARBOR_EMERGENCY_RESPONSE traveled=%.1f max_step=%.1f deployed=%s extinguished=%s final=%s" % [distance,max_jump,deployed,extinguished,truck.global_position])
	await _finish(scene)

func _finish(scene: Node) -> void:
	var assigned: Array[Node] = []
	for vehicle in get_nodes_in_group("emergency_vehicle"):
		if vehicle.visible and not foreign_units.has(vehicle):
			assigned.append(vehicle)
	scene.queue_free()
	await process_frame
	await process_frame
	for vehicle in assigned:
		check(not vehicle.visible and vehicle.target == null and vehicle.collision_layer == 0,
			"Scene exit reclaims active root pooled unit without manual test cleanup")
	for actor in get_nodes_in_group("firefighter"):
		check(not assigned.has(actor.fire_truck), "Scene exit removes root-level responders belonging to its pool units")
	for unit in foreign_units:
		check(unit.visible and unit.target == foreign_target and unit.home_depot_id == "fixture_other_scene",
			"Stale assignment cannot reclaim another scene's retargeted service unit")
		root.get_node("EmergencyPool").return_vehicle(unit)
	if is_instance_valid(foreign_target):
		foreign_target.queue_free()
	print("HARBOR EMERGENCY DISPATCH: %d failure(s)" % failures.size())
	quit(1 if failures.size() else 0)
