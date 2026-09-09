extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func _run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	root.get_node("CampaignState").set_campaign_flag(&"harbor_delivery_complete",true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 25: await process_frame
	var world := current_scene
	var stream := world.get_node("ContinuousWorld")
	await stream.ensure_mountain()
	while not stream.ready_for_crossing: await process_frame
	var player: Node2D = world.get_node("Player")
	var travel := root.get_node("RegionTravel")
	player.global_position = Vector2(8000,-4529)
	player.money=4321
	player.mountain_thermal_coat=true
	player.world_pickups_collected.append("mountain_cargo_treasure")
	var car := ModernTrafficFactory.spawn_parked_vehicle(world,"SaveProbe",player.global_position,0,"summit_suv",0,Color("804dc0"))
	car.health=73
	car.enter_vehicle(player)
	stream._update_region()
	var state: Dictionary = JSON.parse_string(JSON.stringify(player.serialize()))
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(travel.snapshot_world()))
	car.exit_vehicle()
	car.queue_free()
	await process_frame
	player.restore(state)
	travel.pending_world=snapshot
	travel.finish_arrival(world)
	var restored: Node2D = travel.controlled_car()
	check(restored!=null and restored.health==73,"JSON save restores occupied damaged car")
	check(restored.global_position.distance_to(Vector2(8000,-4529))<1,"global coordinates not offset twice")
	check(player.money==4321 and player.mountain_thermal_coat and player.world_pickups_collected.has("mountain_cargo_treasure"),"money coat and unique loot survive")
	restored.exit_vehicle()
	restored.queue_free()
	await process_frame
	player.global_position=Vector2(6200,500)
	travel.pending_world={"region":"mountain","temperature":61,"weather_clock":53}
	travel.finish_arrival(world)
	check(player.global_position==Vector2(10500,-4460),"old isolated mountain coordinates migrate once")
	check(stream.mountain.cold_controller.current_temperature==61,"old temperature restored")
	var before: Vector2=player.global_position
	travel.finish_arrival(world)
	check(player.global_position==before,"migration is not repeated")
	var room: Node2D=stream.mountain.interior_manager.cabin_interior
	player.global_position=room.get_node("SpawnPoint").global_position
	travel.pending_world={"region":"mountain","coordinates_version":2,"interior":"mountain_cabin","exterior_return":[11650,-4230]}
	travel.finish_arrival(world)
	check(player.get_meta("mountain_interior",false) and player.get_meta("police_exterior_position",Vector2.ZERO)==Vector2(11650,-4230),"saved room restores exterior pursuit anchor")
	stream.mountain.interior_manager._on_exit_requested(null,player,&"",null,&"",&"mountain_cabin")
	check(player.global_position==Vector2(11650,-4230) and not player.has_meta("police_exterior_position"),"saved room exit returns into same world")
	print("CONTINUOUS SAVE FAILURES: ",failures)
	quit(0 if failures.is_empty() else 1)
