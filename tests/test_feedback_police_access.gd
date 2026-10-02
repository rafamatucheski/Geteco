extends SceneTree
const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
const POLICY := preload("res://gameplay/urban_v1/HarborPortPolicy.gd")
const DETAIL := preload("res://world/harbor_route_detail/HarborRouteDetail3D.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(35).timeout.connect(func(): push_error("FEEDBACK timeout"); quit(3))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("FEEDBACK ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for _i in count: await physics_frame

func run() -> void:
	var bundle := KIT.build(self,KIT.grid_roads(),Vector3(0,.04,-8))
	var dispatch = bundle.controller
	var game = bundle.gameplay
	dispatch.set_physics_process(false)
	game.set_physics_process(false)
	await frames(3)
	game.register_crime(240,bundle.player.position)
	check(game.stars == 4,"old six-star total now reaches four; high tiers take longer")
	game.register_crime(180,bundle.player.position)
	check(game.stars == 6 and game.snapshot().crime_points == 420,"six stars reached and new crime total persists")
	check(RULES.MAX_ACTIVE[6] == 5 and RULES.FOOT_LIMIT[6] == 10,"six-star response admits five vehicles and ten officers (reinforcements halved)")
	var unit = dispatch.dispatch_police_to(bundle.player.position)
	check(unit != null,"dispatch creates a real unit through the road router")
	if unit != null:
		var car = unit.vehicle
		check(car.archetype == "police_transport" and unit.crew_remaining == 6,"tactical van carries six officers")
		check(car.max_health == 380 and car.equipment.beacons.size() >= 2,"van has actual durability and working beacon materials")
		var fleet := preload("res://runtime/FleetState.gd")
		car.equipment.siren_on = true
		check(fleet.validate(fleet.capture(car,"harbor")),"tactical van and active siren are valid for save/restore")
		for _i in 1200:
			unit.tick(1.0/60.0)
			game.health = 100
			await physics_frame
			if unit.officers.size() == 6: break
		check(unit.officers.size() == 6 and unit.crew_remaining == 0,"all six officers disembark from actual arriving van")
		var armed := true
		for officer in unit.officers: armed = armed and officer.weapon_id == "m4a1"
		check(unit.officers.size() == 6 and armed,"six-star team is equipped with rifles")
		var origin: Vector3 = car.global_position
		for officer in unit.officers: officer.receive_damage(10000,bundle.player)
		unit.tick(1.0/60.0)
		await frames(90)
		check(unit.finished and unit.end_reason == "crew_depleted" and is_instance_valid(car),"dead crew leaves a parked car and releases dispatch slot")
		check(car.global_position.distance_to(origin) < .08 and not car.controlled and not car.external_input,"empty van never drives away")
		check(car.is_in_group("drivable") and not car.get_meta("dispatch_unit",false),"abandoned van remains available for theft")
		dispatch.units.erase(unit)
		car.controlled = true
		dispatch._tidy_wrecks()
		check(not car in dispatch.wrecks,"taken van no longer belongs to dispatch cleanup")
		dispatch.deployed_this_pursuit = RULES.DEPLOYMENT[6]
		dispatch._last_stars = 6
		dispatch._police_clock = 0.0
		dispatch._dispatch_police(.1)
		check(not dispatch.units.is_empty() and dispatch.deployed_this_pursuit > RULES.DEPLOYMENT[6],"six-star reinforcements continue beyond the old cumulative budget")
		car.queue_free()
	# Geometry from the actual route-detail factory, queried at both lane centers.
	var zone := DETAIL._build_connecting_streets()
	bundle.scene.add_child(zone)
	await frames(3)
	for z in [121.2,123.8]:
		var query := PhysicsRayQueryParameters3D.create(Vector3(83,.06,z),Vector3(90,.06,z),1)
		check(bundle.scene.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"street beside police is clear across sidewalk/curb at z="+str(z))
	check(POLICY.is_private_road({"id":"salvage_access"}) and POLICY.is_private_road({"id":"westgate_service_lane"}) and not POLICY.is_private_road({"id":"union_avenue"}),"Neco/workshop access excluded, public avenue preserved")
	KIT.teardown(bundle)
	await frames(2)
	print("FEEDBACK_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
