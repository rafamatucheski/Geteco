extends "res://tests/test_jessica_avoidance.gd"
## A largada renderizada no banco: policial colidível na frente, cupê próprio atrás.
## Isto confere os envelopes físicos registrados, não a IA viva de perseguição.

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	solid(stage,Vector3(80,.10,24),Vector3(65,-.05,27))
	solid(stage,Vector3(80,4,.20),Vector3(65,2,30.625))
	var person := CharacterBody3D.new()
	person.name = "BankBumperOfficer"
	person.collision_layer = 2
	person.collision_mask = 7
	person.position = Vector3(49.78926,0,26.21395)
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = 1.70
	collider.shape = capsule
	collider.position.y = .85
	person.add_child(collider)
	stage.add_child(person)
	person.add_to_group("v2_police_officers")
	var rear := VEHICLE.new()
	rear.archetype = "sport_coupe"
	rear.name = "PlayerCoupe"
	rear.position = Vector3(40.62514,.12,28.501)
	rear.rotation.y = -PI*.5
	stage.add_child(rear)
	var car := VEHICLE.new()
	car.archetype = "jessica_jetta_gli"
	car.vehicle_id = "jessica_jetta_gli"
	car.position = Vector3(46.625,.12,27.15)
	car.rotation.y = -PI*.5
	stage.add_child(car)
	for i in 45: await physics_frame
	var rear_start: Vector3 = rear.global_position
	var car_health: float = car.health
	var rear_health: float = rear.health
	var curve := Curve3D.new()
	curve.add_point(Vector3(46.625,0,27.15))
	curve.add_point(Vector3(80,0,26.75167))
	curve.set_meta("traffic_open",true)
	var driver := DRIVER.new()
	driver.setup(car,curve)
	var grounded := true
	var contacts_free := true
	for i in 1200:
		driver.tick(1.0/60.0,false)
		await physics_frame
		grounded = grounded and car.is_on_floor()
		for index in car.get_slide_collision_count():
			var hit = car.get_slide_collision(index).get_collider()
			contacts_free = contacts_free and hit != person and hit != rear
		if car.global_position.x > 60 and driver._bypass_curve == null: break
	check(car.global_position.x > 60 and driver._bypass_curve == null,"ordinary reverse and steering pass the officer with the rear coupe present")
	check(driver.recoveries > 0 and driver.recoveries <= 3 and driver._reverse_distance < 4.5,"short supported recovery is actually used")
	check(rear.global_position.distance_to(rear_start) < .05 and rear.health >= rear_health,"rear coupe stays intact at its actual pose")
	check(person.collision_layer == 2 and rear.collision_layer == 4 and car.collision_mask == 7,"officer and both vehicles retain their collision contracts")
	check(contacts_free and car.health >= car_health,"maneuver clears both obstacle bodies without impact")
	check(grounded and car.global_position.y > -.1,"entire maneuver keeps physical ground support")
	print("JESSICA_PEDESTRIAN_QUEUE_STATE ",JSON.stringify({"car":str(car.global_position),"rear":str(rear.global_position),"driver":driver.debug_snapshot()}))
	stage.queue_free()
	for i in 3: await physics_frame
	print("JESSICA_PEDESTRIAN_QUEUE_RESULT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
