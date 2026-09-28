extends SceneTree
## Real Vehicle/Dispatch integration plus collision and high-speed tire sweep.
## Headless evidence verifies behavior only; rendered frame-time is separate.
const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
const TIRES := preload("res://gameplay/police_response/ground/TirePuncture.gd")
const BLOCK := preload("res://gameplay/police_response/ground/PoliceRoadblock.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []
var checks := 0
var groups: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print(("GROUND PASS " if ok else "GROUND FAIL ")+label)
	if not ok: failures.append(label)

func fixture() -> Dictionary:
	var bundle := KIT.build(self,KIT.grid_roads(),Vector3(0,.04,0))
	bundle.gameplay.set_physics_process(false)
	bundle.controller.set_physics_process(false)
	if is_instance_valid(bundle.gameplay.police_air): bundle.gameplay.police_air.set_physics_process(false)
	return bundle

func run() -> void:
	await dispatch_contract()
	await roadblock_and_tires()
	check(groups.size() == 2,"both integration groups completed")
	check(checks >= 25,"all required checks executed")
	print("POLICE_GROUND checks=%d failures=%s" % [checks,failures])
	quit(0 if failures.is_empty() else 1)

func dispatch_contract() -> void:
	var b := fixture()
	var game: Node3D = b.gameplay
	var controller: Node3D = b.controller
	await physics_frame
	game.register_crime(15,game.player.global_position)
	var patrol: RefCounted = controller.dispatch_police_to(game.last_known)
	check(patrol != null and patrol.variant == "patrol","one-star first response remains patrol")
	if patrol == null: KIT.teardown(b); return
	patrol.vehicle.set_physics_process(false)
	await physics_frame
	await physics_frame
	game.register_crime(20,game.last_known)
	var bike: RefCounted = controller.dispatch_police_to(game.last_known)
	check(bike != null and bike.variant == "motorcycle","second response at two stars sends a motorcycle")
	if bike == null: KIT.teardown(b); return
	bike.vehicle.set_physics_process(false)
	await physics_frame
	await physics_frame
	check(bike.vehicle.archetype == "bike_police" and bike.crew_capacity == 1,"motorcycle has one finite officer")
	bike._sync_motorcycle_rider()
	check(not bike.vehicle._motorcycle_rider_parts.is_empty() and bike.vehicle._motorcycle_rider_parts.all(func(p): return p.visible),"motorcycle officer is visible while seated")
	check(bike.vehicle.equipment.beacons.size() == 2,"motorcycle has working paired police beacons")
	check(RULES.response_variant(3,controller._active_police()) != "motorcycle","one motorcycle cap survives escalation")
	game.register_crime(420,game.last_known)
	var tactical: RefCounted = controller.dispatch_police_to(game.last_known)
	check(tactical != null and tactical.variant == "tactical","army crew precedes armored support")
	if tactical == null: KIT.teardown(b); return
	tactical.vehicle.set_physics_process(false)
	await physics_frame
	await physics_frame
	var tank: RefCounted = controller.dispatch_police_to(game.last_known)
	check(tank != null and tank.variant == "tank","six stars dispatch a physical tank")
	if tank == null:
		print("GROUND_DIAGNOSTIC ",controller.events_named("spawn_failed"))
		KIT.teardown(b)
		return
	tank.vehicle.set_physics_process(false)
	check(tank.vehicle.visual.has_node("TankTurret") and tank.vehicle.half_width > 1.5 and tank.vehicle.max_health == 3000,"tank silhouette matches a wide armored collision body")
	check(RULES.response_variant(6,controller._active_police()) != "tank","at most one active tank")
	check(not TIRES.puncture(tank.vehicle,4),"tracks are immune to tire spikes")
	game.set_meta("police_air_reserved_slots",4)
	check(controller.foot_officer_count() == 4,"rappel reservation reduces ground officer budget")
	game.set_meta("police_air_reserved_slots",0)
	await physics_frame
	check(bike._deploy_police_crew() and bike.officers.size() == 1 and bike.crew_remaining == 0,"single motor officer physically dismounts through clear space")
	bike._sync_motorcycle_rider()
	check(bike.vehicle._motorcycle_rider_parts.all(func(p): return not p.visible),"seated rider disappears after dismount")
	if not bike.officers.is_empty():
		var officer: CharacterBody3D = bike.officers[0]
		check(controller.take_agent_for_interior(officer) and bike.officers.is_empty() and bike.crew_remaining == 0,"interior transfer cannot regenerate a motorcycle officer")
		officer.queue_free()
	game.clear_wanted(true)
	patrol._tick_police(.02)
	tactical._tick_police(.02)
	check(patrol.state == "investigating" and tactical.state in ["recall","departing"] and controller.units.filter(func(u): return u.state == "investigating").size() == 1,"escape retains exactly one investigator and recalls the other crew")
	var contact_age: float = game.contact_age
	patrol._tick_police(.5)
	check(game.contact_age == contact_age and not game.last_known_valid,"investigator does not rediscover player merely by proximity")
	game.clear_wanted()
	patrol._tick_police(.02)
	check(patrol.state in ["recall","departing"],"clearing the case releases investigator")
	controller.dismiss_all("test_load")
	check(controller.units.is_empty() and controller.roadblocks.blocks.is_empty(),"load cleanup clears ground response")
	KIT.teardown(b)
	await process_frame
	groups.append("dispatch")

func roadblock_and_tires() -> void:
	var b := fixture()
	var game: Node3D = b.gameplay
	var controller: Node3D = b.controller
	await physics_frame
	game.register_crime(60,game.player.global_position)
	var roadblock: Node3D = controller.roadblocks.try_place(game.last_known)
	check(roadblock != null,"organized roadblock is placed on a reachable road outside view")
	if roadblock == null: KIT.teardown(b); return
	check(roadblock.global_position.distance_to(game.last_known) >= 35,"roadblock never materializes around player")
	await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(roadblock.to_global(Vector3(2.6,.5,-2)),roadblock.to_global(Vector3(2.6,.5,2)),1)
	var hit := controller.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and hit.collider is StaticBody3D and hit.collider.get_parent() == roadblock,"roadblock has real collision against cars and pedestrians")
	check(BLOCK.wheel_crosses_strip(Vector3(0,.1,-5),Vector3(0,.1,5),3.6),"swept tire contact catches a fast crossing")
	check(not BLOCK.wheel_crosses_strip(Vector3(3,.1,-5),Vector3(3,.1,5),3.6),"passing around strip does not puncture tires")
	check(not BLOCK.wheel_crosses_strip(Vector3(0,2,-5),Vector3(0,2,5),3.6),"vehicle above the road does not touch spikes")
	var car := VEHICLE.new()
	car.archetype = "coupe"
	b.scene.add_child(car)
	car.set_physics_process(false)
	car.position = roadblock.to_global(Vector3(0,.1,-7))
	car.rotation.y = roadblock.rotation.y
	var original_speed: float = car.handling.max_speed
	var original_grip: float = car.handling.drift_factor
	roadblock.sample_target(car,true)
	car.position = roadblock.to_global(Vector3(0,.1,7))
	check(roadblock.sample_target(car,true) and TIRES.snapshot(car) == 4,"physical target crossing punctures all four tires")
	check(car.handling.max_speed < original_speed*.5 and car.handling.drift_factor > original_grip,"puncture reduces maximum speed and real tire grip")
	check(not TIRES.puncture(car,4),"repeated contact never compounds identical damage")
	TIRES.repair_vehicle(car)
	await process_frame
	check(car.handling.max_speed == original_speed and car.handling.drift_factor == original_grip and TIRES.snapshot(car) == 0,"repair restores original driving limits and tire geometry")
	car.position = roadblock.to_global(Vector3(0,.1,-7))
	roadblock.sample_target(car,false)
	car.position = roadblock.to_global(Vector3(0,.1,7))
	check(not roadblock.sample_target(car,false) and TIRES.snapshot(car) == 0,"retracted spikes do not puncture vehicles during surrender")
	b.state.safe = true
	check(controller.roadblocks.try_place(Vector3.ZERO) == null,"garage rejects new roadblocks")
	b.state.safe = false
	controller.player_position_override = Vector3(0,0,0)
	check(controller.roadblocks.try_place(Vector3.ZERO) == null,"interior transition rejects roadblocks")
	controller.dismiss_all("test_travel")
	check(controller.roadblocks.blocks.is_empty(),"travel removes roadblock bodies and spike state")
	KIT.teardown(b)
	await process_frame
	groups.append("roadblocks")
