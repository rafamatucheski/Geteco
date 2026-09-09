extends SceneTree

func _init() -> void: call_deferred("run")
func sample_frames(count: int) -> float:
	var times: Array[float] = []
	var previous := Time.get_ticks_usec()
	for i in count:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now-previous)/1000.0)
		previous = now
	times.sort()
	return times[times.size()/2]
func capture(path: String) -> void:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	print("HARBOR_COUPЕ_CAPTURE %s result=%d" % [path,root.get_texture().get_image().save_png(path)])
func run() -> void:
	var scene = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 15: await physics_frame
	scene._drive()
	var car = scene.get_node("PlayerCar")
	await create_timer(0.6).timeout
	await capture("D:/geteco/harbor_coupe_integrated.png")
	# A/B same stationary district view: cached vs forced visual animation.
	# This isolates renderer cost, not a claim about worst-case driving FPS.
	var cached := await sample_frames(180)
	var timer := Timer.new()
	timer.wait_time = 1.0/30.0
	timer.timeout.connect(func():
		for wheel in car.spinners: wheel.rotation.x += 0.25
		car.request_appearance_update()
	)
	scene.add_child(timer)
	timer.start()
	var animated := await sample_frames(180)
	timer.stop()
	print("COUPE_RENDER_AB cached_median_ms=%.2f animated_median_ms=%.2f" % [cached,animated])
	car.rotation = -0.5
	await capture("D:/geteco/harbor_coupe_angle.png")
	var garage = scene.get_node("Interiors").garage_interior
	car.global_position = garage.global_position + Vector2(0,100)
	car.velocity = Vector2.ZERO
	car.get_node("Camera").reset_smoothing()
	await create_timer(0.5).timeout
	var bay = garage.get_node("PaintAndSpray")
	bay.paint_car(2)
	await create_timer(1.0).timeout
	await capture("D:/geteco/harbor_coupe_paint.png")
	scene.queue_free()
	for i in 3: await process_frame
	quit()
