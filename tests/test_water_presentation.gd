extends SceneTree
## Percurso real: margens, fonte, região carregada por streaming e abrigo.
const WATER := preload("res://audio/WaterSoundscape.gd")
const OUTPUT := "res://docs/measurements/water-0910/"
var failures: Array[String] = []
var world: Node2D
var player: Node2D
var capture := false
var camera: Camera2D

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func visit(point: Vector2) -> void:
	player.global_position = point
	player.velocity = Vector2.ZERO
	await create_timer(1.8).timeout

func picture(label: String, point: Vector2, zoom_value: float = 1.0) -> void:
	if not capture: return
	camera.global_position = point
	camera.zoom = Vector2.ONE * zoom_value
	camera.make_current()
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + label + ".png")

func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Timeout na água"); quit(2))
	capture = "--capture" in OS.get_cmdline_user_args()
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var state := root.get_node("CampaignState")
	state.reset_campaign()
	state.set_campaign_flag(&"harbor_arrival_seen", true)
	state.set_campaign_flag(&"harbor_arrival_call_complete", true)
	root.get_node("SaveManager").clear_pending_save()
	world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 25: await process_frame
	player = world.get_node("Player")
	player.set_physics_process(false)
	world.weather.is_dynamic_time = false
	world.weather.time_of_day = 0.4
	world.weather.is_dark = false
	camera = Camera2D.new()
	world.add_child(camera)
	var soundscape = world.get_node("HarborSoundscape")
	var details = soundscape.water_details
	check(not world.get_node("Waterfront").is_processing(), "Água não redesenha navio e guindastes por quadro")
	check(world.get_node("District/FountainWater").polygon.size() == 64, "Fonte mantém superfície circular e pedestal")
	check(world.get_node("NorthDistrict/AnimatedWater").material is ShaderMaterial, "Mar do acesso norte animado")
	check(not world.get_node("EastDistrict").has_node("FountainWater"), "Fonte não duplicada nos bairros derivados")
	for point in [Vector2(3180,1400), Vector2(4430,1800), Vector2(6700,1800), Vector2(1750,2460), Vector2(5500,-2350), Vector2(8990,-4600)]:
		check(WATER.coast_weight(point) > 0.95, "Mar alcança margem " + str(point))
	check(WATER.coast_weight(Vector2(1700,1130)) == 0.0, "Mar não vaza no centro")
	check(WATER.coast_weight(Vector2(6870,-4510)) == 0.0, "Ponte mantém apenas seu ambiente regional")
	check(WATER.coast_weight(Vector2(5720,-3800)) > 0.95, "Margem lateral da rodovia também tem ondas")
	await visit(Vector2(3180,1400))
	check(soundscape.beds.water.playing and soundscape.weights.water > 0.9, "Ondas tocam junto ao cais")
	await picture("01_cais", Vector2(3540,1450))
	await create_timer(1.2).timeout
	await picture("02_cais_movimento", Vector2(3540,1450))
	var fountain_position: Vector2 = world.get_node("District/FountainWater").global_position
	await visit(fountain_position + Vector2(0,65))
	check(details.beds.fountain.playing and details.gains.fountain > 0.9, "Fonte toca ao se aproximar")
	check(details.beds.fountain.volume_db <= -26.0, "Fonte tem teto discreto mesmo junto à borda")
	await picture("03_fonte", fountain_position, 2.0)
	await visit(Vector2(1700,1130))
	# O HarborSoundscape faz fade exponencial (constante 0,7 s) e só para o leito
	# abaixo de 0,001: leva ~3 s, e 1,8 s fixos cortavam a transição no meio.
	var waves_deadline := Time.get_ticks_msec() + 6000
	while soundscape.beds.water.playing and Time.get_ticks_msec() < waves_deadline:
		await process_frame
	check(not soundscape.beds.water.playing, "Ondas param ao se afastar do mar")
	await visit(Vector2(5900,-3800))
	var continuous = world.get_node("ContinuousWorld")
	while not continuous.ready_for_crossing: await process_frame
	var mountain = continuous.mountain
	await visit(Vector2(7900,-4430))
	var lake: Node2D = mountain.find_child("SecretMountainLake", true, false)
	await visit(lake.to_global(Vector2(-220,100)))
	check(details.beds.lake.playing and details.gains.lake > 0.5, "Lago acompanha offset da montanha carregada")
	var interactive = lake.get_node("InteractiveLakeWater")
	interactive.actor_step(player, false)
	check(not interactive.marks.is_empty() and interactive.marks.back().water, "Passos continuam produzindo ondulações sobre o material animado")
	check(details.beds.stream.stream.loop and details.beds.stream.stream.get_length() > 25, "Correnteza usa loop longo")
	await picture("04_lago", lake.global_position, 1.3)
	var outside_db: float = details.beds.lake.volume_db
	player.is_in_dialogue = true
	await create_timer(0.8).timeout
	check(details.beds.lake.volume_db < outside_db - 8, "Água recua durante diálogo")
	player.is_in_dialogue = false
	player.set_meta("mountain_interior", true)
	await create_timer(1.8).timeout
	check(not details.beds.lake.playing and not soundscape.beds.water.playing, "Abrigo silencia água externa")
	player.remove_meta("mountain_interior")
	# Mede sobre o curso desenhado do riacho, não numa coordenada fixa: a geometria
	# da serra mudou e (7100,-20) ficou a ~150 px da margem (ganho 0,69).
	var stream_probe: Vector2 = mountain.to_global(Vector2(7100,-20))
	var best_distance := INF
	for zone in get_nodes_in_group("water_sound_zone"):
		if not zone is Line2D or zone.get_meta("water_sound_kind", zone.get("sound_kind")) != "stream": continue
		for i in zone.points.size() - 1:
			var closest := Geometry2D.get_closest_point_to_segment(stream_probe, zone.to_global(zone.points[i]), zone.to_global(zone.points[i + 1]))
			if closest.distance_to(stream_probe) < best_distance:
				best_distance = closest.distance_to(stream_probe)
				stream_probe = closest
	await visit(stream_probe)
	check(details.beds.stream.playing and details.gains.stream > 0.8, "Riacho usa correnteza perto do curso real")
	await picture("05_corredeira", mountain.to_global(Vector2(7060,50)), 1.3)
	await visit(Vector2(1700,1130))
	check(not details.beds.lake.playing and not details.beds.stream.playing, "Streaming não deixa áudio da montanha preso na cidade")
	world.queue_free()
	await process_frame
	print("WATER_PRESENTATION: %d falhas" % failures.size())
	quit(0 if failures.is_empty() else 1)
