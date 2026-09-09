extends SceneTree

var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	var path := Path2D.new()
	path.curve = Curve2D.new()
	path.curve.add_point(Vector2(5000,0))
	path.curve.add_point(Vector2(10000,0))
	world.add_child(path)
	var follow := PathFollow2D.new()
	path.add_child(follow)
	var car = preload("res://world/shared/traffic/TrafficVehicle.tscn").instantiate()
	follow.add_child(car)
	car.apply_archetype("summit_suv", Color.BLUE)
	for i in 10: await process_frame
	var start := follow.progress
	var requests: int = car.body_render_requests
	for i in 15: await physics_frame
	check(car.body_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "offscreen vehicle viewport is disabled")
	check(car.body_render_requests == requests, "offscreen traffic submits no repeated renders")
	check(follow.progress > start, "offscreen lane simulation continues")
	camera.global_position = car.global_position
	camera.force_update_scroll()
	for i in 15: await process_frame
	check(car.body_render_requests > requests, "visible vehicle resumes rendering")
	car.repaint_vehicle(Color.RED)
	check(car.body_model.paint.albedo_color == Color.RED, "paint still updates the actual 3D material")
	var zone := Node2D.new()
	world.add_child(zone)
	zone.position = Vector2(6500, 100)
	for variant in 5:
		if variant == 1: zone.position.x += 450
		if variant == 2: path.position.x += 120
		if variant == 3:
			# Same length, different geometry: length-only caches would be stale.
			path.curve.set_point_position(1, Vector2(5000, 5000))
		if variant == 4:
			var replacement := Curve2D.new()
			replacement.add_point(Vector2(4000,0))
			replacement.add_point(Vector2(12000,0))
			path.curve = replacement
		var expected := path.curve.get_closest_offset(path.to_local(zone.global_position))
		check(is_equal_approx(car._control_zone_curve_offset(path, zone, zone.global_position), expected), "crossing projection invalidation variant %d" % variant)
	print("TRAFFIC RENDER FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)
