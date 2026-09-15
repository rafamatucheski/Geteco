extends SceneTree
const Layout = preload("res://world/mountain_pass/transit/MountainTransitVillageLayout.gd")
const OUTPUT := "D:/geteco/artifacts/rodoviaria-gelo-0910"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	var capture := OS.get_cmdline_user_args().has("--capture")
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.get_node("SaveManager").clear_pending_save()
	var mountain = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	mountain.connect_to_harbor = false
	mountain.spawn_player_on_ready = false
	mountain.spawn_suv_on_ready = false
	root.add_child(mountain)
	current_scene = mountain
	while not mountain.region_ready: await process_frame
	print("MOUNTAIN_VILLAGE_READY")
	var village = mountain.get_node("MountainTransitVillage")
	var passengers = village.get_node("TransitPassengers")
	var camera := Camera2D.new()
	mountain.add_child(camera)
	camera.position = Vector2(7580, -1640)
	camera.zoom = Vector2.ONE * 1.45
	camera.make_current()
	var coach := Node2D.new()
	coach.name = "StoppedCoachFixture"
	coach.position = Layout.BERTH
	mountain.add_child(coach)
	var second := Node2D.new()
	mountain.add_child(second)
	check(passengers.receive_coach(coach), "First coach occupies single berth")
	check(passengers.receive_coach(coach) and passengers.trip_count == 1, "Repeated stop notification does not duplicate passengers")
	check(not passengers.receive_coach(second), "A second coach cannot occupy berth")
	check(passengers.history[0].winter_ready > 0 and passengers.history[0].shopping > 0, "Same arrival mixes winter clothing and shoppers")
	check(village.has_node("WinterShopEntrance"), "Winter clothing shop has real interactive entrance")
	var chalet_doors := 0
	for child in village.get_children():
		if child.name.begins_with("ChaletEntrance"): chalet_doors += 1
	check(chalet_doors == 4, "All four chalets have real entrances")
	var previous := {}
	var blocked_frames := {}
	for frame in 7200:
		await physics_frame
		if frame == 300 and capture:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT.path_join("01_vila_desembarque.png"))
		if frame == 1800 and capture:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT.path_join("02_loja_e_chales.png"))
		var inside := 0
		for traveler in passengers.travelers:
			if traveler.routine == "inside_chalet": inside += 1
			if traveler.visible and traveler.route_index < traveler.itinerary.size():
				var id: int = traveler.get_instance_id()
				if previous.has(id) and traveler.global_position.distance_to(previous[id]) < 0.02:
					blocked_frames[id] = blocked_frames.get(id, 0) + 1
				else: blocked_frames[id] = 0
				previous[id] = traveler.global_position
		if passengers.is_exchange_complete() and passengers.active_bus == coach:
			passengers.release_coach(coach)
		if inside == 5: break
	check(passengers.history[0].alighted == 5, "All five travelers physically alight")
	check(passengers.active_bus == null, "Berth releases after disembark")
	check(passengers.purchases == 2, "Both ordinary-clothes travelers visit shop and buy winter clothing")
	check(passengers.completed_rests > 0, "Travelers physically rest on village benches before continuing to chalets")
	for traveler in passengers.travelers:
		if traveler.routine != "inside_chalet":
			print("TRAVELER_ROUTE ",traveler.name," index=",traveler.route_index," itinerary=",traveler.itinerary," nav=",traveler._navigation.path)
			if traveler.route_index<traveler.itinerary.size():
				var target:Vector2=traveler.itinerary[traveler.route_index]
				var side:Vector2=traveler.global_position.direction_to(target).orthogonal()*9.0
				for offset in [Vector2.ZERO,side,-side]:
					var query:=PhysicsRayQueryParameters2D.create(traveler.global_position+offset,target+offset,3,[traveler.get_rid()])
					query.hit_from_inside=true
					var hit:Dictionary=traveler.get_world_2d().direct_space_state.intersect_ray(query)
					if not hit.is_empty():print("TRAVELER_ROUTE_RAY ",traveler.name," ",hit.position," ",hit.collider.get_path())
			for hit_index in traveler.get_slide_collision_count():
				print("TRAVELER_BLOCKER ", traveler.name, " ", traveler.get_slide_collision(hit_index).get_collider().get_path())
		check(traveler.winter_outfit and traveler.model.get_meta("winter_outfit", false), "Traveler wears real winter model: " + traveler.name)
		check(traveler.routine == "inside_chalet", "Traveler reaches chalet without crossing walls: %s at %s phase %s" % [traveler.name, traveler.global_position, traveler.routine])
	check(passengers.receive_coach(coach), "Next service can use the released platform")
	check(passengers.history.back().expected == 2 and passengers.travelers.size() == 2, "Next arrival brings two travelers and recycles only people inside chalets")
	for frame in 7200:
		await physics_frame
		var finished := true
		for traveler in passengers.travelers:
			finished = finished and traveler.routine == "inside_chalet"
		if finished: break
	check(passengers.history.back().alighted == 2 and passengers.purchases == 3, "Second arrival has two alight and one actual winter shopping visit")
	for traveler in passengers.travelers:
		check(traveler.routine == "inside_chalet", "Second service traveler reaches a chalet")
	print("MOUNTAIN_VILLAGE_RESULT ", {"arrivals": passengers.history, "purchases": passengers.purchases, "bench_rests": passengers.completed_rests, "failures": failures})
	mountain.queue_free()
	for frame in 4: await process_frame
	quit(0 if failures.is_empty() else 1)
