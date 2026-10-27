extends SceneTree
## Cor do carro ao bater (cartão bug-veiculos-cor-ao-bater-20261012): o relato era a pintura metalizada mudar de
## cor depois de uma batida. Carrega Main de dia, com tempo parado e céu limpo, põe um carro de pintura metalizada
## diante da câmera travada e fotografa antes e depois de batidas pelo caminho real (Vehicle.receive_impact →
## VehicleBodyDents). Compara a cor média dos pixels de pintura (os que, antes, estavam perto da cor da pintura)
## na mesma área da tela. Grava as fotos em evidence/ e imprime os números.
## Uso (com tela): "$GODOT" --path . --script res://tests/capture/capture_crash_paint_color.gd -- --no-save [arquétipo]
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const START := Vector3(80, 0, 80)

func _initialize() -> void:
	create_timer(300).timeout.connect(func(): push_error("CRASH_PAINT timeout"); quit(3))
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var id := "sport_coupe"
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"): id = arg
	root.size = Vector2i(1280, 720)
	var folder := FIXTURE.output_dir("crash-paint-" + id)
	var path := FIXTURE.write_fixture(folder, "checkpoint.json", FIXTURE.full_snapshot(START, true))
	var world: Node3D = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.get("session") != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.get("session") == null or not world.session.ready_for_play: push_error("sessão não carregou"); quit(1); return
	if world.session.modal: world.session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.health = 100000.0
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .5
	world.session.weather.weather_state = 0
	world.session.weather._update()
	var car: Node3D = preload("res://scripts/Vehicle.gd").new()
	car.archetype = id
	car.vehicle_id = "crash_paint"
	world.add_child(car)
	car.global_position = world.player.global_position + Vector3(5, .6, 0)
	world.production.vehicles.append(car)
	for tick in 90: await physics_frame
	car.set_physics_process(false)
	var paint: StandardMaterial3D = car._paint.materials[0] if not car._paint.materials.is_empty() else null
	if paint == null: push_error("carro sem pintura"); quit(1); return
	var metallic_before := paint.metallic
	world.camera.target = car
	world.camera.heading = 0
	world.camera.target_size = 7.0
	world.camera.size = 7.0
	world.camera.locked = true
	for frame in 40: await process_frame
	var before := await _shot(folder, "antes")
	var box := _screen_box(world.camera.get_viewport().get_camera_3d(), car)
	var paint_screen := _paint_pixels(before, box, paint.albedo_color)
	var mean_before := _mean(before, paint_screen)
	# Batidas reais: lateral e frente, como contra outro carro a ~12 m/s.
	for hit in [[Vector3(car.half_width, .7, .4), Vector3.RIGHT], [Vector3(car.half_width, .6, -.9), Vector3.RIGHT], [Vector3(0, .6, -car.half_length), Vector3.FORWARD]]:
		# Dano baixo para não chegar ao fogo (abaixo de 20 % pega fogo): a cor da carcaça não é o relato.
		car.receive_impact(6.0, hit[0], null, 12.0, hit[1])
		for frame in 30: await process_frame
	for frame in 60: await process_frame
	var after := await _shot(folder, "depois")
	var mean_after := _mean(after, paint_screen)
	var shift := Vector3(mean_after.r - mean_before.r, mean_after.g - mean_before.g, mean_after.b - mean_before.b)
	print("CRASH_PAINT arquétipo=%s metallic %.2f→%.2f rugosidade %.2f albedo %s" % [id, metallic_before, paint.metallic, paint.roughness, paint.albedo_color.to_html(false)])
	print("CRASH_PAINT pixels de pintura=%d média antes=%s depois=%s diferença RGB=%s (|Δ|=%.3f) matiz %.3f→%.3f saturação %.3f→%.3f valor %.3f→%.3f" % [paint_screen.size(), mean_before.to_html(false), mean_after.to_html(false), shift.snapped(Vector3.ONE * .001), shift.length(), mean_before.h, mean_after.h, mean_before.s, mean_after.s, mean_before.v, mean_after.v])
	print("CRASH_PAINT_DONE ", folder, " vida=%.0f de %.0f" % [car.health, car.max_health], " queimando=", car.damage_look.burning, " carcaça=", car.damage_look.wrecked, " amassados=", car.body_dents.snapshot().size() if is_instance_valid(car.body_dents) else -1)
	quit(0)

func _shot(folder: String, label: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [folder, label]))
	return image

func _screen_box(camera: Camera3D, car: Node3D) -> Rect2i:
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = b if first else bounds.merge(b)
		first = false
	var rect := Rect2()
	for i in 8:
		var p := camera.unproject_position(bounds.get_endpoint(i))
		rect = Rect2(p, Vector2.ZERO) if i == 0 else rect.expand(p)
	return Rect2i(rect).intersection(Rect2i(Vector2i.ZERO, root.size))

func _paint_pixels(image: Image, box: Rect2i, paint: Color) -> PackedVector2Array:
	var points := PackedVector2Array()
	for y in range(box.position.y, box.end.y, 2):
		for x in range(box.position.x, box.end.x, 2):
			var c := image.get_pixel(x, y)
			# Mesmo matiz da pintura e brilho razoável: lataria, não vidro, pneu ou chão.
			if absf(wrapf(c.h - paint.h, -.5, .5)) < .06 and c.s > paint.s * .4 and c.v > .12: points.append(Vector2(x, y))
	return points

func _mean(image: Image, points: PackedVector2Array) -> Color:
	var sum := Vector3.ZERO
	for p in points:
		var c := image.get_pixel(int(p.x), int(p.y))
		sum += Vector3(c.r, c.g, c.b)
	if points.is_empty(): return Color.BLACK
	sum /= points.size()
	return Color(sum.x, sum.y, sum.z)
