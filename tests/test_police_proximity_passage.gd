extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures.append(message)

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func _run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	var saves = root.get_node("SaveManager")
	saves.set("_save_dir", "D:/geteco/artifacts/police-proximity/saves/")
	saves.clear_pending_save()
	var world = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await frames(15)
	world._walk()
	var player = world.get_node("Player")
	var manager = world.get_node("Interiors")
	var police = manager.police_interior
	var entrance = world.get_node("District/Police/Entrance")
	player.global_position = entrance.to_global(Vector2(0, 65))
	player.velocity = Vector2.ZERO
	await frames(20)
	check(not player.has_meta("harbor_interior"), "approach opens door without entering from the sidewalk")
	check(entrance._door_open, "exterior door opens on approach")
	Input.action_press("move_up")
	for i in 150:
		await physics_frame
		if player.has_meta("harbor_interior"):
			break
	Input.action_release("move_up")
	check(player.has_meta("harbor_interior"), "walking toward police door enters without E")
	await frames(100)
	check(player.has_meta("harbor_interior"), "arrival does not immediately send player outside")
	check(not police.exit_door.get_node("Prompt").visible, "exit has no E prompt")
	Input.action_press("move_down")
	for i in 180:
		await physics_frame
		if not player.has_meta("harbor_interior"):
			break
	Input.action_release("move_down")
	check(not player.has_meta("harbor_interior"), "walking to exit leaves without E")
	await frames(100)
	check(not player.has_meta("harbor_interior"), "outside return marker does not trigger a re-entry")
	check(player.global_position.distance_to(entrance.get_node("OutsideReturn").global_position) < 20, "exit returns to correct exterior door")
	Input.action_press("move_up")
	for i in 150:
		await physics_frame
		if player.has_meta("harbor_interior"):
			break
	Input.action_release("move_up")
	check(player.has_meta("harbor_interior"), "walking back from return marker re-enters without leaving sensor")
	print("POLICE_PROXIMITY failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
