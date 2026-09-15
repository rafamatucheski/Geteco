extends SceneTree
var failures: Array[String] = []
var care: Node
var renewal: Node

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func tick(seconds: float) -> void:
	for i in ceili(seconds * 2.0):
		care._process(0.5)
		renewal._process(0.5)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	care = root.get_node("NPCMedicalCare")
	renewal = root.get_node("WorldRenewal")
	care.set_process(false)
	renewal.set_process(false)
	root.get_node("WantedManager").set_process(false)
	var citizen = load("res://characters/AnimatedPedestrian3D.gd").new()
	citizen.name = "RenewableResident"
	citizen.position = Vector2(3000, 3000)
	world.add_child(citizen)
	await process_frame
	citizen.set_physics_process(false)
	var key: String = citizen.get_meta("medical_identity")
	citizen.global_position = Vector2(200,200)
	citizen.take_damage(1000)
	# Independent of witnesses, rescue, local physics, or active district.
	world.process_mode = Node.PROCESS_MODE_DISABLED
	tick(29)
	check(citizen.is_dead and citizen.modulate.a == 1.0, "Body remains during rescue opportunity")
	tick(3)
	check(citizen.modulate.a > 0.0 and citizen.modulate.a < 1.0, "Corpse fades gradually in a sleeping district")
	tick(4)
	check(not citizen.visible and citizen.collision_layer == 0, "Unattended corpse stops rendering and colliding")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(root.get_node("CampaignState").to_save_data()))
	check(root.get_node("CampaignState").restore_from_save(saved), "Cleanup state survives campaign serialization")
	tick(21)
	check(not citizen.is_dead and citizen.visible and citizen.health > 0, "Population returns after cleanup")
	check(citizen.global_position == Vector2(3000,3000), "Replacement uses an offscreen authored location")
	check(not care.records().has(key), "Completed cleanup removes persistent casualty")
	# A dispatched unit cannot reserve a body forever after the crew dies.
	var unit = load("res://emergency/EmergencyVehicle.tscn").instantiate()
	world.add_child(unit)
	unit.activate()
	unit.set_physics_process(false)
	await process_frame
	citizen.global_position = Vector2(200,200)
	citizen.take_damage(1000)
	unit.target = citizen
	care.incidents[key].unit = unit
	care.incidents[key].phase = "dispatched"
	tick(40)
	check(citizen.modulate.a == 1.0, "Active dispatch has more time than an unattended death")
	tick(82)
	check(citizen.modulate.a < 1.0 and unit.target == null, "Stalled rescue eventually releases its target")
	care.retry_patient(citizen)
	check(care.incidents[key].phase == "fading", "Late rescue callbacks cannot restart cleanup")
	tick(30)
	check(not citizen.is_dead, "Population recovers after an unsuccessful rescue")
	# Even a pooled vehicle in a disabled region is eventually returned.
	unit.health = 0
	unit.is_broken = true
	unit.is_exploded = true
	tick(45)
	check(not unit.visible and unit.collision_layer == 0, "Destroyed emergency vehicle returns to its pool")
	unit.activate()
	check(not unit.is_broken and unit.health > 0, "Emergency pool can reuse the cleaned vehicle")
	unit.queue_free()
	# Repeated destruction cannot accumulate additional population nodes.
	for cycle in 3:
		citizen.global_position = Vector2(200,200)
		citizen.take_damage(1000)
		tick(60)
		check(is_instance_valid(citizen) and not citizen.is_dead, "Population slot survives cycle %d" % cycle)
	world.process_mode = Node.PROCESS_MODE_INHERIT
	var bear = load("res://world/mountain_pass/MountainBear.gd").new()
	bear.position = Vector2(4000,3000)
	world.add_child(bear)
	await process_frame
	bear.set_physics_process(false)
	var bear_health: int = bear.health
	bear.take_damage(1000)
	tick(60)
	check(is_instance_valid(bear) and not bear.is_dead and not bear.model.dead, "Wildlife returns alive with its model reset")
	check(bear.health == bear_health and bear.collision_layer == 4, "Bear health and collision restored")
	var lamp = load("res://geodata/StreetLamp.gd").new()
	lamp.position = Vector2(5000,3000)
	world.add_child(lamp)
	var prop = load("res://geodata/BreakableProp.gd").new()
	prop.position = Vector2(5200,3000)
	prop.collision_layer = 1
	world.add_child(prop)
	var cargo = load("res://geodata/PhysicalCargo.gd").new()
	cargo.position = Vector2(5400,3000)
	world.add_child(cargo)
	var debris = load("res://guns/ImpactDebris.gd").spawn(world, Vector2(5600,3000), Vector2.RIGHT, 100, "wood")
	var car = load("res://cars/traffic/TrafficVehicle.tscn").instantiate()
	car.position = Vector2(6000,3000)
	world.add_child(car)
	car.configure_as_parked()
	var lane := Path2D.new()
	lane.position = Vector2(7000,3000)
	lane.curve = Curve2D.new()
	lane.curve.add_point(Vector2.ZERO)
	lane.curve.add_point(Vector2(500,0))
	world.add_child(lane)
	var follower := PathFollow2D.new()
	lane.add_child(follower)
	var traffic = load("res://cars/traffic/TrafficVehicle.tscn").instantiate()
	traffic.speed = 90
	follower.add_child(traffic)
	await process_frame
	car.set_physics_process(false)
	traffic.set_physics_process(false)
	traffic.set_process(false)
	traffic.health = 0
	traffic.is_broken = true
	traffic.is_exploded = true
	traffic._detached_from_lane = true
	lamp.receive_vehicle_impact(200, Vector2.RIGHT)
	prop.receive_vehicle_impact(100, Vector2.RIGHT)
	cargo.take_damage(1000)
	# Loaded wrecks set state directly and never run an explosion coroutine.
	car.health = 0
	car.is_broken = true
	car.is_exploded = true
	world.process_mode = Node.PROCESS_MODE_DISABLED
	tick(38)
	check(debris.is_queued_for_deletion(), "Debris expires even in a sleeping region")
	check(car.modulate.a > 0 and car.modulate.a < 1, "Restored vehicle wreck fades without its physics running")
	tick(4)
	check(not car.visible and car.collision_layer == 0, "Vehicle wreck becomes nonblocking")
	tick(25)
	check(car.visible and not car.is_broken and car.health == car.max_health, "Fleet slot is repaired and reused")
	check(not traffic._detached_from_lane and traffic.speed == 90 and traffic.get_parent() == follower, "Exploded traffic resumes its lane without losing the fleet slot")
	tick(55)
	check(not lamp.broken and not lamp._falling and lamp.collision_layer == 1, "Fallen lamp rebuilt after delay")
	check(not prop.broken and prop.collision_layer == 1, "Street furniture regains collision")
	check(not cargo.broken and cargo.health > 0 and cargo.collision_layer == 1, "Physical cargo is replenished instead of permanently deleted")
	# Never remove the vehicle occupied by the player.
	car.is_driven_by_player = true
	car.health = 0
	car.is_broken = true
	tick(200)
	check(car.visible and car.modulate.a == 1.0, "Occupied vehicle is preserved")
	car.is_driven_by_player = false
	car.repair_vehicle()
	# Returning a prop within view must wait for the player to leave.
	var visible_prop = load("res://geodata/BreakableProp.gd").new()
	visible_prop.position = Vector2(200,200)
	visible_prop.collision_layer = 1
	world.add_child(visible_prop)
	await process_frame
	visible_prop.receive_vehicle_impact(100, Vector2.RIGHT)
	tick(150)
	check(visible_prop.broken and not visible_prop.visible, "No obstacle materializes on camera")
	# Legacy casualties without a new timer still expire while unloaded.
	care.records()["legacy:unloaded"] = {"phase":"down", "home_x":0, "home_y":0, "days":2.0}
	tick(150)
	check(not care.records().has("legacy:unloaded"), "Legacy unloaded casualty does not remain in save forever")
	# Rebuild a resident from a saved recycling record, rather than only
	# restoring the dictionary around an existing live object.
	citizen.global_position = Vector2(200,200)
	citizen.take_damage(1000)
	tick(36)
	var remaining: float = care.records()[key].remaining_seconds
	citizen.queue_free()
	await process_frame
	var replacement = load("res://characters/AnimatedPedestrian3D.gd").new()
	replacement.name = "RenewableResident"
	replacement.position = Vector2(3000,3000)
	world.add_child(replacement)
	await process_frame
	check(not replacement.visible and replacement.is_dead, "Reload keeps the pending cleanup hidden")
	tick(remaining + 1)
	check(replacement.visible and not replacement.is_dead, "Saved cleanup finishes after re-creating the resident")
	print("WORLD_RENEWAL failures=", failures.size(), " ", failures)
	world.queue_free()
	await process_frame
	care.incidents.clear()
	care.residents.clear()
	care.records().clear()
	quit(0 if failures.is_empty() else 1)
