extends SceneTree
## Vehicles e reservas reais. A preparação restaura duas curvas comprometidas observadas;
## o movimento depois da preparação usa a física normal de trânsito, sem controlador de comboio.
const VEHICLE = preload("res://scripts/Vehicle.gd")
const BUS = preload("res://runtime/transit/BiarticulatedBus.gd")
const J = preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
const EAST := Vector3(382.5, 0, -262.5)
const WEST := Vector3(367.5, 0, -262.5)
var failures: Array[String] = []
var checks := 0
var world: Node3D

func _initialize() -> void:
	create_timer(35).timeout.connect(func(): push_error("completed-turn timeout"); quit(3))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("TURN ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func curve(points: Array[Vector3]) -> Curve3D:
	var result := Curve3D.new()
	for point in points: result.add_point(point)
	result.set_meta("traffic_open", true)
	return result

func setup_graph() -> void:
	J.configure(null)
	J._signals.clear()
	J.configure({"vertices":[EAST, WEST, EAST + Vector3.FORWARD * 40, EAST + Vector3.BACK * 40, WEST + Vector3.FORWARD * 40, WEST + Vector3.BACK * 40],
		"edges":{0:[{"to":1},{"to":2},{"to":3}], 1:[{"to":0},{"to":4},{"to":5}]}})

func make_car(point: Vector3, yaw: float, route: Curve3D) -> CharacterBody3D:
	var car = VEHICLE.new()
	car.archetype = "sedan_classic"
	car.position = point
	car.rotation.y = yaw
	car.route = route
	world.add_child(car)
	car.set_physics_process(false)
	car.traffic = true
	return car

func committed(car: CharacterBody3D, center: Vector3, heading: Vector3) -> void:
	var key := J.key_of(center)
	check(J.request(key, car.get_instance_id(), heading, -2.0, 0.0), "committed entry lease acquired")
	car._junction_route = car.route
	car._junction_list = J.along(car.route)
	car._held_junction = key
	for row in car._junction_list:
		if row.key == key: car._held_offset = row.offset

func run() -> void:
	if not ClassDB.class_exists(&"CSharpScript") or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	setup_graph()
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(140, .2, 140)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(375, -.1, -262.5)
	world.add_child(floor_body)
	var route_w := curve([Vector3(382.5,0,-230),Vector3(382.5,0,-263.8494),Vector3(330,0,-263.8494)])
	var route_e := curve([Vector3(367.5,0,-300),Vector3(367.5,0,-261.1108),Vector3(425,0,-261.1108)])
	var westbound := make_car(Vector3(376.586,.04,-263.8494),1.52438056,route_w)
	var eastbound := make_car(Vector3(373.5298,.04,-261.1108),-PI/2,route_e)
	for frame in 3: await physics_frame
	var key := J.key_of(EAST)
	var id := westbound.get_instance_id()
	committed(westbound,EAST,Vector3.FORWARD)
	var timestamp: int = J.owners[key][id][1]
	check(not J._cross_traffic_inside(key,eastbound.get_instance_id(),true), "completed aligned turn permits compatible outgoing axis")
	check(J.owners[key].has(id) and J.owners[key][id][1] == timestamp and J.occupies(key,id), "reclassification retains same physical lease and timestamp")
	check(J._cross_traffic_inside(key,eastbound.get_instance_id(),false), "completed turn still blocks transverse entry")
	# Cada exclusão restaura o eixo de entrada original e depois pede a travessia.
	for property in {"traffic":false,"controlled":true,"external_input":true,"bypass_side":1.0,"bypass_blend":.5,"_merging_back":true,"speed":-1.0,"route":null}:
		var previous = westbound.get(property)
		var excluded: Dictionary = {"traffic":false,"controlled":true,"external_input":true,"bypass_side":1.0,"bypass_blend":.5,"_merging_back":true,"speed":-1.0,"route":null}
		westbound.set(property,excluded[property])
		J.owners[key][id][0] = false
		check(J._cross_traffic_inside(key,eastbound.get_instance_id(),true), "entry remains blocking for " + property)
		westbound.set(property,previous)
	var old_pose: Transform3D = westbound.transform
	westbound.rotation.y = PI/4
	J.owners[key][id][0] = false
	check(J._cross_traffic_inside(key,eastbound.get_instance_id(),true), "turning hull still blocks conflicting approach")
	westbound.transform = old_pose
	westbound.position.x = 380.5
	westbound.rotation.y = PI/2
	check(J._cross_traffic_inside(key,eastbound.get_instance_id(),true), "aligned nose with rear still in turn preserves entry axis")
	westbound.transform = old_pose
	westbound.position.y = 12
	check(not J._completed_exit_axis(key,id,false) and not J.occupies(key,id), "other road elevation cannot authorize exit reclassification")
	westbound.transform = old_pose
	var bus = BUS.new()
	bus.position = westbound.position
	bus.rotation.y = westbound.rotation.y
	bus.route = route_w
	world.add_child(bus)
	bus.set_physics_process(false)
	bus.traffic = true
	check(bus.junction_collision_bodies().size() > 1 and not J._completed_exit_axis(key,bus.get_instance_id(),false), "real articulated vehicle conserves entry reservation")
	bus.free()
	# Different worlds do not even mutate each other's lease classification.
	var viewport := SubViewport.new()
	viewport.world_3d = World3D.new()
	root.add_child(viewport)
	var remote := VEHICLE.new()
	viewport.add_child(remote)
	remote.set_physics_process(false)
	J.owners[key][id][0] = false
	check(not J._cross_traffic_inside(key,remote.get_instance_id(),true) and not J.owners[key][id][0], "independent World3D neither blocks nor mutates the owner")
	viewport.free()
	J.register_signal(EAST,7.0)
	J._phase_frame = Engine.get_process_frames()
	J._phase_time = J.CYCLE*.5 + 1.0 - J._offset(EAST)
	check(J.signal_state(key,Vector3.RIGHT) == "red", "red phase fixture uses real shared signal clock")
	check(not J.request(key,eastbound.get_instance_id(),Vector3.RIGHT,1.0,0), "completed turn cannot bypass requested red signal")
	J._signals.clear()
	setup_graph()
	committed(westbound,EAST,Vector3.FORWARD)
	committed(eastbound,WEST,Vector3.BACK)
	var start_w: Vector3 = westbound.position
	var start_e: Vector3 = eastbound.position
	for car in [westbound,eastbound]: car.set_physics_process(true)
	for frame in 720: await physics_frame
	check(westbound.position.x < start_w.x-12 and eastbound.position.x > start_e.x+12, "both real sedans clear the opposing reservation cycle under normal traffic physics")
	check(not J.owners.get(key,{}).has(id) and not J.owners.get(J.key_of(WEST),{}).has(eastbound.get_instance_id()), "completed physical departure releases upstream leases normally")
	print("TURN_TRACE west=",westbound.position," east=",eastbound.position)
	world.free()
	print("TURN_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
