extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)
func _run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	var saves := root.get_node("SaveManager")
	var previous_directory: String = saves._save_dir
	var test_directory := "user://qa_mountain_%d/" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(test_directory))
	saves._save_dir = test_directory
	change_scene_to_file("res://district/mountain_pass/MountainPass.tscn")
	for i in 10: await physics_frame
	var scene := current_scene
	var player: Node2D = scene.player_instance
	player.set_physics_process(false)
	var manager: Node = scene.interior_manager
	var room: Node2D = manager.cabin_interior
	var entrance: BuildingEntrance
	for door in manager._exterior_doors:
		if manager._exterior_doors[door].interior_id == &"mountain_cabin": entrance=door; break
	player.global_position = entrance.global_position + Vector2(0,24)
	for i in 4: await physics_frame
	entrance.request_interaction(player)
	await create_timer(0.4).timeout
	player.money = 7171
	var expected_return: Vector2 = manager._actor_returns[player]
	check(saves.save_game("mountain_room_qa").success,"real save file written in isolated test directory")
	var loaded: Dictionary = saves.load_game("mountain_room_qa")
	check(loaded.success,"real save file parsed")
	change_scene_to_file(load("res://district/harbor_preview/HarborSceneRoute.gd").for_save(loaded.data))
	for i in 20: await physics_frame
	scene = current_scene
	player = scene.player_instance
	player.set_physics_process(false)
	room = scene.interior_manager.cabin_interior
	check(player.money==7171,"player restored from disk")
	check(player.get_meta("mountain_interior_id","")==&"mountain_cabin","room identity restored")
	check(scene.storm_manager.sheltered and not scene.storm_manager.visible,"saved room remains snow-free")
	check(player.viewport_3d.size.x==384,"saved room restores human render scale")
	player.global_position = room.exit_door.global_position+Vector2(0,-25)
	for i in 4: await physics_frame
	check(room.exit_door.request_interaction(player),"saved room exit works")
	await create_timer(0.4).timeout
	check(player.global_position.distance_to(expected_return)<1,"saved room exits at original forest door")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_directory+"mountain_room_qa.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_directory))
	saves._save_dir = previous_directory
	current_scene.queue_free()
	for i in 4: await process_frame
	print("SAVED ROOM FAILURES: ",failures)
	quit(0 if failures.is_empty() else 1)
