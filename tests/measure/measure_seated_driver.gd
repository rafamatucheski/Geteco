extends SceneTree
## Custo de quadro do motorista sentado + interior + vidro/teto translúcidos, na cena real
## renderizada (Main.tscn, NÃO headless): o mesmo veículo dirigido com o recurso desligado
## (`VehicleInterior.enabled = false`, comportamento antigo: piloto oculto, vidro opaco) e
## ligado, alternados em duas rodadas para diluir ruído de outras sessões no mesmo PC.
## Também mede o custo único de montar o interior na primeira entrada de cada arquétipo.
## Uso: --script res://tests/measure/measure_seated_driver.gd -- --no-save [--frames=300] [ids,...]
## Percentis de tempo de quadro em MILISSEGUNDOS.
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
var world
var frames := 300
var rounds := 2

func _initialize() -> void: run.call_deferred()

func percentile(values: Array, p: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[clampi(int(ceil(p * sorted.size())) - 1, 0, sorted.size() - 1)])

func summary(values: Array) -> String:
	var total := 0.0
	for v in values: total += float(v)
	return "media %.2f p50 %.2f p95 %.2f p99 %.2f max %.2f ms (%d quadros)" % [total / values.size(), percentile(values, .5), percentile(values, .95), percentile(values, .99), percentile(values, 1.0), values.size()]

func sample(count: int) -> Array:
	var times: Array = []
	var last := Time.get_ticks_usec()
	for i in count:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
	return times

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	var ids: Array = ["union_sedan", "sport_coupe", "route_city", "port_forklift"]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--frames="): frames = int(argument.substr(9))
		elif argument.begins_with("--rounds="): rounds = int(argument.substr(9))
		elif not argument.begins_with("--"): ids = argument.split(",")
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 1500:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	var controller = world.session.controller
	controller.set_population(0)
	var driving = world.driving
	print("MEASURE renderizador=", RenderingServer.get_video_adapter_name(), " quadros por amostra=", frames)
	for id in ids:
		var results := {false: {"parado": [], "andando": []}, true: {"parado": [], "andando": []}}
		var first_attach := -1.0
		for round in rounds:
			for enabled in ([false, true] if round % 2 == 0 else [true, false]):
				INTERIOR.enabled = enabled
				var car = null
				for offset in [Vector3(20, 0, 0), Vector3(-25, 0, 10), Vector3(0, 0, 30), Vector3(35, 0, -20), Vector3(-40, 0, -30)]:
					var road: Vector3 = controller.nearest_road(world.player.global_position + offset)
					car = controller.spawn_vehicle(id, road + Vector3.UP * .12, controller.road_yaw(road))
					if car != null: break
				if car == null: continue
				car.traffic = false
				for i in 20: await physics_frame
				if enabled and first_attach < 0.0:
					# Primeira vez deste arquétipo no processo, como no jogo: o jogador chega perto (prewarm
					# quadro a quadro, medindo o pior quadro) e depois a entrada monta a vista e o interior.
					INTERIOR.prewarm(car)
					var worst := 0.0
					var last_tick := Time.get_ticks_usec()
					for i in 24:
						await process_frame
						var tick := Time.get_ticks_usec()
						worst = maxf(worst, float(tick - last_tick) / 1000.0)
						last_tick = tick
					var began := Time.get_ticks_usec()
					INTERIOR.open_view(car)
					var after_view := Time.get_ticks_usec()
					INTERIOR.attach(car)
					var ended := Time.get_ticks_usec()
					first_attach = float(ended - began) / 1000.0
					print("MEASURE ", id, " primeira vez com prewarm: pior quadro durante o prewarm %.1f ms | open_view %.2f ms (%s) | attach do interior %.2f ms" % [worst, (after_view - began) / 1000.0, INTERIOR.profile, (ended - after_view) / 1000.0])
				var side: int = int(car.boarding_sides()[0])
				world.player.teleport(car.driver_door_anchor(side) + car.global_basis.x * float(side) * .45)
				await create_timer(.3).timeout
				if not driving.interact(true):
					car.queue_free()
					continue
				for i in 500:
					await physics_frame
					if driving.occupied and not driving.is_body_transition_active(): break
				world.camera.target_size = 14.0
				await create_timer(1.0).timeout
				results[enabled].parado.append_array(await sample(frames))
				car.external_input = true
				car.throttle_input = 1.0
				car.brake_input = false
				await create_timer(.8).timeout
				results[enabled].andando.append_array(await sample(frames))
				car.throttle_input = 0
				car.brake_input = true
				for i in 240:
					await physics_frame
					if absf(car.speed) < .3: break
				car.speed = 0
				driving.leave()
				for i in 400:
					await physics_frame
					if not driving.occupied and not driving.is_body_transition_active(): break
				await create_timer(.3).timeout
				if is_instance_valid(car): car.queue_free()
				await process_frame
		INTERIOR.enabled = true
		print("MEASURE ", id, " abertura (open_view + attach) com prewarm feito = %.2f ms" % first_attach)
		for enabled in [false, true]:
			for state in ["parado", "andando"]:
				if results[enabled][state].is_empty(): continue
				print("MEASURE ", id, " recurso=", "ligado" if enabled else "desligado", " ", state, " ", summary(results[enabled][state]))
	quit(0)
