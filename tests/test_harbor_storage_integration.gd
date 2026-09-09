extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)
func run() -> void:
	create_timer(80).timeout.connect(func(): quit(2))
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag, true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 40: await process_frame
	var art = current_scene.get_node("District/HarborStorageArt")
	var player = current_scene.get_node("Player")
	check(art.model.get_batch_metrics().after_count <= 30, "Integrated depot uses material batches")
	check(art.viewport_3d.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "Static art does not render continuously")
	# Check the complete footprint against reserved streets, buildings and entrances.
	var district = current_scene.get_node("District")
	var envelope: AABB = art.model.get_envelope()
	var yard := Rect2(art.to_global(art.project_floor(Vector2(envelope.position.x, envelope.position.z))), Vector2.ZERO)
	yard = yard.expand(art.to_global(art.project_floor(Vector2(envelope.end.x, envelope.end.z))))
	for site in district.sites:
		check(not yard.intersects(site.bounds), "Yard clears building " + str(site.id))
	for access in district.accesses:
		check(not yard.intersects(access.bounds), "Yard clears access " + str(access.id))
	for road in current_scene.get_node("RoadLayout").get_road_graph_definitions():
		var points: PackedVector2Array = road.points
		for j in range(points.size() - 1):
			var reserved := Rect2(points[j], Vector2.ZERO).expand(points[j+1]).grow(float(road.width)*0.5 + 42.0)
			check(not yard.intersects(reserved), "Yard clears road " + str(road.id))
	# Use Dante's actual collision shape and movement to cross the front apron.
	player.global_position = Vector2(2460, 1770)
	for i in 3: await physics_frame
	for i in 480:
		if player.global_position.x >= 2720: break
		Input.action_press("ui_right")
		await physics_frame
	Input.action_release("ui_right")
	check(player.global_position.x >= 2720, "Dante walks across the loading apron: " + str(player.global_position))
	# Positive control: real player shape must be blocked by the pallet stack.
	player.global_position = art.to_global(art.project_floor(Vector2(-3.4, -4.0)))
	await physics_frame
	check(player.test_move(player.global_transform, art.project_floor(Vector2(0, 2))-art.project_floor(Vector2.ZERO)), "Pallet stack blocks the real player body")
	player.global_position = Vector2(2600, 1770)
	for i in 25: await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("D:/geteco/harbor-storage-integrated.png") == OK, "Gameplay capture saved")
	print("HARBOR STORAGE INTEGRATION: ", failures)
	quit(0 if failures.is_empty() else 1)
