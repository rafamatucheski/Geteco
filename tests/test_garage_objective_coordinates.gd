extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)

func shown_metres(mission: Node) -> float:
	var text: String = mission._objective_label.text
	return text.get_slice("/", text.get_slice_count("/") - 1).strip_edges().trim_suffix(" m").to_float()

func _run() -> void:
	create_timer(80).timeout.connect(func(): quit(2))
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met"]:
		campaign.set_campaign_flag(flag, true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 30: await process_frame
	var world := current_scene
	var manager: Node = world.get_node("Interiors")
	var garage: Node2D = manager.garage_interior
	var player: Node2D = world.get_node("Player")
	var entrance: Node2D = world.get_node("District/Garage/Entrance")
	var mission: Node = world.get_node("ArrivalMission")
	mission._set_phase("board", tr("OBJ_BOARD"), entrance.global_position)
	manager._on_exterior_destination_requested(entrance, player, &"", null, &"", garage, garage.spawn_point)
	for i in 4: await physics_frame
	check(player.has_meta("police_exterior_position"), "Real entrance retains exterior mapping metadata")
	mission._refresh_objective()
	check(shown_metres(mission) < 15, "Board objective in garage stays within room-scale metres")
	check(mission.navigation_target == entrance.global_position, "City navigation keeps the exterior entrance instead of isolated room coordinates")
	var board: Node2D = garage.mission_board
	player.global_position = board.global_position
	mission._refresh_objective()
	check(shown_metres(mission) == 0, "Standing at the board displays zero metres despite exterior metadata")
	var board_floor: Vector2 = garage.showroom.unproject_floor(board.global_position)
	player.global_position = garage.to_global(garage.workshop_point(Vector3(board_floor.x - 2, 0, board_floor.y)))
	mission._refresh_objective()
	check(shown_metres(mission) == 2, "Two real workshop metres display two metres")
	for phase in ["meet_maciota", "delivery_return"]:
		mission.phase = phase
		player.global_position = garage.jager_npc.global_position
		mission._refresh_objective()
		check(shown_metres(mission) == 0, phase + " also uses the local NPC position")
	mission.phase = "board"
	player.global_position = garage.spawn_point.global_position
	manager._on_exit_door_requested(garage.exit_door, player, &"", null, &"", &"harbor/District/Garage/Entrance")
	player.global_position = entrance.global_position + Vector2(166, 0)
	mission._refresh_objective()
	check(not player.has_meta("police_exterior_position"), "Real exit clears interior map metadata")
	check(shown_metres(mission) == 10, "Exterior objective restores normal map distance")
	var other: Node2D = manager.clinic_interior
	player.global_position = other.spawn_point.global_position
	player.set_meta("police_exterior_position", entrance.global_position + Vector2(332, 0))
	mission._refresh_objective()
	check(shown_metres(mission) == 20, "Another interior routes from its exterior position to the garage")
	print("GARAGE_OBJECTIVE_COORDINATES failures=", failures)
	quit(0 if failures.is_empty() else 1)
