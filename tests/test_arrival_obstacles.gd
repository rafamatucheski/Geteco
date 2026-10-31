extends SceneTree

var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message); push_error(message)

func solid(parent: Node3D, point: Vector3, size: Vector3, layer := 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	parent.add_child(body)
	body.position = point
	return body

func scenario(queue: bool, sealed: bool, sidewalk := false) -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	solid(scene, Vector3(0,-.5,-30), Vector3(16,1,100))
	if sidewalk:
		solid(scene,Vector3(6,.075,-30),Vector3(4,.15,80))
		solid(scene,Vector3(-6,.075,-30),Vector3(4,.15,80))
	var car := preload("res://runtime/ArrivalCar.gd").new()
	scene.add_child(car)
	car.position = Vector3(0,.04,0)
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0,0,-60))
	curve.set_meta("traffic_open",true)
	curve.set_meta("lane_sections",[{"a":Vector3(-2,0,5),"b":Vector3(-2,0,-70),"width":8.0,"lanes":1}])
	car.route = curve
	car.traffic = true
	car.controlled = true
	# A missão é dona da recuperação de batida do carro de passageiro controlado. Roda
	# também esse dono real; um carro controlado sozinho fica de propósito parado
	# depois que o StreetPhysics o suspende num impacto.
	var passenger := preload("res://runtime/ArrivalActor.gd").new()
	scene.add_child(passenger)
	passenger.collision_layer = 0
	passenger.collision_mask = 0
	passenger.set_physics_process(false)
	var arrival := preload("res://runtime/Arrival.gd").new()
	scene.add_child(arrival)
	arrival.configure({"ready_for_play":true,"state":{"place_id":""},"world":{"player":passenger,"gameplay":{"health":100}}})
	arrival.car = car
	arrival.route = curve
	arrival.active = true
	arrival.riding = true
	arrival.phase = "city_tour"
	arrival._caption = 3
	arrival._caption_wait = 500
	# A parked car / a stationary three-car queue. The full opposite lane
	# contains a distant object: requiring 22m clear hides the shorter escape.
	for index in (3 if queue else 1):
		solid(scene,Vector3(0,1,-10-index*6),Vector3(2,2,4),4)
	solid(scene,Vector3(-4,1,-36),Vector3(2,2,4),4)
	if sealed: solid(scene,Vector3(0,1,-10),Vector3(16,2,2))
	if sidewalk: solid(scene,Vector3(0,1,-10),Vector3(8,2,2),4)
	var reached := false
	var overlapped := false
	var sidewalk_used := false
	var hull := PhysicsShapeQueryParameters3D.new()
	hull.shape = car.rotation_shape
	hull.collision_mask = 4
	hull.exclude = [car.get_rid()]
	for frame in 2400:
		await physics_frame
		if car.position.y>.1 and absf(car.position.x)>4.0: sidewalk_used = true
		hull.transform = Transform3D(car.global_basis,car.to_global(car.shape.position))
		if not scene.get_world_3d().direct_space_state.intersect_shape(hull,1).is_empty(): overlapped = true
		if car.position.z < (-30 if queue else -18): reached = true; break
	check(not reached if sealed else reached,"sealed street stays solid" if sealed else ("Maciota passes stationary queue" if queue else "Maciota passes parked obstacle"))
	check(car.collision_mask == 7,"bypass retains world, pedestrian and vehicle collisions")
	check(not overlapped,"M8 passes without overlapping the parked hulls")
	if sidewalk: check(sidewalk_used,"sealed road is bypassed on the raised sidewalk")
	if sealed:
		arrival._physics_process(61.0)
		check(arrival.riding and not arrival.flags.get("harbor_city_tour_complete",false),"long obstruction keeps passenger aboard and mission pending without giving up")
	check(absf(car.position.y) < (.2 if sidewalk else .1),"M8 remains supported on the street/kerb")
	var rear := solid(scene,car.position+car.global_basis.z*4+Vector3.UP,Vector3(2,2,.25),4)
	await physics_frame
	check(not car._rear_clear(),"rear sweep rejects a thin obstacle between sparse probe positions")
	rear.free()
	print("ARRIVAL_OBSTACLE queue=",queue," sealed=",sealed," position=",car.position," bypass=",car.bypass_side)
	print("ARRIVAL_CLEARANCE left=",car._lane_clear(-3.4,[0.0,5.0,10.0])," right=",car._lane_clear(2.6,[0.0,5.0,10.0])," blocked_time=",car.blocked_time," stall=",car.stall_time," traffic=",car.traffic," health=",car.health," junction=",car.junction_wait," hull=",car.rotation_shape.size," center=",car.shape.position)
	arrival.riding = false
	scene.free()
	await physics_frame

func run() -> void:
	if "--sidewalk-only" in OS.get_cmdline_user_args():
		await scenario(false,false,true)
		print("ARRIVAL_SIDEWALK failures=",failures)
		quit(0 if failures.is_empty() else 1)
		return
	await scenario(false,false)
	await scenario(true,false)
	await scenario(false,true)
	await scenario(false,false,true)
	print("ARRIVAL_OBSTACLES failures=",failures)
	quit(0 if failures.is_empty() else 1)
