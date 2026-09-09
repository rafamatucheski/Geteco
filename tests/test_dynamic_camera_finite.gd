extends SceneTree

var failures := 0

func _init() -> void:
	call_deferred("run")

func check_camera(camera: Camera2D, label: String) -> void:
	if not camera.zoom.is_finite() or camera.zoom.x <= 0.0 or camera.zoom.y <= 0.0 or not camera.transform.is_finite():
		failures += 1
		push_error("Invalid camera state: " + label)

func run() -> void:
	var body := CharacterBody2D.new()
	var camera = load("res://DynamicCamera.gd").new()
	body.add_child(camera)
	root.add_child(body)
	camera.set_process(false)
	body.velocity = Vector2(600.0, 0.0)
	camera.zoom = Vector2.ONE * 1.8
	camera._process(3.0)
	check_camera(camera, "long frame")
	if camera.zoom.x < 1.22 or camera.zoom.x > 1.8:
		failures += 1
	for limit in [0.0, -1.0, NAN, INF]:
		camera.max_speed = limit
		for speed in [Vector2.ZERO, Vector2(600.0, 0.0), Vector2(NAN, 0.0), Vector2(INF, 0.0)]:
			body.velocity = speed
			camera._process(0.016)
			check_camera(camera, "invalid speed/limit")
	for value in [NAN, INF, -1.0]:
		# Test rejection before the Camera2D setter: assigning NaN directly to
		# that native property already triggers an engine affine-invert error.
		var repaired: float = camera._safe_zoom(value, 1.8)
		if not is_finite(repaired) or repaired <= 0.0:
			failures += 1
		camera.zoom_close = value
		camera.zoom_far = value
		camera.zoom_nitro = value
		camera.overview_zoom = value
		camera.transition_speed = value
		camera.lead_distance = value
		for elapsed in [0.0, 10.0, NAN, INF, -1.0]:
			camera._process(elapsed)
			check_camera(camera, "invalid zoom/delta")
		camera.set_overview_mode(true)
		camera._process(0.016)
		check_camera(camera, "overview")
		camera.set_overview_mode(false)
	body.queue_free()
	await process_frame
	print("DYNAMIC_CAMERA_FINITE_RESULT failures=%d" % failures)
	quit(0 if failures == 0 else 1)
