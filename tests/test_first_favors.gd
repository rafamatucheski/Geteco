extends SceneTree
## Production integrations: bank passage/receipt, versioned delivery and real
## flatbed load/unload. Fixture travel is explicit; it does not certify a route.
var failures: Array[String] = []
var checks := 0
var world: Node2D
var player: CharacterBody2D
var mission: Node
var bridge: Node

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("FIRST_FAVORS ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
func frames(count := 4) -> void:
	for i in count: await physics_frame
func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless" or not "--capture" in OS.get_cmdline_user_args(): return
	var folder := "D:/geteco/artifacts/chapter-one-0913"
	DirAccess.make_dir_recursive_absolute(folder)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label+".png")) == OK, "rendered evidence saved: "+label)
func dismiss() -> void:
	for i in 15:
		if mission.phase == "story_dialogue": mission.advance_dialogue()
		elif bridge._dialog.visible: bridge._next_message()
		else: break
func run() -> void:
	create_timer(240,true,false,true).timeout.connect(func(): printerr("FIRST_FAVORS_TIMEOUT"); quit(2))
	var state := root.get_node("CampaignState")
	state.reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	root.get_node("SaveManager").set("_save_dir", OS.get_temp_dir().path_join("geteco_first_favors_%d" % OS.get_process_id())+"/")
	root.get_node("SaveManager").set("_save_directory_ready", false)
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met"]: state.set_campaign_flag(StringName(flag),true)
	world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready: await process_frame
	await frames(10)
	player = world.get_node("Player")
	mission = world.campaign_controller
	bridge = world.get_node("CobraCampaign")
	player.active_weapon_id = "fists"
	check(not mission.accept_mission("primeiro_giro"), "remote acceptance rejected")
	player.global_position = mission.garage.mission_board.global_position+Vector2(0,25)
	await frames()
	world.weather.time_of_day = .9
	check(mission.accept_mission("primeiro_giro"), "board accepts first favor")
	check(mission.phase == "story_dialogue", "briefing is explicit, not an automatic collection")
	dismiss()
	check(mission.phase == "delivery_bank", "first objective is bank")
	check(absf(world.weather.time_of_day-10.0/24.0)<.01, "accepting schedules bank visit at ten AM")
	player.global_position = mission._pickup_position()
	check(not mission.interact_with_objective() and not state.has_campaign_flag(&"harbor_delivery_picked_up"), "cannot skip bank by visiting parcel first")
	# Older in-progress save retains original itinerary, without inventing a receipt.
	state.set_campaign_flag(&"harbor_first_favors_v3",false)
	mission.start_or_resume()
	check(mission.phase == "delivery_pickup", "legacy delivery remains playable")
	state.set_campaign_flag(&"harbor_first_favors_v3",true)
	mission.start_or_resume()
	var favors: RefCounted = mission.first_favors
	var bank: Node2D = favors.bank_room()
	var door: Node2D = favors.bank_door()
	player.global_position = door.to_global(Vector2(0,55))
	player.reset_physics_interpolation()
	await frames(60)
	check(not mission.interact_with_objective(), "normal receipt cannot be collected from outside")
	Input.action_press("move_up")
	for i in 180:
		await physics_frame
		if bank.actor_inside(): break
	Input.action_release("move_up")
	await frames(55)
	check(bank.actor_inside(), "player physically walks through bank entrance")
	player.global_position = bank.civilians[0].global_position+Vector2(0,48)
	await frames()
	check(mission.interact_with_objective(), "Helena interaction opens bank conversation")
	await capture("bank-helena-dialogue")
	dismiss()
	check(state.has_campaign_flag(&"harbor_delivery_receipt") and mission.phase == "delivery_pickup", "receipt unlocks collection after conversation")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(state.to_save_data()))
	check(state.restore_from_save(snapshot), "mission flags survive real campaign serialization")
	mission.start_or_resume()
	check(mission.phase == "delivery_pickup", "resume does not repeat bank transaction")
	# Exit through the same real threshold before fixture travel to the port.
	player.global_position = bank.spawn_point.global_position
	Input.action_press("move_down")
	for i in 180:
		await physics_frame
		if not bank.actor_inside(): break
	Input.action_release("move_down")
	await frames(55)
	check(not bank.actor_inside() and not player.has_meta("robbery_room"), "bank exit restores exterior actor")
	player.global_position = mission._pickup_position()
	await frames()
	check(mission.interact_with_objective(), "paid parcel collected on foot")
	check(mission.phase == "delivery_return", "parcel guides player back to Maciota")
	var money_before: int = player.money
	player.global_position = mission.entrance.get_node("OutsideReturn").global_position
	player.reset_physics_interpolation()
	await frames(8)
	check(mission.entrance.request_interaction(player), "garage exterior door accepts return with parcel")
	await create_timer(1.1).timeout
	check(mission.garage.contains_point(player.global_position), "return uses real garage entry and camera transition")
	player.global_position = mission.garage.jager_npc.global_position+Vector2(0,45)
	await frames()
	check(mission.interact_with_objective(), "Maciota receives parcel through conversation")
	await capture("maciota-delivery-dialogue")
	check(player.money == money_before, "reward waits for delivery conversation")
	dismiss()
	check(state.has_campaign_flag(&"harbor_delivery_complete") and player.money == money_before+150, "delivery pays exactly 150")
	var personal := get_first_node_in_group("personal_car_manager")
	var delivery_deadline := Time.get_ticks_msec()+30000
	while personal.delivery_in_progress and Time.get_ticks_msec()<delivery_deadline: await process_frame
	check(not personal.delivery_in_progress, "Monaliza delivery animation finishes before follow-up")
	dismiss()
	mission._complete_delivery()
	check(player.money == money_before+150, "repeated completion cannot duplicate reward")
	# Contact recovery: use production ledger, NPC conversation and TowService.
	player.global_position = bridge.runtime.WORKSHOP+Vector2(0,45)
	check(bridge.runtime.start_mission("cobra_contact"), "Ferrugem follow-up starts")
	dismiss()
	check(bridge.runtime.interact(), "Ferrugem authorizes recovery")
	dismiss()
	var recovery: RefCounted = bridge.runtime._story_tow
	check(bridge.runtime.stage == 1 and is_instance_valid(recovery.vehicle), "contact requires an actual recovery")
	if not is_instance_valid(recovery.vehicle): finish(); return
	# Failure boundaries must release this reservation and offer an honest retry.
	var reserved: Node2D = recovery.vehicle
	player.is_arrested = true
	bridge.runtime._physics_process(.3)
	check(bridge.runtime.active_id.is_empty() and not reserved.has_meta("story_tow_authorized"), "arrest aborts recovery and releases reserved car")
	player.is_arrested = false
	dismiss()
	check(bridge.runtime.start_mission("cobra_contact"), "recovery is available after arrest")
	dismiss()
	check(bridge.runtime.interact(), "recovery can restart from Ferrugem")
	dismiss()
	player.is_dead = true
	bridge.runtime._physics_process(.3)
	check(bridge.runtime.active_id.is_empty() and player.money == money_before+150, "death aborts without granting contact reward")
	player.is_dead = false
	dismiss()
	check(bridge.runtime.start_mission("cobra_contact"), "recovery is available after hospitalization")
	dismiss()
	check(bridge.runtime.interact(), "hospitalization retry recreates recovery reservation")
	dismiss()
	var service: Node = recovery.service
	var yard: Node2D = recovery.yard
	var truck: Node2D = service.truck
	var target: Node2D = recovery.vehicle
	check(not yard.eligible(target) and service.can_tow(target), "authorized story car can be towed but cannot be crushed")
	check(yard.ledger().data.contract.is_empty(), "story does not create a paid salvage contract")
	# Driving the customer's car directly to the bay cannot fake a recovery.
	target.global_position = yard.to_global(yard.dock)
	recovery.tick(.3)
	check(bridge.runtime.stage == 1, "delivery without using flatbed is rejected")
	truck.global_position = yard.to_global(Vector2(170,440))
	truck.global_rotation = 0
	truck.velocity = Vector2.ZERO
	target.global_position = truck.to_global(Vector2(-115,0))
	target.global_rotation = 0
	target.velocity = Vector2.ZERO
	await frames()
	check(service.attach(target), "real winch loads authorized car with collision queries")
	recovery.tick(.3)
	check(bridge.runtime.stage == 2 and service.cargo == target, "cargo stage only begins after real load")
	service.snapshot()
	check(yard.ledger().data.tow_vehicle.cargo.get("story_tow_authorized",false), "loaded mission cargo persists its identity in save")
	player.global_position = truck.global_position+Vector2(-40,40)
	truck.enter_vehicle(player)
	while truck.has_meta("vehicle_boarding"): await process_frame
	await frames()
	var driven_start: Vector2 = truck.global_position
	Input.action_press("move_up")
	await create_timer(.45).timeout
	Input.action_release("move_up")
	check(truck.is_driven_by_player and truck.global_position.distance_to(driven_start)>2, "real accelerator moves loaded narrative flatbed")
	check(target.global_position.distance_to(truck.global_position)<18, "customer car follows the driven flatbed")
	truck.velocity = Vector2.ZERO
	await capture("neco-loaded-flatbed")
	root.get_node("WantedManager").reset()
	var slot := "story_loaded_%d" % OS.get_process_id()
	check(root.get_node("SaveManager").save_game(slot).get("success",false), "save real campaign while driving loaded flatbed")
	check(root.get_node("SaveManager").load_game(slot).get("success",false), "load saved narrative flatbed")
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	await scene_changed
	world = current_scene
	while not world.gameplay_ready: await process_frame
	await frames(12)
	player = world.get_node("Player")
	mission = world.campaign_controller
	bridge = world.get_node("CobraCampaign")
	yard = get_first_node_in_group("chop_shop")
	service = yard.tow_service
	truck = service.truck
	target = service.cargo
	check(is_instance_valid(target) and target.has_meta("story_tow_authorized"), "scene reload restores narrative cargo identity")
	var trucks := 0
	var story_cars := 0
	for candidate in get_nodes_in_group("vehicle"):
		if String(candidate.name) == "NecoTowTruck": trucks += 1
		if candidate.has_meta("story_tow_authorized"): story_cars += 1
	check(trucks == 1 and story_cars == 1 and truck.is_driven_by_player, "restore creates exactly one truck, customer car and driver")
	if not is_instance_valid(target): finish(); return
	check(bridge.runtime.active_id.is_empty(), "interrupted contact returns to its explicit retry checkpoint")
	truck.force_exit_vehicle()
	await create_timer(.9).timeout
	player.global_position = bridge.runtime.WORKSHOP+Vector2(0,40)
	check(bridge.runtime.start_mission("cobra_contact"), "loaded campaign permits contact retry")
	dismiss()
	check(bridge.runtime.interact(), "Ferrugem recognizes already loaded recovery on retry")
	dismiss()
	recovery = bridge.runtime._story_tow
	check(recovery.vehicle == target and bridge.runtime.stage == 2, "retry reuses exact restored cargo without another vehicle")
	truck.global_position = yard.to_global(yard.dock)+Vector2(112,0)
	truck.global_rotation = 0
	truck.velocity = Vector2.ZERO
	await frames()
	check(service.unload(), "real winch unloads onto clear delivery bay")
	recovery.tick(.3)
	check(bridge.runtime.stage == 3, "unloading requires Neco's confirmation")
	player.global_position = yard.npc.global_position+Vector2(0,40)
	check(bridge.runtime.interact(), "Neco hands over signed work order")
	dismiss()
	check(bridge.runtime.stage == 4 and player.money == money_before+150, "Neco does not pay a second salvage reward")
	player.global_position = bridge.runtime.WORKSHOP+Vector2(0,40)
	check(bridge.runtime.interact(), "Ferrugem recognizes Vicente signature")
	dismiss()
	check(bridge.ledger.get_status("cobra_race").available, "race unlocks only after actual car recovery")
	check(player.money == money_before+270, "contact pays existing 120 once")
	check(not yard.eligible(target), "repaired customer car remains protected from press")
	finish()

func finish() -> void:
	print("FIRST_FAVORS_RESULT checks=%d failures=%d %s" % [checks, failures.size(), str(failures)])
	quit(0 if failures.is_empty() else 1)
