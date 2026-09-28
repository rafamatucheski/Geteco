extends SceneTree
## Capturas do Túnel do canal no Main.tscn real (renderizado, nunca headless).
## Uso: "$GODOT" --path . --script res://tests/canal_tunnel/capture_canal_tunnel.gd -- --no-save
##   --output=res://evidence/canal-tunnel-20260928/x.png --focus=x,z [--size=m] [--time=h]
##   [--car=x,z] (carro do jogador parado no ponto, jogador dentro)
const TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")

func _initialize() -> void:
	call_deferred("run")

func _arg(name: String, fallback := "") -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--" + name + "="): return argument.trim_prefix("--" + name + "=")
	return fallback

func _xz(text: String) -> Vector2:
	var parts := text.split(",")
	return Vector2(float(parts[0]), float(parts[1]))

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var output := ProjectSettings.globalize_path(_arg("output", "res://evidence/canal-tunnel-20260928/capture.png"))
	seed(28092026)
	var world: Variant = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for frame in 1800:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.weather != null:
			break
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.diagnostic_label.hide()
	var time := _arg("time")
	if not time.is_empty():
		world.session.weather.time_of_day = time.to_float()
		world.session.weather.weather_state = 0
		world.session.weather._update()
	var focus2 := _xz(_arg("focus", "240,105"))
	var focus := Vector3(focus2.x, 0.0, focus2.y)
	var car_arg := _arg("car")
	world.production._update_physical_residency(focus)
	world.production._update_logical_region(focus)
	if car_arg.is_empty():
		world.player.teleport(focus + Vector3(0, 0.08, 0))
	else:
		var at := _xz(car_arg)
		var car: CharacterBody3D = world.driving.car
		var spot := Vector3(at.x, TUNNEL.floor_y(at.x) + 0.12, at.y)
		car.place(spot, -PI * 0.5)
		for frame in 3: await physics_frame
		for side in [-1, 1]:
			world.player.teleport(car.to_global(Vector3(side * (car.half_width + .65), .04, .15)))
			await physics_frame
			if world.driving.interact(): break
		car.set_external_driver(true)
		car.place(spot, -PI * 0.5)
	world.camera.heading = 0.0
	world.camera.target_size = float(_arg("size", "40"))
	world.camera.focus = focus
	world.camera.initialized = true
	for frame in 150:
		await process_frame
		world.camera.focus = focus
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output)
	print("CANAL_TUNNEL_CAPTURE ", output, " erro=", error)
	world.queue_free()
	await process_frame
	quit(0 if error == OK else 1)
