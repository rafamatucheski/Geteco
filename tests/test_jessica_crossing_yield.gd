extends SceneTree
## Cruzamento recíproco na Market: o dono real do trânsito normal espera o
## Jetta parado. A única recuperação é uma ré física apoiada fora
## do cruzamento. O Main continua responsável por banco/procurado/trânsito em streaming.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const DRIVER := preload("res://gameplay/jessica/JessicaGetawayDriver.gd")
const SIGNALS := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
const CENTER := Vector3(137,0,78)
var failures: Array[String] = []
var checks := 0
var rear_fixture_point := Vector3(120,.12,79.84)
var expect_clear := false

func _initialize() -> void:
	create_timer(35).timeout.connect(func(): push_error("Jessica crossing-yield bounded timeout"); quit(3))
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

func pin_phase(time: float) -> void:
	SIGNALS._phase_frame = Engine.get_process_frames()
	SIGNALS._phase_time = time-SIGNALS._offset(CENTER)

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	solid(stage,Vector3(90,.10,40),Vector3(135,-.05,80))
	var car: CharacterBody3D = parked(stage,"jessica_jetta_gli","jessica_jetta_gli",Vector3(127.0854,.12,79.85149),-1.57385587692261)
	var owner: CharacterBody3D = parked(stage,"sport_coupe","crossing_owner",Vector3(133.6629,.12,79.19783),1.76980602741241)
	# A pose traseira é uma fixture explícita de folga local, não um fato faltando no rastreio.
	var rear: CharacterBody3D = parked(stage,"nimbus_minivan","rear_queue",rear_fixture_point,-PI*.5)
	for i in 45: await physics_frame
	var car_start: Vector3 = car.global_position
	var owner_start: Vector3 = owner.global_position
	var rear_start: Vector3 = rear.global_position
	var graph: Dictionary = {"vertices":[CENTER,CENTER+Vector3(35,0,0),CENTER-Vector3(35,0,0),CENTER+Vector3(0,0,35),CENTER-Vector3(0,0,35)],
		"edges":{0:[{"to":1},{"to":2},{"to":3},{"to":4}]}}
	SIGNALS.configure(graph)
	# Reproduz o vão de parada registrado (~0.127m) na pose registrada do Jetta.
	SIGNALS.register_signal(CENTER,7.375)
	var key: Vector3i = SIGNALS.key_of(CENTER)
	var curve := Curve3D.new()
	curve.add_point(Vector3(110,0,79.85149))
	curve.add_point(Vector3(170,0,79.80))
	curve.set_meta("traffic_open",true)
	car.set("route",curve)
	var driver = DRIVER.new()
	driver.setup(car,curve)
	# Uma saída suave do trânsito normal do braço norte para a Market, tangente à
	# pose registrada do dono. O prefixo histórico fornece o braço real de chegada dele.
	var owner_curve := Curve3D.new()
	owner_curve.bake_interval = .15
	owner_curve.add_point(Vector3(139.5,0,62),Vector3.ZERO,Vector3(0,0,4))
	owner_curve.add_point(Vector3(139.5,0,74),Vector3(0,0,-4),Vector3(0,0,4))
	owner_curve.add_point(Vector3(133.6629,0,79.19783),Vector3(3.92105,0,-.790797),Vector3(-3.92105,0,.790797))
	owner_curve.add_point(Vector3(120,0,84.4),Vector3(4,0,-.6),Vector3(-4,0,.6))
	owner_curve.add_point(Vector3(95,0,84.4),Vector3(4,0,0),Vector3.ZERO)
	owner_curve.set_meta("traffic_open",true)
	owner.set("route",owner_curve)
	owner.set("route_distance",owner_curve.get_closest_offset(owner.global_position))
	owner.set("_junction_route",owner_curve)
	var junctions: Array = SIGNALS.along(owner_curve)
	owner.set("_junction_list",junctions)
	pin_phase(16.0)
	check(SIGNALS.signal_state(key,Vector3.RIGHT) == "red" and SIGNALS.signal_state(key,Vector3.BACK) == "green","real signal retains Jetta and releases the entered owner axis")
	check(SIGNALS.occupies(key,owner.get_instance_id()) and not SIGNALS.occupies(key,car.get_instance_id()),"only the actual owner hull occupies the crossing at spawn")
	check(SIGNALS.request(key,owner.get_instance_id(),Vector3.BACK,-2,0),"post-spawn owner checkpoint receives a genuine native reservation")
	owner.set("_held_junction",key)
	var owner_crossing_offset: float = INF
	for junction: Dictionary in junctions:
		if junction.key == key:
			owner_crossing_offset = float(junction.offset)
			owner.set("_held_offset",owner_crossing_offset)
	check(is_finite(owner_crossing_offset),"normal owner curve resolves the same occupied crossing")
	owner.set("traffic",true)
	for i in 15:
		pin_phase(16.0)
		driver.tick(1.0/60.0,false)
		await physics_frame
	check(owner.get("blocked") == true and owner.get("blocker") == car,"normal traffic sensor proves reciprocal blocking against Jetta")
	check(SIGNALS.has_reservation(key,owner.get_instance_id()) and SIGNALS.occupies(key,owner.get_instance_id()),"reciprocal owner still holds its occupied native token")
	if not failures.is_empty(): await finish(stage,car,owner); return
	var minimum_x: float = car.global_position.x
	var contacts_free := true
	var grounded := true
	var retained_before_clear := true
	var owner_cleared := false
	var clock_preserved := true
	var previous_wait: float = driver._traffic_wait_seconds
	for i in 900:
		if not SIGNALS.occupies(key,owner.get_instance_id()): owner_cleared = true
		pin_phase(.1 if owner_cleared else 16.0)
		driver.tick(1.0/60.0,false)
		await physics_frame
		minimum_x = minf(minimum_x,car.global_position.x)
		grounded = grounded and car.is_on_floor() and owner.is_on_floor() and rear.is_on_floor()
		if not owner_cleared:
			retained_before_clear = retained_before_clear and not SIGNALS.has_reservation(key,car.get_instance_id()) and car.global_position.x <= car_start.x+.05
			if driver._yielding: clock_preserved = clock_preserved and driver._traffic_wait_seconds+.05 >= previous_wait
		previous_wait = driver._traffic_wait_seconds
		for body: CharacterBody3D in [car,owner]:
			for index in body.get_slide_collision_count():
				var other: Object = body.get_slide_collision(index).get_collider()
				contacts_free = contacts_free and other != car and other != owner and other != rear
		if owner_cleared and driver._yield_completed > 0 and car.global_position.x > 132: break
	check(driver._yield_attempts > 0 and driver._yield_attempts <= 3,"bounded local reverse is actually exercised")
	check(driver._sensor_lease_grants > 0,"physically admitted native short sensor lease is actually exercised")
	check(not owner.has_meta("jessica_sensor_yield_owner"),"the local sensor permission is revoked after physical crossing clearance")
	check(minimum_x < car_start.x-1.0 and driver.recoveries == 0,"yield uses physical reverse rather than a crossing S maneuver")
	if expect_clear:
		check(owner_cleared and driver._yield_completed > 0 and owner.global_position.distance_to(owner_start) > 3 and car.global_position.x > 132,"available rear room lets both vehicles progress through native traffic control")
	else:
		check(not owner_cleared and driver._yield_completed == 0 and car.global_position.x < car_start.x,"insufficient rear room preserves crossing retention instead of simulating passage")
		check(driver._sensor_lease_diagnostic.get("reason","") == "owner_hull_overlap","whole owner hull explains the restricted-case refusal")
		# Avalia o prazo existente sem gastar outro ciclo real.
		# Só o timestamp decorrido desta fixture avança; corpos, curvas, máscaras,
		# fases nativas e reservas mantêm o estado físico observado.
		driver._traffic_wait_started -= ceili(SIGNALS.CYCLE*1000.0)
		pin_phase(16.0)
		driver.tick(1.0/60.0,false)
		check(driver.traffic_wait_expired,"restricted passage reaches the bounded flow-failure decision")
		driver.tick(1.0/60.0,true)
		check(float(owner.get("unjam_time")) == 0 and not owner.has_meta("jessica_sensor_yield_owner"),"bounded failure revokes only the local permission")
	check(retained_before_clear and clock_preserved,"reverse preserves the red retention, native priority and waiting episode clock")
	check(rear.global_position.distance_to(rear_start) < .05 and rear.collision_layer == 4,"rear car remains present and collidable")
	check(car.collision_mask == 7 and owner.collision_mask == 7 and not car.get_collision_exceptions().has(owner) and not car.get_collision_exceptions().has(rear),"recovery never disables masks or introduces collision exceptions")
	check(grounded and contacts_free,"all actors retain ground and the yielded maneuver touches no vehicle hull")
	print("JESSICA_CROSSING_YIELD_STATE ",JSON.stringify({"car":str(car.global_position),"owner":str(owner.global_position),"rear":str(rear.global_position),
		"minimum_x":minimum_x,"owner_cleared":owner_cleared,"driver":driver.debug_snapshot(),
		"owner_sensor_lease_time":owner.get("unjam_time"),"owner_sensor_lease_tag":owner.get_meta("jessica_sensor_yield_owner",0),
		"expected_clear":expect_clear,"deadline_clock_assessment":not expect_clear,
		"fixture_limit":"recorded Jetta/owner poses, authored smooth normal traffic exit and explicit conservative rear-car fixture"}))
	await finish(stage,car,owner)

func finish(stage: Node3D, car: CharacterBody3D, owner: CharacterBody3D) -> void:
	car.call("_release_junction")
	owner.call("_release_junction")
	stage.queue_free()
	for i in 3: await physics_frame
	print("JESSICA_CROSSING_YIELD_RESULT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
