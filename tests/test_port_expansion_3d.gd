extends SceneTree

## Real V2 session: streamed logistics, boarding/return, physical hold and V1 car.
var world
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok: return
	failures.append(message)
	push_error(message)

func settle(frames: int) -> void:
	for _index in frames: await physics_frame

func run() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for _index in 500:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		check(false,"Main V2 must start")
		quit(1)
		return
	var session = world.session
	check(world.production.no_save,"Test must isolate the personal save")
	session.weather.time_of_day = .40
	var quay := Vector3(298.0,.08,211.0)
	world.player.teleport(quay)
	world.production.region.set_focus(quay)
	await settle(180)
	var logistics = session.urban_operations.cargo_handling
	check(logistics.active and logistics.work_trucks.size() == 3,"Quay logistics activate")
	check(logistics.find_children("PortFreightRouteFloor*","StaticBody3D",false,false).size() == 8,"Freight road keeps floor support beyond streamed player chunks")
	var ready_trucks := 0
	var first_truck_position := Vector3.ZERO
	for state in logistics.work_trucks:
		var truck = state.truck
		if is_instance_valid(truck) and truck.visible and not truck.has_meta("awaiting_ground"):
			ready_trucks += 1
			if first_truck_position == Vector3.ZERO: first_truck_position = truck.global_position
		print("PORT_TRUCK ",state.phase," point=",truck.global_position if is_instance_valid(truck) else "missing"," awaiting=",truck.get_meta("awaiting_ground",false) if is_instance_valid(truck) else "missing")
	check(ready_trucks == 3,"Three physical freight trucks appear on their route")
	await settle(90)
	var first_state: Dictionary = logistics.work_trucks[0]
	check(is_instance_valid(first_state.truck) and first_state.truck.global_position.distance_to(first_truck_position) > 1.0,"Freight truck actually drives toward the crane")
	check(float(first_state.depot_offset) > float(first_state.stop_offset),"Loaded truck has a downstream warehouse stop")
	first_state.phase = "loading"
	logistics.cranes[0].clock = 19.95
	logistics._tick_crane(0,.1)
	check(bool(first_state.loaded) and first_state.truck.get_meta("port_container_loaded",false),"Crane loads the physical truck bed")
	first_state.phase = "delivering"
	first_state.remaining = .01
	first_state.truck.speed = 0.0
	logistics._tick_truck(0,.05)
	check(not first_state.loaded and int(first_state.deliveries) == 1 and first_state.phase == "approach","Depot unload returns the carrier to the next circuit")
	var hatch := Vector3(4250.0/16.0,.08,2980.0/16.0)
	world.player.teleport(hatch)
	world.production.region.set_focus(hatch)
	await settle(35)
	check(await session.enter_place("santa_mare_hold",false),"Deck hatch boards the cargo hold")
	if session.room != null and session.state.place_id == "santa_mare_hold":
		check(session.room.solid_bodies.size() >= 8,"Cargo racks and bulkheads have physical collision")
		var rack_hit := false
		for body in session.room.solid_bodies:
			if body.name == "PortCargoRacks" and body.collision_layer == 1: rack_hit = true
		check(rack_hit,"Visible port rack has a matching solid collider")
		var rack_ray := PhysicsRayQueryParameters3D.create(session.room.to_global(Vector3(-6.0,1.0,-4.0)),session.room.to_global(Vector3(-6.0,1.0,3.0)),1)
		var rack_contact: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(rack_ray)
		check(not rack_contact.is_empty() and (rack_contact.collider as Node).name == "PortCargoRacks","Player-height path cannot cross the cargo rack")
		check(session.room.reward_points.size() == 1,"Hidden chest has one persistent reward")
		check(session.room_npcs.size() == 2,"Two native 3D crew occupy clear floor")
		check(is_equal_approx(world.camera.target_size,14.5),"Hold uses close stable camera")
		if session.room.reward_points.size() == 1:
			var treasure: Dictionary = session.room.reward_points[0]
			world.player.teleport(treasure.position + Vector3.UP*.08)
			await settle(3)
			session._collect_reward(session.room)
			check(session.state.world_state.rewards.has("santa_mare_hidden_chest_01"),"Chest grants its treasure once")
			check(treasure.visual.consumed,"Collected treasure starts its absorption")
			await create_timer(.35).timeout
			check(not treasure.visual.visible,"Collected treasure vanishes without blocking the aisle")
		check(session.leave_place(),"Hold returns to ship deck")
		check(world.player.global_position.distance_to(hatch) < 2.0,"Exit returns to original hatch")
		check(await session.enter_place("santa_mare_hold",false),"Hold remains enterable after reward collection")
		if session.room != null and session.state.place_id == "santa_mare_hold":
			check(not session.room.reward_points[0].visual.visible,"Treasures do not duplicate after re-entry")
			check(session.leave_place(),"Second exit returns to hatch")
	var parking := Vector3(7050.0/16.0,.08,2290.0/16.0)
	world.player.teleport(parking + Vector3(2,0,3))
	world.production.region.set_focus(parking)
	await settle(100)
	var secret = session.urban_operations.secret_car.car
	check(is_instance_valid(secret) and secret.vehicle_id == "ashbend_copper_coupe","Original corner parking has the copper secret car")
	if is_instance_valid(secret):
		check(secret.archetype == "cobra_v8" and secret.paint_color == Color("9f673f"),"Secret car is the driveable copper coupe")
		secret.controlled = true
		await settle(35)
		check(bool(session.state.world_state.get("ashbend_secret_car_claimed",false)),"Discovery is persistent after taking the car")
		check(preload("res://gameplay/urban_v1/CobraSecretCar3D.gd").validate_record(session.state.world_state.get("ashbend_secret_car",{})),"Secret car pose and condition have a valid save record")
		var saved_car: Dictionary = session.state.world_state.get("ashbend_secret_car",{}).duplicate(true)
		check(not saved_car.is_empty(),"Taking the secret car records its pose")
		secret.controlled = false
		session.controller.vehicles.erase(secret)
		secret.queue_free()
		await settle(3)
		session.urban_operations.secret_car.car = null
		session.urban_operations.secret_car._process(.36)
		await settle(3)
		var restored = session.urban_operations.secret_car.car
		check(is_instance_valid(restored) and restored.vehicle_id == "ashbend_copper_coupe" and restored.paint_color.to_html(false) == saved_car.get("paint",""),"Claimed secret car restores its identity and paint")
	print("PORT_EXPANSION_3D failures=",failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
