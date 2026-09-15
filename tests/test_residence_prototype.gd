extends SceneTree

const VEHICLE_FACTORY := preload("res://world/shared/emergency/ModernTrafficFactory.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		failures.append(label)


func _run() -> void:
	create_timer(120.0).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280, 720)
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		campaign.set_campaign_flag(flag, true)
	# Purchase autosaves are part of the feature, but this test must never touch
	# a player's real autosave.
	var saves := root.get_node("SaveManager")
	saves._save_dir = OS.get_temp_dir().path_join("geteco_residence_test_%d" % Time.get_ticks_msec()) + "/"
	saves._save_directory_ready = false
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null or not current_scene.get("gameplay_ready"):
		await process_frame
	for i in 3:
		await process_frame

	var world := current_scene
	var manager: ResidenceManager = world.get_node("ResidencePrototype")
	var player := world.get_node("Player")
	player.set_physics_process(false)
	# The exit group also contains ResidenceManager, which is not a door.
	# Dispatch through the real interior handler to catch invalid door accesses.
	var interact := InputEventAction.new()
	interact.action = "interact"
	interact.pressed = true
	world.get_node("Interiors")._unhandled_input(interact)
	check(manager.is_in_group("harbor_interior_exit"), "residence interaction coexists with the interior exit handler")
	if OS.get_cmdline_user_args().has("--access-only"):
		player.money = 100000
		manager.purchase_home("canal_north")
		for frame in 3: await physics_frame
		check(_driveway_clear(manager.properties.canal_north),"north driveway with Monaliza parked")
		world.queue_free()
		await process_frame
		quit(0 if failures.is_empty() else 1)
		return
	check(manager.properties.size() == 3 and manager.residence_interiors.size() == 3, "three prototype residences and interiors are integrated")
	check(manager.properties.westgate_garden.entrance_position().distance_to(Vector2(250, 216)) < 3.0, "west property matches the upper-left marked area")
	check(manager.properties.quayside_house.entrance_position().distance_to(Vector2(2775, 1736)) < 3.0, "quayside property matches the right marked area")
	check(manager.properties.canal_north.entrance_position().distance_to(Vector2(4915, -794)) < 3.0, "third property is in the upper neighborhood")

	player.money = 100000
	manager.open_purchase("westgate_garden")
	for frame in 3:
		await process_frame
	var purchase_rect := manager.menu.panel.get_global_rect()
	check(purchase_rect.position.y >= 20.0 and purchase_rect.end.y <= root.size.y - 20.0, "purchase panel fits inside a 720p viewport")
	manager.menu.close()
	var first_quote := manager.purchase_home("westgate_garden")
	check(first_quote.affordable and first_quote.due == 10000 and player.money == 90000, "first purchase charges full price")
	check(manager.active_home_id() == "westgate_garden" and manager.get_checkpoint_spawn() == manager.properties.westgate_garden.checkpoint, "purchased house becomes the active checkpoint")
	var monaliza: Node2D = world.get_node("PersonalCarManager").car
	check(monaliza.global_position.distance_to(manager.properties.westgate_garden.monaliza_position()) < 1.0, "Monaliza transfers to the active home")

	player.owned_outfits["dante_suit"] = true
	check(manager.equip_outfit("dante_suit") and player.current_outfit_id == "dante_suit", "wardrobe equips only an owned outfit")
	check(not manager.equip_outfit("dante_arctic") and player.current_outfit_id == "dante_suit", "wardrobe rejects an unowned outfit")
	player.health = 20
	check(manager.use_food() and player.health == 55, "food restores 35 health without exceeding the maximum")
	player.health = player.max_health
	check(not manager.use_food(), "food is not consumed at full health")
	check(manager.set_time_period("day") and is_equal_approx(world.weather.time_of_day, 0.36), "bed advances time to day")
	check(manager.set_time_period("night") and is_equal_approx(world.weather.time_of_day, 0.84), "bed advances time to night")
	for frame in 3: await process_frame
	check(absf(world.weather.time_of_day-.84)<.01, "chosen night persists after the campaign updates its clock")
	player.weapon_inventory.shotgun = true
	check(manager.apply_loadout({"curta": "pistol", "longa": "shotgun", "corpo": "", "granada": ""}) and player.personal_loadout.longa == "shotgun", "home arsenal equips owned weapons")

	var extra := VEHICLE_FACTORY.spawn_parked_vehicle(world, "ResidenceTestCar", manager.properties.westgate_garden.garage_position(), 0.0, "sedan_classic", 0, Color("a8463b"))
	extra.enter_vehicle(player)
	var boarding_deadline := Time.get_ticks_msec() + 5000
	while extra.has_meta("vehicle_boarding") and Time.get_ticks_msec() < boarding_deadline:
		await process_frame
	check(extra.is_driven_by_player, "test vehicle uses the real boarding flow")
	check(manager.store_vehicle(extra) and manager.has_stored_vehicle(), "one non-Monaliza vehicle can be stored")
	await process_frame
	var retrieved := manager.retrieve_vehicle()
	check(is_instance_valid(retrieved) and not manager.has_stored_vehicle() and manager.state.stored_vehicle.status == "deployed", "stored vehicle can be retrieved outside")
	check(String(retrieved.active_archetype_id) == "sedan_classic", "retrieved vehicle preserves its archetype")

	var second_quote := manager.purchase_home("quayside_house")
	check(second_quote.refund == 7000 and second_quote.due == 18000 and player.money == 72000, "moving house credits 70 percent of the previous property")
	check(manager.active_home_id() == "quayside_house" and manager.has_stored_vehicle(), "moving house recalls and transfers the extra car")
	check(monaliza.global_position.distance_to(manager.properties.quayside_house.monaliza_position()) < 1.0, "moving house transfers Monaliza")
	var third_quote := manager.purchase_home("canal_north")
	check(third_quote.refund == 17500 and third_quote.due == 27500 and player.money == 44500, "second move applies the current home's trade-in value")

	check(manager.enter_home("canal_north"), "active residence accepts entry")
	var transition_deadline := Time.get_ticks_msec() + 3000
	while world.get_node("Interiors").is_transitioning() and Time.get_ticks_msec() < transition_deadline:
		await process_frame
	var room: ResidenceInterior = manager.residence_interiors.canal_north
	check(room.contains_point(player.global_position) and player.has_meta("harbor_interior"), "entry reaches the matching residence interior")
	check(room.art.find_children("*", "MeshInstance3D", true, false).size() > 100 and room.walls_body.get_child_count() > 10, "3D furnishings have projected physical walls and furniture")
	check(manager.map_position_for_actor(player) == manager.properties.canal_north.entrance_position(), "minimap maps the isolated interior back to its property")
	check(manager.exit_home("canal_north"), "residence exit starts")
	transition_deadline = Time.get_ticks_msec() + 3000
	while world.get_node("Interiors").is_transitioning() and Time.get_ticks_msec() < transition_deadline:
		await process_frame
	check(player.global_position.distance_to(manager.properties.canal_north.checkpoint_position()) < 1.0 and not player.has_meta("harbor_interior"), "residence exit returns to the correct exterior")

	player.global_position = Vector2(1500, 1500)
	player.is_arrested = false
	player._respawn_at_hospital()
	check(player.global_position.distance_to(manager.properties.canal_north.checkpoint_position()) < 1.0, "death recovery uses the purchased residence checkpoint")
	var save_data: Dictionary = JSON.parse_string(JSON.stringify(campaign.to_save_data()))
	campaign.reset_campaign()
	check(campaign.residence_state.is_empty(), "new campaign clears residence ownership")
	check(campaign.restore_from_save(save_data) and campaign.residence_state.active_home == "canal_north", "residence and garage state survive campaign save/load")
	player.set_physics_process(false)
	# A new, physically parked car must be found by SaveManager immediately,
	# without GUARDAR input or a manager processing frame between park/save.
	manager.state["stored_vehicle"] = {}
	var home: ResidenceProperty = manager.properties.canal_north
	var parked := VEHICLE_FACTORY.spawn_parked_vehicle(world,"NaturalParkingTest",home.extra_vehicle_position()+Vector2(0,65),0.0,"sedan_classic",0,Color("a8463b"))
	parked.health = 67
	manager.capture_parking_for_save()
	check(manager.state.stored_vehicle.is_empty(), "car outside marked bays is not claimed")
	parked.global_position = home.extra_vehicle_position()
	parked.velocity = Vector2.ZERO
	var wanted := root.get_node("WantedManager")
	wanted.restore({"current_stars":0,"crime_points":0,"time_hidden":0})
	var save_result: Dictionary = saves.save_game("residence_parking")
	check(save_result.get("success",false), "manual disk save accepts a naturally parked car")
	check(manager.deployed_vehicle == parked and manager.state.stored_vehicle.status == "parked" and parked.is_inside_tree(), "save recognizes the parked car without removing it from the world")
	var parked_position: Vector2 = parked.global_position
	var second_extra := VEHICLE_FACTORY.spawn_parked_vehicle(world,"ExtraCapacityTest",home.monaliza_position(),0.0,"sedan_classic",0,Color.WHITE)
	manager.capture_parking_for_save()
	check(manager.deployed_vehicle == parked, "a second extra vehicle cannot replace the saved car")
	second_extra.queue_free()
	check(saves.load_game("residence_parking").get("success",false), "saved parking slot can be loaded")
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null or not current_scene.get("gameplay_ready"):
		await process_frame
	for frame in 5: await process_frame
	world = current_scene
	manager = world.get_node("ResidencePrototype")
	check(is_instance_valid(manager.deployed_vehicle) and manager.deployed_vehicle.global_position.distance_to(parked_position)<1.0 and manager.deployed_vehicle.health==67, "scene reload restores the parked car at the same place with its damage")
	var saved_cars := 0
	for vehicle in get_nodes_in_group("vehicle"):
		if vehicle.get_meta("residence_stored_vehicle",false): saved_cars += 1
	check(saved_cars == 1, "reload creates exactly one saved extra car")
	player = world.get_node("Player")
	manager.deployed_vehicle.enter_vehicle(player)
	boarding_deadline = Time.get_ticks_msec()+5000
	while manager.deployed_vehicle.has_meta("vehicle_boarding") and Time.get_ticks_msec()<boarding_deadline:
		await process_frame
	check(manager.deployed_vehicle.is_driven_by_player, "restored parked car remains drivable")
	check(saves.save_game("residence_driving").get("success",false) and manager.state.stored_vehicle.status=="driven", "saving while driving delegates the owned car to world travel")
	check(saves.load_game("residence_driving").get("success",false), "driven residence vehicle save loads")
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null or not current_scene.get("gameplay_ready"): await process_frame
	world = current_scene
	manager = world.get_node("ResidencePrototype")
	boarding_deadline = Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<boarding_deadline:
		manager.capture_parking_for_save()
		if is_instance_valid(manager.deployed_vehicle) and manager.deployed_vehicle.is_driven_by_player: break
		await process_frame
	saved_cars = 0
	for vehicle in get_nodes_in_group("vehicle"):
		if vehicle.get_meta("residence_stored_vehicle",false): saved_cars += 1
	check(saved_cars==1 and is_instance_valid(manager.deployed_vehicle) and manager.deployed_vehicle.is_driven_by_player, "driven save restores the same car once without a duplicate at the house")
	for id in manager.properties:
		var property: ResidenceProperty = manager.properties[id]
		check(property.find_children("*","Label",true,false).is_empty(), "house has no decorative name labels: "+id)
		check(property.model.find_children("*","MeshInstance3D",true,false).size()>20, "exterior is a real 3D model: "+id)
		check(_driveway_clear(property), "driveway physically connects parking to street: "+id)
		check(_stations_reachable(manager.residence_interiors[id]), "all room interactions reachable from entrance: "+id)

	print("RESIDENCE PROTOTYPE FAILURES ", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _driveway_clear(property: ResidenceProperty) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 16.0
	query.shape = shape
	query.collision_mask = 1
	for i in range(1,property.driveway.size()):
		var a := property.to_global(property.driveway[i-1])
		var b := property.to_global(property.driveway[i])
		var steps := maxi(1,ceili(a.distance_to(b)/12.0))
		for step in steps+1:
			query.transform = Transform2D(0,a.lerp(b,float(step)/steps))
			var hits := property.get_world_2d().direct_space_state.intersect_shape(query,1)
			if not hits.is_empty():
				print("DRIVEWAY_BLOCKED ",property.property_id," point=",query.transform.origin," collider=",hits[0].collider.get_path())
				return false
	return true


func _stations_reachable(room: ResidenceInterior) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 10.0
	query.shape = shape
	query.collision_mask = 1
	var start := Vector2i.ZERO
	var pending: Array[Vector2i] = [start]
	var visited: Dictionary = {start:true}
	var reached: Dictionary = {}
	var cursor := 0
	while cursor < pending.size():
		var cell := pending[cursor]
		cursor += 1
		var point := room.spawn_point.global_position+Vector2(cell)*16.0
		for station in room.stations:
			if point.distance_to(room.to_global(station.position))<25.0: reached[station.kind]=true
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i = cell+offset
			if visited.has(next): continue
			visited[next]=true
			var candidate := room.spawn_point.global_position+Vector2(next)*16.0
			if not room.contains_point(candidate): continue
			query.transform=Transform2D(0,candidate)
			if room.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): pending.append(next)
	return reached.size()==5
