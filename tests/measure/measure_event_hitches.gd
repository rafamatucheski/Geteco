extends SceneTree
## Custo de eventos pontuais (helicóptero, equipe a pé, morte com loot, explosão).
## Para cada evento mede (a) o tempo síncrono da chamada, em ms, e (b) o pior quadro
## nos 12 quadros seguintes (traz custo diferido: sombras, shader, física).
## Cada evento roda duas vezes: a 1ª mostra o custo frio (shader/cache), a 2ª o quente.
## Rodar RENDERIZADO (nunca --headless), sem outra instância Godot ativa:
##   godot --path . --script res://tests/measure/measure_event_hitches.gd -- --no-save --skip-arrival
var world: Node3D
var results: Array[Dictionary] = []
var output := "res://evidence/event-hitches-20260928"

func _initialize() -> void: run.call_deferred()

func settle(count: int) -> void:
	for index in count: await process_frame

## Executa `action`, mede a chamada e o pior quadro dos quadros seguintes.
func probe(label: String, action: Callable) -> void:
	await settle(30)
	var started := Time.get_ticks_usec()
	action.call()
	var sync_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var worst := 0.0
	var previous := Time.get_ticks_usec()
	for index in 12:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, float(now - previous) / 1000.0)
		previous = now
	results.append({"event": label, "sync_call_ms": snappedf(sync_ms, 0.01), "worst_next_12_frames_ms": snappedf(worst, 0.01)})
	print("HITCH %-28s call=%.2f ms  worst_next_frames=%.2f ms" % [label, sync_ms, worst])

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--no-save" not in args or "--skip-arrival" not in args: quit(2); return
	create_timer(180.0).timeout.connect(func(): push_error("HITCH_TIMEOUT"); quit(2))
	seed(20260928)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for index in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .45
	var gameplay: Node3D = world.gameplay
	await settle(240)

	# Mantém o jogador vivo e o diretor aéreo parado: o helicóptero é lançado à mão.
	gameplay.health = 100.0
	gameplay.stars = 3
	# Em produção o dispatch cria os policiais; aqui só medimos a montagem do PoliceAgent.
	gameplay.dispatch_owned = false
	gameplay.last_known = world.player.global_position
	gameplay.last_known_valid = true
	var air: Node3D = gameplay.police_air
	air.set_physics_process(false)

	for pass_index in 2:
		var tag := "cold" if pass_index == 0 else "warm"
		await probe("heli_find_zone_" + tag, func(): air.set_meta("_zone", air.find_landing_zone(gameplay.last_known if gameplay.last_known_valid else world.player.global_position)))
		var zone: Dictionary = air.get_meta("_zone", {})
		if not zone.is_empty():
			await probe("heli_launch_" + tag, func(): air.launch_helicopter(zone))
			await settle(20)
			air.clear_response()
		else:
			print("HITCH sem zona de pouso válida nesta posição; mova o jogador em Main para um pátio aberto")
		var squad: Array = []
		await probe("officer_squad4_" + tag, func():
			for index in 4:
				var officer = gameplay.spawn_officer()
				if officer != null: squad.append(officer))
		print("HITCH policiais criados: ", squad.size())
		await probe("officer_kill_loot_x4_" + tag, func():
			for officer in squad:
				if is_instance_valid(officer): officer.receive_damage(9999.0, world.player))
		await probe("explosion_" + tag, func(): gameplay.explode(world.player.global_position + Vector3(18, 0, 0), 6.0, 60.0, null))
		# Consequências tardias (socorristas, bombeiros, corpos): caça quadros ruins por 6 s.
		var last := Time.get_ticks_usec()
		var began := last
		for index in 360:
			await process_frame
			var now := Time.get_ticks_usec()
			var ms := float(now - last) / 1000.0
			if ms > 30.0: print("HITCH   aftermath_%s t=%.2fs frame=%.1f ms" % [tag, float(now - began) / 1e6, ms])
			last = now

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var file := FileAccess.open(output.path_join("event-hitches.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "results": results}, "\t"))
		file.close()
	world.queue_free()
	await process_frame
	quit(0)
