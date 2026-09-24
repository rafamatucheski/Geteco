extends SceneTree
## Captura renderizada (Vulkan, não headless) dos efeitos de fogo: jato do
## lança-chamas, explosão de granada/bazuca e carro explodindo, logo após e alguns
## segundos depois (foco de incêndio no chão). Rodar com --no-save.
## Saída em res://evidence/fire-effects-0924/.
const OUTPUT := "res://evidence/fire-effects-0924/"
var world

func _initialize() -> void: run.call_deferred()

func frames(count: int) -> void:
	for i in count: await process_frame

func shot(label: String) -> void:
	await frames(1)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + label + ".png"))
	print("CAPTURE ", label)

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	var controller = world.session.controller
	controller.set_population(0)
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	var origin: Vector3 = world.player.global_position
	await frames(60)
	var gameplay = world.gameplay
	var effects = gameplay.effects
	# Lança-chamas: rajada contínua por ~0,6 s à direita do jogador.
	var aim := Vector3(1, 0, 0)
	for i in 36:
		effects.flame(origin + Vector3(0.6, 1.1, 0), aim, 6.0)
		await process_frame
	await shot("01_lanca_chamas")
	# Granada/bazuca: explosão a 8 m.
	var blast := origin + Vector3(-8, 0, 3)
	gameplay.explode(blast, 6.0, 0.0, null, false)
	await frames(6)
	await shot("02_explosao_inicio")
	await frames(40)
	await shot("03_explosao_fumaca")
	await frames(240)
	await shot("04_fogo_no_chao")
	# Carro explodindo.
	var car = null
	for candidate in controller.vehicles:
		if not is_instance_valid(candidate) or candidate == world.driving.car: continue
		if car == null or candidate.global_position.distance_to(origin) < car.global_position.distance_to(origin): car = candidate
	print("CAR ", car)
	await frames(30)
	if car != null:
		world.player.teleport(car.global_position + Vector3(4.5, .1, 3.0))
		await frames(60)
		await shot("05a_carro_antes")
		gameplay.explode(car.global_position + Vector3(-6, 0, 0), 5.0, 0.0, null, false)
		await frames(3)
		await shot("04b_explosao_perto_do_carro")
		await frames(90)
		gameplay.explosion_occurred.connect(func(pt, r, src): print("EXPLOSION ", pt, " r=", r, " src=", src))
		print("CAR_POS ", car.global_position, " health ", car.health)
		car.receive_damage(car.max_health * 3.0)
		for k in 4:
			await frames(3)
			await shot("05_carro_explodindo_%d" % k)
		await frames(300)
		await shot("06_carro_queimando")
		await frames(900)
		await shot("07_carcaca_fria")
	print("CAPTURE_DONE")
	world.queue_free()
	await process_frame
	quit(0)
