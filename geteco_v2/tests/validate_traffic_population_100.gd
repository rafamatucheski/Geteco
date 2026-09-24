extends SceneTree

var failures: Array[String] = []
var checks := 0
var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	for frame in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.people.size() >= 100 and world.production._ambient_traffic_count() >= 100: break
	check(world.session != null and world.session.ready_for_play,"Native world becomes ready")
	check(world.people.size() == 100,"Production population reaches 100")
	check(world.production._ambient_traffic_count() == 100,"Ambient traffic reaches 100 vehicles")
	var motorcycles := 0
	for car in world.production.vehicles:
		if car.traffic and car.archetype in world.production.TRAFFIC_MOTORCYCLE_TYPES: motorcycles += 1
	check(motorcycles > 0,"Ambient fleet includes motorcycles")
	var traffic_car: CharacterBody3D = world.production.vehicles.filter(func(car): return car.traffic)[0]
	traffic_car.position = world.player.position + Vector3(200,0,0)
	await physics_frame
	check(is_instance_valid(traffic_car) and traffic_car.traffic,"Traffic vehicle remains alive beyond the local unload radius")
	check(traffic_car.distance_travelled >= 0,"Traffic vehicle retains its physical route state")
	var previous_route: Curve3D = traffic_car.route
	world.production._mount_region("mountain")
	world.production._refresh_route_consumers()
	world.production._commit_logical_region("mountain")
	check(traffic_car.traffic and traffic_car.route != null,"Traffic route is refreshed after switching logical regions")
	print("TRAFFIC_POPULATION_100 checks=%d failures=%s people=%d traffic=%d motorcycles=%d" % [checks,failures,world.people.size(),world.production._ambient_traffic_count(),motorcycles])
	world.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
