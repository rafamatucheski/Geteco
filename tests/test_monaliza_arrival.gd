extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var view := preload("res://world/harbor/interiors/HarborWorkshopView.gd").new()
	root.add_child(view)
	view.build_workshop()
	view.position = Vector2(600, 340)
	view.scale = Vector2.ONE * 2.8
	await process_frame
	assert(not view.display_car.visible, "Monaliza must not already be parked")
	paused = true
	view.deliver_monaliza()
	await create_timer(3.0, true).timeout
	assert(view.delivery_active and view.display_car.position.z > 0.0)
	await capture("arrival")
	await create_timer(3.5, true).timeout
	assert(view.delivery_mechanic.get_parent() == view.model)
	assert(view.delivery_mechanic.position.x > 0.8, "Mechanic exits beside the driver door without a reparent transform jump")
	assert(absf(view.delivery_mechanic.rotation.z) < 0.2, "Mechanic stands upright after leaving the car")
	await capture("handoff")
	while not view.delivery_done: await process_frame
	assert(view.mechanic_working and not view.display_car.visible)
	assert(view.delivery_mechanic.position.distance_to(Vector3(-0.95, 0, -2.8)) < 0.01)
	await capture("workbench")
	print("PASS Monaliza arrives while dialogue pauses gameplay, mechanic exits, hands over and works at bench")
	quit()

func capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/monaliza-" + stage + ".png")
