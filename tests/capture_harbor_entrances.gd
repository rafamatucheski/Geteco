extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1500, 950)
	root.content_scale_size = root.size
	var scene := load("res://world/harbor/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	for frame in 30:
		await physics_frame
	var player := scene.get_node("Player") as CharacterBody2D
	var camera := scene.get_node("OverviewCamera") as Camera2D
	camera.make_current()
	for entry in [["garage", "District/Garage/Entrance"], ["police", "District/Police/Entrance"], ["hospital", "District/Clinic/Entrance"], ["workshop", "NorthDistrict/MotorWorkshop/Entrance"], ["firehouse", "NorthDistrict/NorthFireStation/Entrance1"]]:
		var door := scene.get_node(entry[1]) as Node2D
		var state: Dictionary = door.get_entrance_state()
		player.global_position = state.threshold_position + state.outward * 96.0
		player.velocity = Vector2.ZERO
		camera.global_position = door.get_parent().global_position + Vector2(0, 50)
		camera.zoom = Vector2.ONE * 1.65
		for frame in 90:
			await physics_frame
		await _save("D:/geteco/harbor-door-%s-closed.png" % entry[0])
		var action := "ui_up" if state.outward.y > 0 else "ui_down"
		Input.action_press(action)
		var captured_half := false
		for frame in 180:
			await physics_frame
			if player.global_position.distance_to(state.approach_position) < 4.0:
				Input.action_release(action)
			if not captured_half and door.open_amount >= 0.4 and door.open_amount < 0.9:
				captured_half = true
				await _save("D:/geteco/harbor-door-%s-opening.png" % entry[0])
			if door.open_amount >= 0.99:
				break
		Input.action_release(action)
		assert(door.open_amount >= 0.99 and captured_half, "Native approach did not animate the door")
		await _save("D:/geteco/harbor-door-%s-open.png" % entry[0])
		var away := "ui_down" if state.outward.y > 0 else "ui_up"
		Input.action_press(away)
		for frame in 45:
			await physics_frame
		Input.action_release(away)
		for frame in 90:
			await physics_frame
		assert(door.open_amount < 0.01, "Door failed to close after departure")
		print("DOOR_CAPTURE %s opened_and_closed=true" % entry[0])
	quit(0)

func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(path) == OK)
	print("CAPTURE " + path)
