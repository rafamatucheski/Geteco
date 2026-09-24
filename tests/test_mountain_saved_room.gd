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
	saves._save_directory_ready = false
	change_scene_to_file("res://world/mountain_pass/MountainPass.tscn")
	while current_scene == null or not current_scene.region_ready or not current_scene.interior_manager.region_ready: await process_frame
	var scene := current_scene
	var player: Node2D = scene.player_instance
	player.set_physics_process(false)
	var manager: Node = scene.interior_manager
	var room: Node2D = manager.cabin_interior
	var entrance: BuildingEntrance = find_entrance(scene, &"mountain_cabin")
	player.global_position = room.spawn_point.global_position
	for i in 4: await physics_frame
	await create_timer(0.4).timeout
	player.money = 7171
	var expected_position: Vector2 = player.global_position
	check(saves.save_game("mountain_room_qa").success,"real save file written in isolated test directory")
	var loaded: Dictionary = saves.load_game("mountain_room_qa")
	check(loaded.success and loaded.data.world.region == "mountain" and not loaded.data.world.has("interior"),"real save file records physical position")
	# This focused fixture reloads MountainPass directly. The production route
	# opens HarborGame first, whose ContinuousWorld then streams this same room.
	var snapshot: Dictionary = loaded.data.duplicate(true)
	saves.clear_pending_save()
	change_scene_to_file("res://world/mountain_pass/MountainPass.tscn")
	await process_frame
	while current_scene == null or not current_scene.region_ready or not current_scene.interior_manager.region_ready: await process_frame
	scene = current_scene
	player = scene.player_instance
	player.set_physics_process(false)
	room = scene.interior_manager.cabin_interior
	player.restore(snapshot.player)
	scene.restore_region_interior(player, snapshot.world)
	for i in 10: await physics_frame
	check(player.money==7171,"player restored from disk")
	check(player.get_meta("mountain_interior_id","")==&"mountain_cabin" and player.global_position.distance_to(expected_position)<2,"physical room and position restored")
	check(scene.storm_manager.sheltered and not scene.storm_manager.visible,"saved room remains snow-free")
	check(root.get_camera_2d()==player.get_node("Camera"),"saved room keeps player camera")
	entrance = find_entrance(scene, &"mountain_cabin")
	player.global_position = entrance.global_position+Vector2(0,24)
	for i in 4: await physics_frame
	await create_timer(0.4).timeout
	check(not player.has_meta("mountain_interior") and player.global_position.distance_to(entrance.global_position+Vector2(0,24))<2,"saved room exits through original forest door")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_directory+"mountain_room_qa.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_directory))
	saves._save_dir = previous_directory
	current_scene.queue_free()
	for i in 4: await process_frame
	print("SAVED ROOM FAILURES: ",failures)
	quit(0 if failures.is_empty() else 1)

func find_entrance(parent: Node, id: StringName) -> BuildingEntrance:
	if parent is BuildingEntrance and parent.destination_id == id: return parent
	for child in parent.get_children():
		var found := find_entrance(child, id)
		if found != null: return found
	return null
