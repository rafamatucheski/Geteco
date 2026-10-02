extends SceneTree
## Regression: real Vehicle movement keeps support with floor snapping,
## traverses 12.5% slopes, falls off edges, and still collides with solids.
## Run sequentially with other Godot work. This test does not measure FPS.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const SLOPE := 0.125
var failures: Array[String] = []
var checks := 0
var stage: Node3D

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)
	print(("PASS " if value else "FAIL ") + message)

func frames(count: int) -> void:
	for i in count: await physics_frame

func new_stage() -> void:
	if is_instance_valid(stage):
		stage.free()
		await frames(3)
	stage = Node3D.new()
	root.add_child(stage)

func solid(at: Vector3, size: Vector3, pitch := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = at
	body.rotation.x = pitch
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	body.add_child(collider)
	stage.add_child(body)
	return body

func vehicle(point: Vector3, yaw := 0.0) -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = "sport_coupe"
	car.position = point
	car.rotation.y = yaw
	stage.add_child(car)
	car.set_external_driver(true)
	car.brake_input = true
	return car

func ramp_height(z: float) -> float:
	return clampf(2.5 - SLOPE*z, 0.0, 5.0)

func ramp_course() -> void:
	var angle := atan(SLOPE)
	# Top face satisfies y = 2.5 - 0.125*z; endpoints z=+/-20.
	solid(Vector3(0, 2.5-.1/cos(angle), 0), Vector3(12,.2,40.0/cos(angle)), angle)
	solid(Vector3(0,-.1,35),Vector3(12,.2,30))
	solid(Vector3(0,4.9,-35),Vector3(12,.2,30))

func traverse_ramp(descending: bool) -> void:
	await new_stage()
	ramp_course()
	var initial_z := -25.0 if descending else 25.0
	var car := vehicle(Vector3(0,ramp_height(initial_z)+.18,initial_z), PI if descending else 0.0)
	await frames(60)
	check(car.is_on_floor(), "slope start grounded: " + str(descending))
	car.brake_input = false
	car.throttle_input = 1.0
	var supported := 0
	var measured := 0
	var furthest := initial_z
	var worst_gap := 0.0
	var worst_below := 0.0
	for i in 360:
		await physics_frame
		var z: float = car.global_position.z
		furthest = maxf(furthest,z) if descending else minf(furthest,z)
		if absf(z) < 18.0:
			measured += 1
			if car.is_on_floor(): supported += 1
			var gap: float = car.global_position.y-ramp_height(z)
			worst_gap = maxf(worst_gap,gap)
			worst_below = minf(worst_below,gap)
		if (descending and z>25.0) or (not descending and z< -25.0): break
	var label := "downhill" if descending else "uphill"
	check(furthest > 24.0 if descending else furthest < -24.0,label+": traversed slope and both flat joins")
	check(measured>30 and float(supported)/maxi(measured,1)>.90,label+": supported throughout slope")
	# The car has a horizontal hull: its uphill end rests above centre terrain.
	check(worst_gap<car.half_length*SLOPE+.12,label+": no hovering above hull support")
	check(worst_below>-.025,label+": no penetration through ramp")
	check(absf(car.global_position.x)<.1,label+": no lateral collision drift")

func stopped_on_slope() -> void:
	await new_stage()
	ramp_course()
	var car := vehicle(Vector3(0,3.3,0))
	await frames(90)
	var start: Vector3 = car.global_position
	var supported := 0
	for i in 120:
		await physics_frame
		if car.is_on_floor(): supported += 1
	check(supported>=118,"parked slope: floor contact retained")
	check(car.global_position.distance_to(start)<.035,"parked slope: no creeping or vertical jitter")

func leave_edge() -> void:
	await new_stage()
	solid(Vector3(0,-.1,5),Vector3(12,.2,18)) # edge z=-4
	var car := vehicle(Vector3(0,.15,5))
	await frames(60)
	car.brake_input = false
	car.throttle_input = 1.0
	for i in 240:
		await physics_frame
		if car.global_position.y< -4: break
	check(car.global_position.z< -4-car.half_length,"edge: car drove beyond floor support")
	check(car.global_position.y< -3 and not car.is_on_floor(),"edge: gravity resumes, no invisible floor")
	check(car.velocity.y< -1,"edge: downward velocity grows after support ends")

func wall_contact() -> void:
	await new_stage()
	solid(Vector3(0,-.1,0),Vector3(30,.2,40))
	solid(Vector3(0,1.5,-7),Vector3(12,3,.5))
	var car := vehicle(Vector3(0,.15,5))
	await frames(60)
	car.brake_input = false
	car.throttle_input = 1.0
	await frames(240)
	check(car.global_position.z>= -6.75+car.half_length-.04,"wall: real hull cannot pass through wall")
	check(car.global_position.z<0,"wall: car reached obstacle")
	check(car.is_on_floor() and car.global_position.y>-.025,"wall: contact preserves floor support")

func moving_body_contact() -> void:
	await new_stage()
	solid(Vector3(0,-.1,0),Vector3(30,.2,40))
	var car := vehicle(Vector3(0,.15,0))
	await frames(60)
	var body := RigidBody3D.new()
	body.mass = 2500
	body.collision_layer = 4
	body.collision_mask = 7
	body.position = Vector3(0,.61,6)
	body.lock_rotation = true
	body.continuous_cd = true
	body.linear_velocity = Vector3(0,0,-10)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8,1.2,2.0)
	collider.shape = box
	body.add_child(collider)
	stage.add_child(body)
	var nearest := INF
	var worst_overlap := 0.0
	for i in 120:
		await physics_frame
		var gap: float = body.global_position.z-car.global_position.z
		nearest = minf(nearest,gap)
		worst_overlap = maxf(worst_overlap,car.half_length+1.0-gap)
	check(nearest<car.half_length+1.15,"moving rigid body: reached parked vehicle")
	check(worst_overlap<.08,"moving rigid body: no interpenetration through parked hull")
	check(car.is_on_floor() and car.global_position.y>-.025,"moving rigid body: contact retains support")

func run() -> void:
	await traverse_ramp(false)
	await traverse_ramp(true)
	await stopped_on_slope()
	await leave_edge()
	await wall_contact()
	await moving_body_contact()
	if is_instance_valid(stage): stage.free()
	print("VEHICLE_FLOOR_CONTACT checks=",checks," failures=",failures.size())
	quit(1 if not failures.is_empty() else 0)
