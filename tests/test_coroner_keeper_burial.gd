extends SceneTree
const Fixtures := preload("res://tests/test_cemetery_keeper_home.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	Engine.max_fps = 0
	root.get_node("CampaignState").reset_campaign()
	root.get_node("NPCMedicalCare").set_process(false)
	root.get_node("CoronerCare").set_process(false)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var weather := Fixtures.ClockStub.new()
	weather.time_of_day = .45
	weather.is_dark = false
	weather.add_to_group("day_night_manager")
	world.add_child(weather)
	var manager := Fixtures.TestInteriors.new()
	manager.name = "Interiors"
	world.add_child(manager)
	var cemetery := preload("res://world/harbor/HarborCemetery.gd").new()
	world.add_child(cemetery)
	for i in 5: await physics_frame
	var home: Node = cemetery.get_node("KeeperHouse")
	var keeper: Node2D = home.keeper
	for i in 3000:
		if home.state=="working": break
		await physics_frame
	var initial := keeper.global_position
	var goal: Vector2 = cemetery.to_global(cemetery._plots[0])
	root.get_node("CoronerCare").records()["keeper_job"] = {"phase":"burial"}
	var accepted: bool = keeper.request_burial("keeper_job",goal)
	var completed := false
	for i in 3000:
		await physics_frame
		if keeper.burial_work >= 5:
			completed = true
			break
	var correct := accepted and completed and keeper.global_position.distance_to(goal+Vector2(-24,0))<12 and keeper.global_position.distance_to(initial)>30
	print("KEEPER_BURIAL accepted=",accepted," completed=",completed," position=",keeper.global_position," goal=",goal," work=",keeper.burial_work)
	keeper.finish_burial()
	correct = correct and keeper.burial_identity.is_empty() and home.state=="walking_to_work"
	world.queue_free()
	for i in 3: await process_frame
	print("CORONER_KEEPER ","PASS" if correct else "FAIL")
	quit(0 if correct else 1)
