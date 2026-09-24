extends SceneTree

const PREVIEW := preload("res://world/harbor/HarborPreview.tscn")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures.append(message)

func _run() -> void:
	var scene := PREVIEW.instantiate()
	scene.review_mode = false
	root.add_child(scene)
	current_scene = scene
	for i in 6:
		await physics_frame

	var car = scene.get_node("PlayerCar")
	car.set_physics_process(false)
	car.is_driven_by_player = true
	car.is_broken = false
	car._launch.wheelspin = 0.0

	_check(car.drift_smoke_l != null and car.drift_smoke_r != null,
		"PlayerCar has bounded rear-wheel drift emitters")
	_check(car.drift_smoke_l.amount <= 14 and car.drift_smoke_r.amount <= 14
		and car.drift_smoke_l.lifetime <= 0.5 and car.drift_smoke_r.lifetime <= 0.5,
		"drift smoke keeps a short, bounded particle budget")

	car.velocity = Vector2.ZERO
	car.is_skidding = false
	car._update_drift_smoke()
	_check(not car.drift_smoke_l.emitting and not car.drift_smoke_r.emitting,
		"idle and low-grip driving do not emit smoke")

	car.rotation = 0.0
	car.velocity = car.transform.y * 100.0
	car.is_skidding = true
	car._update_drift_smoke()
	_check(not car.drift_smoke_l.emitting and car.drift_smoke_r.emitting,
		"moderate rightward slip emits from the loaded rear side")

	car.velocity = -car.transform.y * 100.0
	car._update_drift_smoke()
	_check(car.drift_smoke_l.emitting and not car.drift_smoke_r.emitting,
		"moderate leftward slip mirrors the rear smoke")

	car.velocity = car.transform.y * 150.0
	car._update_drift_smoke()
	_check(car.drift_smoke_l.emitting and car.drift_smoke_r.emitting,
		"an intense drift emits a compact plume from both rear tires")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("capture="):
			scene._overview = false
			car.get_node("Camera").make_current()
			for i in 24:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(argument.trim_prefix("capture="))

	car.is_driven_by_player = false
	car._update_drift_smoke()
	_check(not car.drift_smoke_l.emitting and not car.drift_smoke_r.emitting,
		"leaving the vehicle stops both emitters")

	print("PLAYER_CAR_DRIFT_SMOKE failures=%d" % failures.size())
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
