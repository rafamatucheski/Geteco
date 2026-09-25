extends SceneTree
## Noite na Main real: postes de calçada gerados e fases da lua. Conta postes
## gerados nos chunks carregados, confere que a lua cheia ilumina mais que a
## nova e, fora do headless, grava capturas em evidence/claude-night-moon-20260925.
## --no-save --skip-arrival obrigatórios.

var world: Node3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	print(("NIGHT_MOON PASS " if ok else "NIGHT_MOON FAIL ") + label + ((" | " + detail) if not detail.is_empty() else ""))
	if not ok: failures.append(label)

func settle(frames: int) -> void:
	for _i in frames: await process_frame

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://evidence/claude-night-moon-20260925")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_viewport().get_texture().get_image().save_png(directory.path_join(label + ".png"))

func set_night(moon_day: int) -> void:
	var weather = world.session.weather
	world.session.state.world_state.moon_day = moon_day
	weather.time_of_day = 0.0 # meia-noite: fase = moon_day / ciclo
	weather.weather_state = 0
	weather.weather_timer = 99999.0
	weather._update()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not "--no-save" in args or not "--skip-arrival" in args:
		push_error("NIGHT_MOON recusa rodar sem --no-save --skip-arrival")
		quit(2)
		return
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(1600, 900))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for _i in 1200:
		if world.session != null and world.session.ready_for_play and world.production.ready_for_play: break
		await physics_frame
	check(world.session != null and world.session.ready_for_play, "sessão inicia")
	check(world.production.no_save, "fixture não usa save pessoal")
	var weather = world.session.weather
	weather.set_process(false)
	await settle(90)
	var generated := 0
	var chunks_with := 0
	for mm in root.find_children("CityLook_sidewalk_lamp", "MultiMeshInstance3D", true, false):
		generated += mm.multimesh.instance_count
		chunks_with += 1
	check(generated > 0, "postes de calçada gerados nos chunks carregados", "postes=%d chunks=%d" % [generated, chunks_with])
	var pools_ok := true
	for mm in root.find_children("CitySidewalkLampPools", "MultiMeshInstance3D", true, false):
		var lamp := mm.get_parent().get_node_or_null("CityLook_sidewalk_lamp") as MultiMeshInstance3D
		if lamp == null or lamp.multimesh.instance_count != mm.multimesh.instance_count: pools_ok = false
	check(pools_ok, "cada poste gerado tem sua mancha de luz")
	var cycle: float = weather.MOON_CYCLE_DAYS
	set_night(int(cycle / 2.0))
	var full_moon: float = weather.moon_illumination()
	var full_sun: float = weather.controller.sun.light_energy
	var full_ambient: float = weather.controller.environment.environment.ambient_light_energy
	await settle(30)
	await capture("night-full-moon")
	set_night(0)
	var new_moon: float = weather.moon_illumination()
	var new_sun: float = weather.controller.sun.light_energy
	var new_ambient: float = weather.controller.environment.environment.ambient_light_energy
	await settle(30)
	await capture("night-new-moon")
	check(full_moon > .95 and new_moon < .05, "fases extremas: cheia≈1, nova≈0", "cheia=%.3f nova=%.3f" % [full_moon, new_moon])
	check(full_sun > new_sun * 3.0 and full_ambient > new_ambient, "lua cheia ilumina bem mais que a nova", "luz %.3f vs %.3f, ambiente %.3f vs %.3f" % [full_sun, new_sun, full_ambient, new_ambient])
	set_night(int(cycle / 2.0))
	weather.weather_state = 2
	weather._update()
	check(weather.controller.sun.light_energy < full_sun * .6, "tempestade encobre a lua cheia", "%.3f" % weather.controller.sun.light_energy)
	weather.weather_state = 0
	weather.time_of_day = .5
	weather._update()
	check(weather.controller.sun.light_energy > 1.0, "dia não depende da lua", "%.3f" % weather.controller.sun.light_energy)
	print("NIGHT_MOON RESULT %s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
