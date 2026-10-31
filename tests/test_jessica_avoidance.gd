extends SceneTree
## Regressão isolada com física real para um pedestre no para-choque dianteiro esquerdo.
## A integração no Main continua responsável pela IA real da polícia e pelo fluxo do banco.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const DRIVER := preload("res://gameplay/jessica/JessicaGetawayDriver.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	create_timer(25).timeout.connect(func(): push_error("Jessica avoidance bounded timeout"); quit(3))
	run.call_deferred()

func solid(parent: Node3D, size: Vector3, point: Vector3) -> StaticBody3D:
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
	return body

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	solid(stage,Vector3(60,.10,24),Vector3(15,-.05,0))
	# A real solid curb prevents escaping through the right-hand verge.
	solid(stage,Vector3(50,.35,.20),Vector3(10,.175,1.9))
	var person := CharacterBody3D.new()
	person.name = "FrontBumperOfficer"
	person.collision_layer = 2
	person.collision_mask = 7
	person.position = Vector3(3.04,0,-1.094)
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = 1.70
	collider.shape = capsule
	collider.position.y = .85
	person.add_child(collider)
	stage.add_child(person)
	person.add_to_group("v2_police_officers")
	var car := VEHICLE.new()
	car.archetype = "jessica_jetta_gli"
	car.vehicle_id = "jessica_jetta_gli"
	car.position.y = .12
	car.rotation.y = -PI*.5
	stage.add_child(car)
	for i in 45: await physics_frame
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(30,0,0))
	curve.set_meta("traffic_open",true)
	var driver := DRIVER.new()
	driver.setup(car,curve)
	var first_position: Vector3 = car.position
	var began := Time.get_ticks_msec()
	for i in 600:
		driver.tick(1.0/60.0,false)
		await physics_frame
		if car.position.x > 10: break
	check(car.position.x > 10,"real throttle, reverse and steering pass the bumper-blocking pedestrian")
	check(driver.recoveries > 0 and driver.recoveries <= 3,"bounded recovery is actually exercised")
	check(is_instance_valid(person) and person.collision_layer == 2,"officer remains present and collidable")
	check(not car.get_collision_exceptions().has(person),"officer collision was never bypassed")
	check(car.is_on_floor() and car.position.y > -.1,"getaway retains actual ground support")
	check(car.position.distance_to(first_position) > 10,"physical displacement is observable")
	print("JESSICA_AVOIDANCE_STATE ",JSON.stringify({"car":str(car.position),"officer":str(person.position),"ms":Time.get_ticks_msec()-began,"driver":driver.debug_snapshot()}))
	stage.queue_free()
	for i in 3: await physics_frame
	print("JESSICA_AVOIDANCE_RESULT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
