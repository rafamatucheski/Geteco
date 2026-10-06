extends SceneTree
## Local physical clearance at the recorded Market queue. This fixture tests
## geometry and signal retention; Main owns live traffic chains and the bank.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const DRIVER := preload("res://gameplay/jessica/JessicaGetawayDriver.gd")
const SIGNALS := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	create_timer(35).timeout.connect(func(): push_error("Jessica vehicle-queue bounded timeout"); quit(3))
	run.call_deferred()

func solid(parent: Node3D, size: Vector3, point: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = point
	parent.add_child(body)

func parked(parent: Node3D, archetype: String, id: String, point: Vector3, yaw: float) -> CharacterBody3D:
	var car = VEHICLE.new()
	car.archetype = archetype
	car.vehicle_id = id
	car.position = point
	car.rotation.y = yaw
	parent.add_child(car)
	return car

func pin_phase(center: Vector3, phase_time: float) -> void:
	# Only this fixture pins the shared phase clock, as the existing signal
	# visual-sync regression does. Product clocks and bodies are unchanged.
	SIGNALS._phase_frame = Engine.get_process_frames()
	SIGNALS._phase_time = phase_time-SIGNALS._offset(center)

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	solid(stage,Vector3(80,.10,16),Vector3(130,-.05,80))
	solid(stage,Vector3(80,.30,.20),Vector3(130,.15,72))
	solid(stage,Vector3(80,.30,.20),Vector3(130,.15,88))
	var car: CharacterBody3D = parked(stage,"jessica_jetta_gli","jessica_jetta_gli",Vector3(109.6355,.12,79.75542),-1.5636568069458)
	var front: CharacterBody3D = parked(stage,"cobra_v8","queue_front",Vector3(116.1219,.12,79.83942),-1.57066118717194)
	# The trace did not record the rear archetype. A real Nimbus hull is a
	# conservative 5.11x2.338m civilian envelope at the measured rear pose.
	var rear: CharacterBody3D = parked(stage,"nimbus_minivan","queue_rear",Vector3(102.672,.12,79.69102),-PI*.5)
	for i in 45: await physics_frame
	var front_start: Vector3 = front.global_position
	var rear_start: Vector3 = rear.global_position
	var car_start: Vector3 = car.global_position
	var front_health: float = front.get("health")
	var rear_health: float = rear.get("health")
	var center := Vector3(132,0,79.833333)
	var graph: Dictionary = {"vertices":[center,center+Vector3(30,0,0),center-Vector3(30,0,0),center+Vector3(0,0,30),center-Vector3(0,0,30)],
		"edges":{0:[{"to":1},{"to":2},{"to":3},{"to":4}]}}
	SIGNALS.configure(graph)
	SIGNALS.register_signal(center,7)
	var curve := Curve3D.new()
	curve.add_point(Vector3(109.6355,0,79.75542))
	curve.add_point(Vector3(160,0,79.833333))
	curve.set_meta("traffic_open",true)
	car.set("route",curve)
	var driver = DRIVER.new()
	driver.setup(car,curve)
	for i in 120:
		pin_phase(center,20.0)
		driver.tick(1.0/60.0,false)
		await physics_frame
	check(driver.recoveries == 0 and car.global_position.distance_to(car_start) < .05,"red retention preserves the stopped front/rear queue")
	var grounded := true
	var contacts_free := true
	var travelled := 0.0
	var before: Vector3 = car.global_position
	for i in 900:
		pin_phase(center,.1)
		driver.tick(1.0/60.0,false)
		await physics_frame
		grounded = grounded and car.is_on_floor() and car.global_position.y > -.1
		for contact_index in car.get_slide_collision_count():
			var collider: Object = car.get_slide_collision(contact_index).get_collider()
			contacts_free = contacts_free and collider != front and collider != rear
		travelled += Vector2(car.global_position.x-before.x,car.global_position.z-before.z).length()
		before = car.global_position
		if car.global_position.x > 130 and driver._bypass_curve == null: break
	check(car.global_position.x > 130 and driver._bypass_curve == null,"real throttle, adaptive reverse and steering complete the vehicle bypass")
	check(driver.recoveries > 0 and driver.recoveries <= 3,"bounded recovery is actually exercised")
	check(driver._reverse_distance < 4.5 and driver._planned_radius >= 2.5/tan(.48),"the plan fits measured rear room and real steering radius")
	check(front.global_position.distance_to(front_start) < .05 and rear.global_position.distance_to(rear_start) < .05,"both physical queue vehicles stay present at their measured poses")
	check(front.collision_layer == 4 and rear.collision_layer == 4 and car.collision_mask == 7,"all car collisions remain active")
	check(not car.get_collision_exceptions().has(front) and not car.get_collision_exceptions().has(rear),"queue collision is never bypassed")
	check(float(front.get("health")) >= front_health and float(rear.get("health")) >= rear_health,"recovery clears whole hulls without impact damage")
	check(contacts_free,"neither vehicle hull is touched during the actual maneuver")
	check(grounded and travelled > 20,"the entire maneuver uses physical displacement and ground support")
	print("JESSICA_VEHICLE_QUEUE_STATE ",JSON.stringify({"car":str(car.global_position),"front":str(front.global_position),"rear":str(rear.global_position),"travelled":travelled,
		"fixture_limit":"front Cobra and conservative real Nimbus rear hull; native signal, no live traffic deadlock",
		"driver":driver.debug_snapshot()}))
	car.call("_release_junction")
	stage.queue_free()
	for i in 3: await physics_frame
	print("JESSICA_VEHICLE_QUEUE_RESULT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
