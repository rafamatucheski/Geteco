extends SceneTree
## Refúgio da Serra na sessão real (Main.tscn, sem gravar): abrigo montado no ponto certo, chão
## aplanado, fogueira como fonte de calor, catre oferecido a pé, dormir leva às 7h do dia seguinte e
## cura, recusa com estrela de polícia, marcador no mapa e foto. Rodar com `-- --no-save`.
const REFUGE := preload("res://world/mountain_detail/MountainRefuge.gd")
const HEAT := preload("res://runtime/cold/OriginalHeatSources.gd")
const REST := preload("res://runtime/RestUntil.gd")
const ATLAS := preload("res://ui/hud/WorldMapData.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var world
var session
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(300.0, true, false, true).timeout.connect(func():
		failures.append("watchdog 300 s")
		finish())
	run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks += 1
	print("MOUNTAIN_REFUGE ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
	return value

func frames(count: int) -> void:
	for i in count: await physics_frame

func run() -> void:
	if not check("--no-save" in OS.get_cmdline_user_args(), "--no-save obrigatório"): finish(); return
	root.size = Vector2i(1280, 720)
	var folder := FIXTURE.output_dir("mountain-refuge")
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.get("session") != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	session = world.session
	if not check(session != null and session.ready_for_play, "sessão real carregou"): finish(); return
	if session.modal: session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO

	# Fogueira: o ponto da lista de calor é o mesmo da fogueira do abrigo girado.
	var fire := REFUGE.world_point(REFUGE.FIRE)
	var listed := Vector3.INF
	for source in HEAT.SOURCES:
		if source.id == "mountain_refuge": listed = HEAT.to_world(source.point)
	check(Vector2(listed.x - fire.x, listed.z - fire.z).length() < .05, "fonte de calor no lugar da fogueira (%s / %s)" % [listed, fire])
	check(HEAT.nearest(fire + Vector3(1.0, .1, 0)).get("id", "") == "mountain_refuge", "fogueira do refúgio esquenta")

	world.production._update_physical_residency(REFUGE.CENTER)
	world.production._update_logical_region(REFUGE.CENTER)
	var cot := REFUGE.world_point(REFUGE.COT)
	world.player.teleport(REFUGE.world_point(Vector3(0, .1, 7)))
	var refuge: Node3D = null
	deadline = Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		refuge = world.production.region.find_child("MountainRefuge", true, false)
		if is_instance_valid(refuge) and refuge.is_node_ready(): break
		await process_frame
	if not check(is_instance_valid(refuge), "refúgio montado na serra"): finish(); return
	check(refuge.global_position.distance_to(REFUGE.CENTER) < .2 and is_equal_approx(refuge.global_rotation.y, REFUGE.YAW), "refúgio no ponto e virado para a trilha")
	var region = world.production.region
	check(absf(region.terrain.height_at(Vector2(cot.x, cot.z))) < .1 and absf(region.terrain.height_at(Vector2(fire.x, fire.z))) < .1, "chão aplanado no catre e na fogueira")
	await frames(30)

	# Foto do alpendre, com o fogo aceso pela lista de calor.
	world.player.teleport(REFUGE.world_point(Vector3(1.0, .1, 8.5)))
	world.camera.initialized = false
	for i in 40: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/refugio.png" % folder))

	# Catre: oferecido a pé ao lado, não de longe.
	world.player.teleport(cot + Vector3(.9, .1, 0).rotated(Vector3.UP, REFUGE.YAW))
	await frames(6)
	var action: Dictionary = session.nearest()
	check(action.get("id", "") == "mountain_refuge" and action.get("target", "") == "rest", "catre oferece dormir (%s)" % action.get("label", action.get("id", "nada")))
	world.player.teleport(REFUGE.world_point(Vector3(0, .1, 9)))
	await frames(4)
	check(session.nearest().get("id", "") != "mountain_refuge", "catre não aparece longe dele")

	# Com estrela de polícia recusa e não mexe no relógio.
	world.player.teleport(cot + Vector3(.9, .1, 0).rotated(Vector3.UP, REFUGE.YAW))
	await frames(4)
	session.weather.time_of_day = 13.0 / 24.0
	world.gameplay.stars = 1
	await session.interact()
	check(is_equal_approx(session.weather.time_of_day, 13.0 / 24.0), "com polícia atrás não dorme")
	world.gameplay.stars = 0
	await frames(2)

	# Dormir: 13h -> 7h do dia seguinte, vida cheia.
	var day: int = session.weather.moon_day()
	world.gameplay.health = 40.0
	check(await session.interact(), "dormir no catre executa")
	check(is_equal_approx(session.weather.time_of_day, 7.0 / 24.0), "acorda às 7h (%.3f)" % (session.weather.time_of_day * 24.0))
	check(session.weather.moon_day() == day + 1, "virou o dia (%d -> %d)" % [day, session.weather.moon_day()])
	check(world.gameplay.health > 40.0, "acorda curado (%.0f)" % world.gameplay.health)
	# O mesmo ajudante do Horizonte: das 7h até as 20h fica no mesmo dia.
	REST.until(session, 20.0)
	check(is_equal_approx(session.weather.time_of_day, 20.0 / 24.0) and session.weather.moon_day() == day + 1, "descanso até as 20h fica no mesmo dia")

	var map := ATLAS.new()
	map.collect({"state":session.state, "world":world, "region":world.production.region}, false)
	check(map.markers.any(func(marker): return marker.id == "refuge"), "Refúgio da Serra no mapa")
	finish()

func finish() -> void:
	print("MOUNTAIN_REFUGE checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
