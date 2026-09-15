extends SceneTree
const SAFETY := preload("res://cars/VehicleMotionSafety.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, description: String) -> void:
	print(("PASS " if value else "FAIL ")+description)
	if not value: failures.append(description)
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	for drift in [0.8,0.95,1.15,1.35]:
		var v := Vector2(300,500)
		for i in 600:
			var next := SAFETY.grip(v,0,drift,1.0/60.0,1,true)
			if i == 599: check(next.is_finite() and next.length()<=v.length()+0.001,"grip never amplifies energy")
			v = next
		check(absf(v.y)<2,"wet handbrake still dissipates lateral velocity")
	for id in VehicleCatalog.VEHICLES:
		var spec := VehicleCatalog.get_vehicle_spec(id)
		check(ResourceLoader.exists(spec.model_class),id+" resolves to 3D body")
	var car = ModernTrafficFactory.spawn_parked_vehicle(world,"CrashCar",Vector2.ZERO,0,"sport_coupe",0,Color.RED)
	var obstacle = ModernTrafficFactory.spawn_parked_vehicle(world,"OtherCar",Vector2(140,0),0,"union_sedan",0,Color.BLUE)
	car.is_driven_by_player = true
	await physics_frame
	check(car.motion_mode == CharacterBody2D.MOTION_MODE_FLOATING and car.platform_floor_layers == 0,"no moving-platform velocity inheritance")
	check((car.collision_mask & obstacle.collision_layer)!=0,"vehicle collision mask includes cars")
	car.velocity = Vector2(500,0)
	for i in 40: await physics_frame
	print("CONTACT pos=",car.global_position," velocity=",car.velocity," other=",obstacle.global_position," masks=",car.collision_mask,"/",obstacle.collision_layer)
	check(car.global_position.x<105 and car.velocity.length()<1,"real driven vehicle stops at another car")
	car.global_position = Vector2(0,300)
	car.velocity = Vector2(120,500)
	for i in 60: await physics_frame
	check(car.global_position.distance_to(Vector2(0,300))<350 and car.velocity.length()<1,"sport coupe skid settles instead of launching")
	car.velocity = Vector2(1e30,1e30)
	var before: Vector2 = car.global_position
	await physics_frame
	await physics_frame
	check(car.global_position.distance_to(before)<35 and car.velocity.length()<=900,"extreme collision velocity cannot teleport vehicle")
	car.velocity = Vector2.INF
	await physics_frame
	await physics_frame
	check(car.global_position.is_finite() and car.velocity.is_finite(),"nonfinite velocity is rejected")
	car.is_driven_by_player = false
	car.global_position = Vector2(-500,500)
	car.velocity = Vector2.ZERO
	var lane := ModernTrafficFactory.create_lane(world,"BlockingLane",PackedVector2Array([Vector2(0,800),Vector2(900,800)]))
	var follower = ModernTrafficFactory.spawn_moving_vehicle(lane,"Follower","route_city",0.06,100,0)
	var parked = ModernTrafficFactory.spawn_parked_vehicle(world,"ParkedBlock",Vector2(290,800),0,"boxrunner",0)
	await physics_frame
	follower.set_process(false)
	for i in 240:
		follower.advance_on_lane(1.0/60.0)
		await physics_frame
	check(follower.global_position.x<220,"lane follower cannot pass through parked vehicle")
	check(not follower.has_nitro and not car.has_nitro and not parked.has_nitro,"all vehicle classes have no nitro")
	check(follower.is_3d_vehicle and car.is_3d_vehicle and parked.is_3d_vehicle,"legacy sports car and heavy traffic all render 3D")
	print("VEHICLE PHYSICS FAILURES: ",failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
