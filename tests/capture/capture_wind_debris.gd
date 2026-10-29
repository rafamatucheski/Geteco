extends SceneTree
## Detritos do vento: papel e folhas no porto na tempestade (fotos na rajada) e, com
## `--play-at=desert,x,z`, a areia do deserto. Rodar com janela e `-- --no-save`;
## GETECO_WIND_DEBRIS=0 dá o "antes" do papel no mesmo build. Imagens em
## evidence/wind-debris-20261029 (fora do Git).
const OUT := "res://evidence/wind-debris-20261029"
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STREET := Vector3(369.8, .08, -81.0)
var world

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--no-save" not in args or DisplayServer.get_name() == "headless": quit(2); return
	create_timer(300,true,false,true).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var place := "harbor"
	for argument in args: if argument.begins_with("--play-at="): place = argument.trim_prefix("--play-at=").get_slice(",", 0)
	var suffix := "on" if preload("res://runtime/atmosphere/WindDebris.gd").enabled else "off"
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
	var deadline := Time.get_ticks_msec()+200000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	if not (world.session != null and world.session.ready_for_play): quit(3); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	var weather = world.session.weather
	weather.time_of_day = .45
	weather.weather_state = 0 if place == "desert" else 2
	weather.weather_locked = true
	weather.wind.seed_with(11)
	# O deserto ainda tira a cortina de carregamento depois de "pronto para jogar".
	for i in (1200 if place == "desert" else 300): await process_frame
	for shot in 5:
		# Espera a rajada (até ~15 s) e deixa o papel atravessar um pouco a vista.
		var waited := 0
		while weather.wind.gust < (.2 if place == "desert" else .45) and waited < 1300:
			await process_frame
			waited += 1
		for i in 40: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s-%s-%d.png" % [OUT, place, suffix, shot])
		var debris = weather.wind_debris
		print("WIND_DEBRIS shot=%s-%d gust=%.2f speed=%.1f m/s ratio=%s fps=%d" % [place, shot, weather.wind.gust,
			weather.wind.velocity.length(), "-" if debris == null else "%.2f" % debris.ratio, Engine.get_frames_per_second()])
		if place == "desert":
			var desert = world.production.regions.get("desert")
			var ambient = desert.ambient if desert != null else null
			if ambient != null:
				print("WIND_DEBRIS areia ativa=%s emitindo=%s em=%s foco=%s fração=%.2f força=%s" % [ambient._active, ambient._wind.emitting,
					ambient._wind.global_position, world.player.global_position, ambient._wind.amount_ratio,
					ambient._wind.draw_pass_1.material.get_shader_parameter("strength")])
		for i in 200: await process_frame
	world.queue_free()
	for i in 3: await process_frame
	quit()
