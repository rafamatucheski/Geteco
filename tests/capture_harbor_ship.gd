extends SceneTree

## Real-renderer evidence: walk the normal Player from land onto the ship.
## Only the documented review shortcut places the actor; no on-board teleport.
func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1600, 1000)
	root.content_scale_size = root.size
	var preview := load("res://world/harbor/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(preview)
	current_scene = preview
	for frame in 30:
		await physics_frame
	preview.call("_visit_ship")
	var waterfront := preview.get_node("Waterfront") as Node2D
	var player := preview.get_node("Player") as CharacterBody2D
	var access: Dictionary = waterfront.call("get_ship_access_data")
	var route: PackedVector2Array = access.walk_route
	var camera := preview.get_node("OverviewCamera") as Camera2D
	camera.make_current()
	camera.position = Vector2(3450, 1430)
	camera.zoom = Vector2.ONE * 0.53
	await _save("D:/geteco/harbor-ship-overview.png")
	var aboard_captured := false
	for index in range(1, route.size()):
		var target := waterfront.to_global(route[index])
		var reached := false
		for frame in 2400:
			var delta := target - player.global_position
			if delta.length() < 3.0:
				reached = true
				break
			# Stay above the native actions' deadzone until within arrival tolerance.
			Input.action_press("ui_right", clampf(delta.x / 2.0, 0.0, 1.0))
			Input.action_press("ui_left", clampf(-delta.x / 2.0, 0.0, 1.0))
			Input.action_press("ui_down", clampf(delta.y / 2.0, 0.0, 1.0))
			Input.action_press("ui_up", clampf(-delta.y / 2.0, 0.0, 1.0))
			await physics_frame
		_release_input()
		if not reached:
			push_error("SHIP_CAPTURE: normal Player blocked at %s toward %s" % [player.global_position, target])
			quit(1)
			return
		print("SHIP_CAPTURE_WALK waypoint=%d position=%s" % [index, player.global_position])
		if not aboard_captured and Geometry2D.is_point_in_polygon(waterfront.to_local(player.global_position), access.deck_polygon):
			camera.position = player.global_position + Vector2(-80, -80)
			camera.zoom = Vector2.ONE * 1.2
			await _save("D:/geteco/harbor-ship-boarding.png")
			aboard_captured = true
		if player.global_position.y < 950.0:
			camera.position = player.global_position + Vector2(0, 100)
			camera.zoom = Vector2.ONE * 1.2
			await _save("D:/geteco/harbor-ship-bow.png")
	print("SHIP_CAPTURE complete_route=true boarded=%s" % aboard_captured)
	quit(0 if aboard_captured else 1)


func _release_input() -> void:
	for action in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		Input.action_release(action)


func _save(path: String) -> void:
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(path)
	assert(result == OK)
	print("CAPTURE " + path)
