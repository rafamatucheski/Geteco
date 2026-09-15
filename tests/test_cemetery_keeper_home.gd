extends SceneTree

class TestInteriors extends HarborInteriorManager:
	func _build_all_interiors() -> void:
		var spaces := Node2D.new()
		spaces.name = "InteriorSpaces"
		add_child(spaces)
	func _bind_exterior_entrances() -> void: pass

class ClockStub extends Node:
	signal time_changed(is_dark: bool)
	var is_dark := true
	var time_of_day := .02
	var interior_mode := false
	func set_interior_mode(value: bool) -> void: interior_mode = value

class PlayerStub extends CharacterBody2D:
	var is_dead := false
	var is_arrested := false
	var hits := 0
	var collectibles_found: Array = []
	func take_damage(_amount: int, _from_player := false) -> void: hits += 1

var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)

func run() -> void:
	create_timer(40).timeout.connect(func(): printerr("KEEPER_HOME TIMEOUT"); quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var weather := ClockStub.new()
	weather.add_to_group("day_night_manager")
	world.add_child(weather)
	var actor := PlayerStub.new()
	actor.add_to_group("player")
	actor.collision_layer = 4
	actor.collision_mask = 1
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 6
	collision.shape = circle
	actor.add_child(collision)
	var camera := Camera2D.new()
	camera.name = "Camera"
	actor.add_child(camera)
	world.add_child(actor)
	var manager := TestInteriors.new()
	manager.name = "Interiors"
	world.add_child(manager)
	root.get_node("CampaignState").set_campaign_flag(&"cemetery_keeper_dead", false)
	root.get_node("CampaignState").set_campaign_flag(&"cemetery_keeper_secret_known", false)
	root.get_node("WantedManager").reset_crime()
	var cemetery := preload("res://world/harbor/HarborCemetery.gd").new()
	cemetery.name = "Cemetery"
	world.add_child(cemetery)
	for i in 4: await process_frame
	var home = cemetery.get_node("KeeperHouse")
	var keeper = home.keeper
	var room = home.room
	var original_id: int = keeper.get_instance_id()
	check(get_nodes_in_group("cemetery_keeper").size() == 1, "Exactly one resident owns the cottage")
	var population := preload("res://systems/PopulationActivity.gd").new()
	check(population._pinned(keeper, Rect2(-100,-100,200,200)), "Remote cottage resident remains simulated outside the camera area")
	check(keeper.sleeping and keeper.get_parent() == room, "After midnight the keeper starts in his bed")
	check(keeper.model.shovel.get_parent() == keeper.model.right_hand_mount, "Real 3D shovel is attached to the hand")
	check(keeper.find_children("*", "Line2D", false, false).is_empty(), "Oversized floating 2D shovel removed")
	check(home.has_node("HouseFootprint") and room.walls_body.get_child_count() >= 9, "House and projected furniture have physical collision")
	check(home.is_sleep_time(), "00:28 is inside sleeping schedule")
	actor.global_position = home._outside_approach()
	for i in 3: await physics_frame
	check(not keeper.hostile and keeper.shots_fired == 0, "Passing the house at night does not provoke gunfire")
	check(home.entrance.request_interaction(actor), "Real entrance accepts a nearby player")
	await create_timer(.6).timeout
	check(room.contains_point(actor.global_position) and weather.interior_mode, "Entrance transitions into the playable room")
	check(home.state == "waking", "Intrusion first wakes the resident with a warning")
	await create_timer(2.8).timeout
	check(keeper.hostile and keeper.shots_fired > 0 and actor.hits > 0, "Woken keeper shoots real projectiles at the intruder")
	check(root.get_node("WantedManager").current_stars == 0, "Keeper gunfire does not falsely blame the player")
	actor.global_position = room.exit_door.global_position + Vector2(0, -18)
	for i in 3: await physics_frame
	check(room.exit_door.request_interaction(actor), "Interior exit stays usable during confrontation")
	await create_timer(.5).timeout
	check(actor.global_position.distance_to(home._outside_approach()) < 1 and not weather.interior_mode, "Exit returns to the exact cottage door")
	var shots_before: int = keeper.shots_fired
	await create_timer(2).timeout
	check(keeper.shots_fired == shots_before and not keeper.hostile, "Keeper stops firing when the intruder leaves")
	# Complete the safe bedside route; advance only the clock, never create an NPC.
	if home.state == "going_to_bed":
		keeper.global_position = keeper.route[keeper.route.size()-1]
		keeper._physics_process(.1)
	# Cancel an intrusion during the get-up animation; its tween must not later
	# pull a sleeping keeper back off the bed or turn him hostile after escape.
	actor.global_position = room.spawn_point.global_position
	home._process(.01)
	check(home.state == "waking", "A new intrusion wakes the sleeping resident")
	actor.global_position = home._outside_approach()
	home._process(.01)
	check(home.state == "going_to_bed" and not home._wake_tween.is_running(), "Quick escape cancels the unfinished wake animation")
	keeper.global_position = keeper.route[keeper.route.size()-1]
	keeper._physics_process(.1)
	check(keeper.sleeping and not keeper.hostile, "Cancelled confrontation returns to actual sleeping pose")
	weather.time_of_day = .25
	for i in 2: await process_frame
	check(not home.is_sleep_time() and home.state == "leaving_home", "At 06:00 the same resident gets up for work")
	keeper.global_position = keeper.route[keeper.route.size()-1]
	keeper._physics_process(.1)
	check(home.state == "walking_to_work" and keeper.get_parent() == home, "Resident exits through his door instead of spawning at the gate")
	check(keeper.get_instance_id() == original_id, "Morning and night use the same resident")
	home.reveal_secret()
	check(root.get_node("CampaignState").has_campaign_flag(&"cemetery_keeper_secret_known"), "Daytime clue is stored in campaign state")
	weather.time_of_day = 23.6 / 24.0
	for i in 2: await process_frame
	check(home.state == "returning_home", "Resident physically heads home before midnight")
	home._on_route_finished()
	home._on_route_finished()
	check(home.state == "home_evening" and not keeper.sleeping, "Early return allows evening conversation before bedtime")
	weather.time_of_day = 0.0
	home._process(.01)
	check(home.is_sleep_time(), "Midnight rollover is correctly classified")
	check(keeper.sleeping, "Resident goes to bed at midnight after returning home")
	check(room.contains_point(room.spawn_point.global_position), "Room spawn remains inside saved-room bounds")
	keeper.take_damage(100, true)
	home._process(300)
	check(keeper.is_dead and keeper.get_instance_id() == original_id and root.get_node("CampaignState").has_campaign_flag(&"cemetery_keeper_dead"), "Dead resident stays dead instead of respawning on a timer")
	manager.set_process(false)
	world.queue_free()
	await process_frame
	print("CEMETERY_KEEPER_HOME ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
