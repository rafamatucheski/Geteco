extends SceneTree
## Reduced causal probe from armored-route-junction-exit-cobre-final.log.
## HISTORICAL defect reproduction: assertions expect the pre-fix deadlock.
## Acceptance coverage lives in tests/test_traffic_junction_completed_turn.gd.
## Two real ordinary Vehicles, no convoy/controller/formation hold. Initial
## transforms and already-committed entry reservations are explicit setup.
## Local L-shaped routes reproduce the observed turning/next-approach relation;
## this does not certify the full authored route, traffic demand or signal art.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const JUNCTIONS := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
const EAST := Vector3(382.5, 0, -262.5)
const WEST := Vector3(367.5, 0, -262.5)
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("return reservation probe timeout"); quit(3))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("RETURN_CYCLE ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func curve(points: Array[Vector3]) -> Curve3D:
	var result := Curve3D.new()
	for point in points: result.add_point(point)
	result.set_meta("traffic_open", true)
	return result

func committed(car: CharacterBody3D, center: Vector3, heading: Vector3) -> void:
	var key := JUNCTIONS.key_of(center)
	check(JUNCTIONS.request(key, car.get_instance_id(), heading, -2.0, 0.0), "initial committed turn owns its entry junction")
	car._junction_route = car.route
	car._junction_list = JUNCTIONS.along(car.route)
	car._held_junction = key
	for row in car._junction_list:
		if row.key == key: car._held_offset = row.offset

func snapshot(car: CharacterBody3D, requested: Vector3) -> Dictionary:
	var key := JUNCTIONS.key_of(requested)
	return {"point":str(car.global_position), "yaw":car.rotation.y, "speed":car.speed,
		"blocked":car.blocked, "signal":car.junction_wait, "gap":car.junction_gap,
		"held":str(car._held_junction), "held_axis":JUNCTIONS.owners.get(car._held_junction, {}).get(car.get_instance_id(), []),
		"next_owners":str(JUNCTIONS.owners.get(key, {})), "next_cross_axis_conflict":JUNCTIONS._cross_traffic_inside(key, car.get_instance_id(), true)}

func run() -> void:
	var map_hash := FileAccess.get_sha256("res://world/editing/world_edits.json")
	JUNCTIONS.configure({"vertices":[EAST, WEST, EAST + Vector3.FORWARD * 40, EAST + Vector3.BACK * 40, WEST + Vector3.FORWARD * 40, WEST + Vector3.BACK * 40],
		"edges":{0:[{"to":1},{"to":2},{"to":3}], 1:[{"to":0},{"to":4},{"to":5}]}})
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(100, .2, 100)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(375, -.1, -262.5)
	world.add_child(floor_body)
	var westbound := VEHICLE.new()
	westbound.archetype = "sedan_classic"
	westbound.position = Vector3(376.586, .04, -263.8494)
	westbound.rotation.y = 1.52438056
	westbound.route = curve([Vector3(382.5,0,-230),Vector3(382.5,0,-263.8494),Vector3(340,0,-263.8494)])
	world.add_child(westbound)
	westbound.set_physics_process(false)
	var eastbound := VEHICLE.new()
	eastbound.archetype = "sedan_classic"
	eastbound.position = Vector3(373.5298,.04,-261.1108)
	eastbound.rotation.y = -PI / 2.0
	eastbound.route = curve([Vector3(367.5,0,-300),Vector3(367.5,0,-261.1108),Vector3(410,0,-261.1108)])
	world.add_child(eastbound)
	eastbound.set_physics_process(false)
	for frame in 3: await physics_frame
	committed(westbound, EAST, Vector3.FORWARD)
	committed(eastbound, WEST, Vector3.BACK)
	var start_w: Vector3 = westbound.global_position
	var start_e: Vector3 = eastbound.global_position
	for car in [westbound, eastbound]:
		car.traffic = true
		car.set_physics_process(true)
	for frame in 720: await physics_frame
	var key_e := JUNCTIONS.key_of(EAST)
	var key_w := JUNCTIONS.key_of(WEST)
	check(westbound.global_position.distance_to(start_w) < .3 and eastbound.global_position.distance_to(start_e) < .3, "both civilians remain stopped for twelve seconds without any convoy or formation hold")
	check(westbound.junction_wait and eastbound.junction_wait and not westbound.blocked and not eastbound.blocked, "normal controllers stop on reservation conflict, not physical bumper obstruction")
	check(JUNCTIONS.occupies(key_e, westbound.get_instance_id()) and JUNCTIONS.occupies(key_w, eastbound.get_instance_id()), "each upstream lease remains backed by an actual hull even after its nine-second TTL")
	check(JUNCTIONS._cross_traffic_inside(key_w, westbound.get_instance_id(), true) and JUNCTIONS._cross_traffic_inside(key_e, eastbound.get_instance_id(), true), "each next east-west approach conflicts with the other's retained north-south entry axis")
	print("RETURN_CYCLE_TRACE ", JSON.stringify({"westbound":snapshot(westbound, WEST), "eastbound":snapshot(eastbound, EAST), "map_sha256":map_hash}))
	check(map_hash == FileAccess.get_sha256("res://world/editing/world_edits.json"), "map document remains byte-identical")
	world.free()
	print("RETURN_CYCLE_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
