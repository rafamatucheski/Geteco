extends SceneTree
## Sonda (30/10, "as poças de água não têm efeito quando o carro passa em cima"): chuva forte, um carro
## de trânsito atravessando uma poça a 12 m/s e o que a poça registra. Só imprime.
## tools/run_godot_locked.sh --path . --script res://tests/probe_rain_puddle_splash.gd -- --no-save --skip-arrival --play-at=harbor,64,82

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 240000:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: print("PUDDLE sessão não ficou pronta"); quit(1); return
	var session = world.session
	var weather = session.get("weather")
	print("PUDDLE weather=", weather != null)
	if weather == null: quit(1); return
	weather.weather_state = 2
	weather.coastal_wetness = 1.0
	for i in 400: await physics_frame
	var puddles: Node = null
	for node in world.find_children("*", "", true, false):
		if node.get_script() != null and str(node.get_script().resource_path).ends_with("RainPuddles3D.gd"):
			puddles = node
			break
	if puddles == null: print("PUDDLE sem RainPuddles3D"); quit(1); return
	var active: Dictionary = puddles._active
	var monitoring := 0
	for p: Area3D in active.values(): if p.monitoring: monitoring += 1
	print("PUDDLE wetness=%.2f raining=%s ativas=%d monitorando=%d" % [puddles.wetness, puddles.raining, active.size(), monitoring])
	if active.is_empty(): quit(0); return
	var player_pos: Vector3 = world.player.global_position
	var target: Area3D = null
	var best := INF
	for p: Area3D in active.values():
		var d: float = p.global_position.distance_to(player_pos)
		if d < best: best = d; target = p
	var car = session.controller.spawn_vehicle("taxi_yellow", target.global_position + Vector3(-12, .3, 0), PI * .5) if session.controller.has_method("spawn_vehicle") else null
	print("PUDDLE carro=", car, " camada=", car.collision_layer if car != null else -1, " poça_mask=", target.collision_mask, " raio=", (target.get_child(1).shape as CylinderShape3D).radius)
	if car == null: quit(1); return
	var before: int = puddles.splash_count
	var entered := [0]
	target.body_entered.connect(func(body): entered[0] += 1; print("PUDDLE entrou ", body, " vel=", body.get("velocity")))
	for i in 150:
		car.velocity = Vector3(12, 0, 0)
		car.global_position += Vector3(12, 0, 0) / 60.0
		await physics_frame
		if i == 62:
			world.player.global_position = car.global_position + Vector3(0, 0, 6)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://evidence/rain-puddle-splash.jpg"), .85)
	print("PUDDLE entradas=%d respingos=%d (antes %d)" % [entered[0], puddles.splash_count - before, before])
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://evidence/rain-puddle-splash.jpg"), .85)
	quit(0)
