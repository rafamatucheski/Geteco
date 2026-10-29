extends SceneTree
## Tempestade no porto, a pé, com o vento do clima (WindField): fotos ao longo de ~14 s
## para pegar calmo e rajada. Rodar com janela e `-- --no-save`; GETECO_WIND_GUSTS=0 dá o
## "antes" no mesmo build (sufixo -off). Imagens em evidence/wind-rain-20261029 (fora do Git).
const OUT := "res://evidence/wind-rain-20261029"
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STREET := Vector3(369.8, .08, -81.0)
var world

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": quit(2); return
	create_timer(240,true,false,true).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var suffix := "on" if preload("res://runtime/atmosphere/WindField.gd").enabled else "off"
	root.size = Vector2i(1600, 900)
	# Rua em frente ao quartel de bombeiros: aberta, sem marquise em cima.
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
	weather.time_of_day = .42
	weather.weather_state = 2
	weather.weather_locked = true
	weather.wind.seed_with(11)
	for i in 240: await physics_frame
	for shot in 8:
		for i in 105: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/storm-%s-%d.png" % [OUT, suffix, shot])
		print("WIND_RAIN shot=%d gust=%.2f speed=%.1f m/s dir=%s visible=%s" % [shot, weather.wind.gust, weather.wind.velocity.length(), weather.wind.direction, weather.precipitation.visible])
	world.queue_free()
	for i in 3: await process_frame
	quit()
