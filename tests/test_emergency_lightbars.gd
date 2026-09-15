extends SceneTree

var failures: Array[String] = []
var units: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)

func _run() -> void:
	create_timer(25).timeout.connect(func(): quit(2))
	root.size = Vector2i(1100, 700)
	root.get_node("WantedManager").set_process(false)
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var camera := Camera2D.new()
	stage.add_child(camera)
	camera.position = Vector2(500, 300)
	camera.zoom = Vector2.ONE * 1.8
	camera.make_current()
	var incident := Node2D.new()
	incident.set_meta("ambient_crime", true)
	stage.add_child(incident)
	incident.position = Vector2(500, 50)
	await process_frame
	var pool := root.get_node("EmergencyPool")
	for service in ["police", "ambulance", "fire", "coroner"]:
		var car = pool.get_vehicle(service)
		car.set_physics_process(false)
		car.position = Vector2(270 + units.size() * 155, 300)
		car.rotation = 0.4
		car.target = incident
		car.is_acting = false
		car.is_returning_to_base = false
		car._update_response_audio()
		check(car.lights.visible and car.siren_audio.playing, service + " responds with lights and siren")
		check(car.visual_3d.lightbar.lamps.size() == 2, service + " has two animated 3D lenses")
		car.is_acting = true
		car._update_response_audio()
		check(car.lights.visible and not car.siren_audio.playing, service + " keeps warning lights during on-site work")
		units.append(car)
	# Observe the production presenter changing a stationary vehicle's roof lights.
	await create_timer(0.08).timeout
	var phases: Dictionary = {}
	for i in 12:
		await create_timer(0.04).timeout
		for car in units:
			var key: String = car.name
			if not phases.has(key): phases[key] = {}
			phases[key][car.visual_3d.lightbar.phase] = true
	for car in units:
		check(phases[car.name].has(0) and phases[car.name].has(1), str(car.type) + " alternates both sides while stationary")
		check(car.visual_3d.render_requests >= 2, str(car.type) + " submits new rendered flashes")
	if DisplayServer.get_name() != "headless":
		for phase in [0, 1]:
			while units[0].visual_3d.lightbar.phase != phase: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/geteco/artifacts/patrol-side-parking-0910/rescue-flash-%d.png" % phase)
	for car in units:
		car.is_returning_to_base = true
		car._update_response_audio()
	await create_timer(0.08).timeout
	for car in units:
		check(not car.lights.visible and car.visual_3d.lightbar.phase == -1, str(car.type) + " turns lights off after response")
		for lamp in car.visual_3d.lightbar.lamps:
			check(not lamp.emission_enabled, "parked/returning lens does not glow")
		pool.return_vehicle(car)
	var reused = pool.get_vehicle("ambulance")
	reused.set_physics_process(false)
	reused.target = null
	reused._update_response_audio()
	check(not reused.lights.visible, "recycled ambulance has no stale active response")
	pool.return_vehicle(reused)
	var parked = ModernTrafficFactory.spawn_parked_vehicle(stage, "ParkedCruiser", Vector2(500, 300), 0.4, "police_cruiser", 0)
	parked.ensure_presentation()
	parked.set_physics_process(false)
	parked.set_process(true)
	await create_timer(0.08).timeout
	check(parked.is_3d_vehicle and parked.visual.texture is ViewportTexture, "parked cruiser uses actual 3D geometry")
	check(parked.active_roof_prop_node == null or not parked.active_roof_prop_node.visible, "3D roof has no duplicate floating 2D bar")
	check(parked.lightbar_3d.phase == -1, "parked cruiser starts with giroflex off")
	parked.toggle_siren()
	await create_timer(0.08).timeout
	check(parked.lightbar_3d.phase >= 0, "player siren control activates 3D roof lenses")
	parked.toggle_siren()
	await create_timer(0.08).timeout
	check(parked.lightbar_3d.phase == -1, "player siren control extinguishes 3D roof lenses")
	var resting_renders: int = parked.body_render_requests
	await create_timer(0.12).timeout
	check(parked.body_render_requests == resting_renders, "unlit parked cruiser does not render continuously")
	stage.queue_free()
	await process_frame
	print("EMERGENCY_LIGHTBARS failures=", failures)
	quit(0 if failures.is_empty() else 1)
