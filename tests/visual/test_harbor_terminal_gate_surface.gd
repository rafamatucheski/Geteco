extends SceneTree
## Real road material passes, full coach hulls, and both renderer handoffs.
var failures: Array[String] = []
var world: Node2D
var network: Node2D
var stop: Node2D
var view: Node2D
var operations: Node2D
const ORIGIN := Vector2(1700, 1060)
const SIDEWALK_TOP := 1148.0
const ASPHALT_TOP := 1190.0

func _initialize() -> void: run.call_deferred()

func run() -> void:
	root.size = Vector2i(1000, 720)
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	var layout := preload("res://world/harbor/HarborRoadLayout.gd").new()
	layout.name = "RoadLayout"
	world.add_child(layout)
	stop = Node2D.new()
	stop.name = "ArrivalStop"
	stop.position = ORIGIN
	world.add_child(stop)
	network = preload("res://world/harbor/HarborRoadNetwork.gd").new()
	network.provider_paths.assign([NodePath("../RoadLayout")])
	network.build_guard_rails = false
	world.add_child(network)
	view = preload("res://world/harbor/terminal/HarborTerminalView.gd").new()
	stop.add_child(view)
	operations = preload("res://world/harbor/terminal/HarborTerminalOperations.gd").new()
	operations.architecture = view
	stop.add_child(operations)
	operations.set_physics_process(false)
	for service in operations.fleet:
		service.set_physics_process(false)
		service.passenger_service.set_physics_process(false)
	for gate in operations.gates:
		gate.collision.disabled = true
		if is_instance_valid(gate.arm): gate.arm.rotation.z = PI * .49
	await process_frame
	await process_frame
	var service = operations.fleet[0]
	var covered := 0
	var masked := 0
	var missing_pavement := 0
	var blocked_hulls := 0
	var first_missing := Vector2.INF
	for curve in [service._departure_route(), service._arrival_route()]:
		for step in ceili(curve.get_baked_length() / 6.0):
			var offset := float(step) * 6.0
			var point: Vector2 = curve.sample_baked(offset)
			var direction: Vector2 = (curve.sample_baked(minf(offset + .2, curve.get_baked_length())) - curve.sample_baked(maxf(0, offset - .2))).normalized()
			var hull: PackedVector2Array = service._shape_for_heading(direction).points
			var bounds := Rect2(ORIGIN + point + hull[0], Vector2.ZERO)
			for vertex in hull: bounds = bounds.expand(ORIGIN + point + vertex)
			if bounds.end.y <= SIDEWALK_TOP or bounds.position.y >= ASPHALT_TOP: continue
			# Only the gate mouths, not the ordinary coach circuit along the street.
			if point.x < 215 or point.x > 390: continue
			service.coach.position = point
			service.heading = direction
			service._sync_native(0)
			covered += 1
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = service._shape_for_heading(direction)
			query.transform = Transform2D(0, ORIGIN + point)
			query.collision_mask = 1
			if not world.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(): blocked_hulls += 1
			if not service._external and view.z_index + view.sprite_3d.z_index < network.z_index: masked += 1
			for y in range(ceili(maxf(bounds.position.y, SIDEWALK_TOP + 1)), floori(minf(bounds.end.y, ASPHALT_TOP - 1)), 6):
				for x in range(ceili(bounds.position.x), floori(bounds.end.x), 6):
					var sample := Vector2(x, y)
					if not Geometry2D.is_point_in_polygon(sample - ORIGIN - point, hull): continue
					var color := _road_surface_at(sample)
					if color != network.ROAD_COLOR:
						missing_pavement += 1
						if first_missing == Vector2.INF: first_missing = sample
	if covered < 15: failures.append("Both complete coach hulls must cross the real sidewalk band")
	if masked > 0: failures.append("%d handoff poses leave the coach behind the road layer" % masked)
	if blocked_hulls > 0: failures.append("%d complete coach hulls intersect gate architecture with the barriers open" % blocked_hulls)
	if missing_pavement > 0: failures.append("%d hull samples still cross sidewalk/curb instead of an open driveway; first %s" % [missing_pavement, first_missing])
	if DisplayServer.get_name() != "headless":
		for other in operations.fleet:
			if other == service: continue
			other.coach_model.hide()
			other._external_sprite.hide()
		var camera := Camera2D.new()
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		camera.position = Vector2(2010, 1150)
		camera.zoom = Vector2.ONE * 2.8
		world.add_child(camera)
		camera.make_current()
		view.set_animation_active(true)
		var prefix := "baseline" if "--baseline" in OS.get_cmdline_user_args() else "final"
		for gate in [["departure", 250.0, Vector2.DOWN], ["arrival", 360.0, Vector2.UP]]:
			for y in [55, 75, 95, 115]:
				service.coach.position = Vector2(gate[1], y)
				service.heading = gate[2]
				service._sync_native(0)
				service.coach.reset_physics_interpolation()
				service._external_sprite.reset_physics_interpolation()
				for frame in 6: await physics_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("D:/geteco/artifacts/life-refinement-0911/terminal-gate-%s-%s-%d.png" % [prefix, gate[0], y])
	print("TERMINAL_GATE_SURFACE poses=", covered, " masked=", masked, " pavement_missing=", missing_pavement, " blocked_hulls=", blocked_hulls, " failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _road_surface_at(point: Vector2) -> Color:
	var cell := Vector2i((point / 512.0).floor())
	if not network.static_canvas.chunks.has(cell): return Color.TRANSPARENT
	var chunk: Dictionary = network.static_canvas.chunks[cell]
	for index in range(chunk.vertices.size() - 3, -1, -3):
		var triangle := PackedVector2Array([chunk.vertices[index], chunk.vertices[index + 1], chunk.vertices[index + 2]])
		if Geometry2D.is_point_in_polygon(point, triangle): return chunk.colors[index]
	return Color.TRANSPARENT
