extends SceneTree

## Sair da garagem dirigindo a Monaliza.
##
## Regressao de dois defeitos que apareceram juntos em partida real:
##
## 1. `physics_interpolation` ligada fazia `Camera3D.unproject_position()` ler o
##    transform interpolado (ainda sem o `look_at`) no quadro em que a camera da
##    oficina nasce. Toda a geometria projetada saia errada: os solidos do
##    cenario colapsavam numa faixa em cima da vaga, a porta de saida caia ao
##    lado do carro em vez de ficar no portao, e o carro estacionado nascia
##    DENTRO de dois colisores. Ai qualquer `move_and_slide()` disparava
##    depenetracao maior que o passo maximo, o VehicleMotionSafety rejeitava o
##    quadro e zerava a velocidade -- acelerar nao movia o carro um pixel.
## 2. A troca interior->rua acontecia num unico quadro, sem cortina.

var failures: Array[String] = []
var player: Node2D
var garage: Node2D
var car: Node2D
var interiors: Node

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func _initialize() -> void:
	run.call_deferred()

func ground_of(node: Node2D) -> Vector2:
	return garage.showroom.unproject_floor(node.global_position)

func run() -> void:
	create_timer(180).timeout.connect(func(): quit(2))
	var state := root.get_node("CampaignState")
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_delivery_complete"]:
		state.set_campaign_flag(flag, true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 40: await process_frame
	var world := current_scene
	interiors = world.get_node("Interiors")
	garage = interiors.garage_interior
	player = world.get_node("Player")
	car = get_first_node_in_group("personal_car_manager").car
	check(car != null and car.unlocked, "Monaliza existe e esta liberada")

	var entrance: Node = world.get_node("District/Garage/Entrance")
	interiors._on_exterior_destination_requested(entrance, player, &"", null, &"", garage, garage.spawn_point)
	for i in 8: await physics_frame

	# A projecao tem que fechar o ida-e-volta: e ela que posiciona colisao,
	# marcadores e pontos de interacao da oficina inteira.
	var exit_ground := ground_of(garage.exit_door)
	print("  saida em metros=", exit_ground, " vaga=", ground_of(car), " spawn=", garage.showroom.unproject_floor(garage.spawn_point.global_position))
	check(exit_ground.y > 5.0 and absf(exit_ground.x) < 0.5, "Porta de saida fica no portao, nao ao lado do carro")
	check(ground_of(car).length() < 0.1, "Vaga da Monaliza projeta na origem da oficina")

	# Estacionada, a Monaliza nao pode estar dentro de nenhum solido: e isso que
	# travava o carro (depenetracao rejeitada quadro a quadro).
	var collider := car.get_node("Collision") as CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collider.shape
	query.transform = collider.global_transform
	query.collision_mask = 0xFFFFFFFF
	var overlaps: Array = []
	for hit in car.get_world_2d().direct_space_state.intersect_shape(query, 32):
		if hit.collider != car: overlaps.append(String(hit.collider.name))
	check(overlaps.is_empty(), "Monaliza estacionada nao sobrepoe solido " + str(overlaps))

	# Enquadramento: o portao tem que caber na tela, senao o carro sai do quadro
	# antes de a saida disparar.
	var frame: Rect2 = garage.get_camera_rect()
	check(frame.has_point(garage.exit_door.global_position), "Portao cabe no enquadramento da garagem")
	check(frame.has_point(car.global_position), "Vaga da Monaliza cabe no enquadramento")
	if DisplayServer.get_name() != "headless":
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/monaliza_garage_bay.png"))

	# Dante entra pela porta do motorista com E, como em partida.
	player.global_position = garage.to_global(garage.workshop_point(Vector3(-1.35, 0, 0.0)))
	player.velocity = Vector2.ZERO
	for i in 4: await physics_frame
	var interact := InputEventKey.new()
	interact.physical_keycode = KEY_E
	interact.keycode = KEY_E
	interact.pressed = true
	Input.parse_input_event(interact)
	Input.flush_buffered_events()
	await process_frame
	var release := interact.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	for i in 4: await physics_frame
	check(car.is_driven_by_player, "E coloca Dante no volante da Monaliza")
	if not car.is_driven_by_player:
		print("MONALIZA_EXIT failures=", failures)
		quit(1)
		return
	for i in 140:
		if not (is_instance_valid(car._boarding) and car._boarding.active): break
		await physics_frame
	for i in 6: await physics_frame

	var start := ground_of(car)
	var curtain: ColorRect = interiors.get_node("InteriorFade/Curtain")
	var darkest := 0.0
	Input.action_press("ui_up", 1.0)
	var exited_frame := -1
	var moved := 0.0
	for i in 420:
		await physics_frame
		darkest = maxf(darkest, curtain.color.a)
		if player.has_meta("harbor_interior"):
			moved = ground_of(car).distance_to(start)
		elif exited_frame < 0:
			exited_frame = i
			Input.action_release("ui_up")
			print("  saiu da garagem no quadro ", i, " depois de andar %.2f m" % moved)
	Input.action_release("ui_up")
	check(moved > 2.0, "Monaliza acelera dentro da garagem (andou %.2f m)" % moved)
	check(exited_frame >= 0, "Monaliza sai sozinha ao alcancar o portao")
	# A amostragem e por quadro de fisica e o tween corre no quadro de render:
	# o pico exato pode passar entre duas amostras. 0.8 ja prova tela preta.
	check(darkest > 0.8, "Cortina preta cobre a troca de mundo (pico alpha=%.2f)" % darkest)
	check(is_zero_approx(curtain.color.a), "Cortina volta a transparente depois do fade-in")
	check(player.global_position.distance_to(garage.global_position) > 1500, "Carro e motorista voltam para o Harbor")

	if DisplayServer.get_name() != "headless":
		for i in 20: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/monaliza_garage_street.png"))
	print("MONALIZA_EXIT failures=", failures)
	quit(0 if failures.is_empty() else 1)
