extends SceneTree
## Carro do Meshy (`metro_hatch`) no mundo real: nasce ao lado do jogador, o jogador entra, dirige uns segundos e sai.
## Registra fotos da câmera do jogo e o resultado de cada passo (nasceu, entrou, andou, rodas giraram).
## Uso: "$GODOT" --path . --script res://tests/capture/capture_meshy_car_ingame.gd -- --no-save --skip-arrival [--old]
## Vídeo: acrescente --write-movie evidence/npc-meshy/video/carro.avi --fixed-fps 30 antes de --script.
var out_dir := "res://evidence/npc-meshy/car-ingame"

func _initialize() -> void: run.call_deferred()

func _shot(name: String) -> void:
	for i in 4: await process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [out_dir, name]))

func run() -> void:
	if "--old" in OS.get_cmdline_user_args():
		preload("res://runtime/FleetCatalog.gd").meshy_cars = false
		out_dir += "-antigo"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("MESHY_CAR mundo não carregou"); quit(1); return
	# Pega um trecho de rua pela rota do trânsito, como no teste de condução.
	var start: CharacterBody3D = world.driving.car
	var route: Curve3D = world.production.traffic_routes.route_near(start.position)
	var distance := route.get_closest_offset(start.position)
	var point := route.sample_baked(distance + 12.0, true)
	var direction := route.sample_baked(distance + 13.0, true) - point
	var yaw := atan2(-direction.x, -direction.z)
	var car: CharacterBody3D = world.production.spawn_vehicle("metro_hatch", point + Vector3.UP * .12, yaw)
	print("MESHY_CAR nasceu=", car != null)
	if car == null: quit(1); return
	for i in 20: await physics_frame
	var wheels := car.find_children("Wheel_*", "MeshInstance3D", true, false)
	print("MESHY_CAR peças_roda=", wheels.size(), " malhas=", car.find_children("*", "MeshInstance3D", true, false).size())
	var approach := car.to_global(Vector3(-(car.half_width + .65), .04, .15))
	world.player.teleport(approach)
	for i in 30: await physics_frame
	await _shot("1-parado")
	var entered := false
	for side in [-1, 1]:
		world.player.teleport(car.to_global(Vector3(side * (car.half_width + .65), .04, .15)))
		await physics_frame
		if world.driving.interact(): entered = true; break
	print("MESHY_CAR entrou=", entered)
	for i in 40: await physics_frame
	await _shot("2-dentro")
	var start_pos := car.global_position
	Input.action_press("accelerate")
	for i in 150: await physics_frame
	await _shot("3-andando")
	Input.action_press("move_right")
	for i in 70: await physics_frame
	await _shot("4-curva")
	Input.action_release("move_right")
	for i in 90: await physics_frame
	Input.action_release("accelerate")
	Input.action_press("brake")
	for i in 80: await physics_frame
	Input.action_release("brake")
	await _shot("5-freada")
	var wheel_a: Transform3D = (car.find_children("Wheel_*", "MeshInstance3D", true, false)[0] as Node3D).transform
	print("MESHY_CAR roda_girou=", not wheel_a.is_equal_approx(Transform3D.IDENTITY))
	print("MESHY_CAR andou=", snappedf(car.global_position.distance_to(start_pos), 0.1), " m")
	print("MESHY_CAR ", "OK")
	quit(0)
