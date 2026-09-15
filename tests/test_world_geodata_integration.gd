extends SceneTree
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280,720)
	var scene := load("res://world/harbor/HarborPreview.tscn").instantiate() as Node2D
	scene.get_node("Interiors").enabled = false
	root.add_child(scene)
	current_scene = scene
	for i in 600:
		if scene.world_build_ready: break
		await create_timer(.05).timeout
	if not scene.world_build_ready:
		push_error("World did not finish loading")
		quit(1)
		return
	await physics_frame
	await physics_frame
	var player := scene.get_node("Player") as CharacterBody2D
	var car := scene.get_node("PlayerCar") as CharacterBody2D
	player.set_physics_process(false)
	car.set_physics_process(false)
	var space := scene.get_world_2d().direct_space_state
	var count := 0
	for building in get_nodes_in_group("building_geodata"):
		for solid: Rect2 in building.get_meta("solid_rects_local", []):
			var point := PhysicsPointQueryParameters2D.new()
			point.position = building.to_global(solid.get_center())
			point.collision_mask = 1
			var matched := false
			for hit in space.intersect_point(point):
				if hit.collider == building: matched = true
			if not matched: failures.append("Missing solid: " + str(building.get_path()))
			for actor in [player,car]:
				var from: Transform2D = actor.global_transform
				from.origin = building.to_global(solid.get_center() + Vector2(0, -solid.size.y*.5-80))
				if not actor.test_move(from, point.position-from.origin): failures.append("Roof crossing: " + str(building.get_path()))
			count += 1
	for segment in [
		PackedVector2Array([Vector2(3100,400),Vector2(4500,400)]),
		PackedVector2Array([Vector2(6600,1700),Vector2(7000,1700)]),
		PackedVector2Array([Vector2(7150,-4560),Vector2(7400,-4560)]),
		PackedVector2Array([Vector2(3570,2090),Vector2(3570,3250)]),
	]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(segment[0],segment[1],1))
		if not hit.is_empty(): failures.append("Blocked connection: %s by %s" % [segment,hit.collider.get_path()])
	print("WORLD_GEODATA_INTEGRATION solids=%d failures=%s" % [count,failures])
	if DisplayServer.get_name() != "headless":
		var camera := scene.get_node("OverviewCamera") as Camera2D
		camera.make_current()
		camera.zoom = Vector2.ONE * .8
		for view in [{"name":"west_coast","point":Vector2(-1400,1700)}, {"name":"south_port","point":Vector2(5900,5800)}, {"name":"north_coast","point":Vector2(4900,-2300)}]:
			camera.position = view.point
			camera.reset_smoothing()
			for frame in 5: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/geteco/artifacts/world-geodata/"+view.name+".png")
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
