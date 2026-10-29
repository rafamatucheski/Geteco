extends SceneTree
## Bancos de névoa (FogBanks) no porto, a pé: madrugada limpa e tempestade, fotos em sequência
## para ver o banco andar com o vento. Rodar com janela e `-- --no-save`; GETECO_FOG_BANKS=0 dá
## o "antes" no mesmo build (sufixo -off). Imagens em evidence/fog-banks-20261029 (fora do Git).
const OUT := "res://evidence/fog-banks-20261029"
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STREET := Vector3(369.8, .08, -81.0)
var world

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": quit(2); return
	create_timer(240,true,false,true).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var suffix := "on" if preload("res://runtime/atmosphere/FogBanks.gd").enabled else "off"
	root.size = Vector2i(1600, 900)
	var fixture_path := OUT.path_join("fixture-save.json")
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(FIXTURE.full_snapshot(STREET, true), "\t"))
	file.close()
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("skip_dispatch",true)
	world.set_meta("menu_save_path",fixture_path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec()+180000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	if not (world.session != null and world.session.ready_for_play): quit(3); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	var weather = world.session.weather
	weather.weather_locked = true
	weather.wind.seed_with(11)
	# (rótulo, hora, clima): madrugada limpa e tempestade de dia.
	for scene in [["dawn", .26, 0], ["storm", .45, 2]]:
		weather.time_of_day = scene[1]
		weather.weather_state = scene[2]
		# A névoa sobe em 8 s; a foto quer o estado assentado.
		if weather.fog_banks != null: weather.fog_banks._snap = true
		for i in 600: await process_frame
		for shot in 4:
			for i in 90: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s-%s-%d.png" % [OUT, scene[0], suffix, shot])
			var fog = weather.fog_banks
			print("FOG_BANKS shot=%s-%d amount=%s drift=%s wind=%.1f m/s fps=%d" % [scene[0], shot,
				"-" if fog == null else "%.2f" % fog.amount, "-" if fog == null else str(fog.drift),
				weather.wind.velocity.length(), Engine.get_frames_per_second()])
	world.queue_free()
	for i in 3: await process_frame
	quit()
