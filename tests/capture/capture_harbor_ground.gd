extends SceneTree
## Chão do Harbor antes/depois (pedido do jogador de 29/10: asfalto limpo demais para cidade portuária).
## Quatro pontos (porto, zona industrial, centro e rua residencial), câmera de jogo, sem trânsito nem
## pedestres para a contagem de draw calls não variar com a população sorteada.
##
## A/B no mesmo código: GETECO_HARBOR_ROAD_WEAR=0 volta ao chão anterior (decalques antigos e asfalto
## sem macrovariação). Em cada ponto mede o total de draw calls (média de 60 quadros) e, escondendo só
## os nós do desgaste, quanto deles é do chão novo ou dos decalques antigos de rua.
##
## Uso (janela, nunca headless; pela fila):
##   tools/run_godot_locked.sh --path . --script res://tests/capture/capture_harbor_ground.gd -- --no-save \
##     --no-traffic --population=0 --no-dispatch --variant=depois
## Saída: evidence/harbor-ground-20261029/<variante>/<ponto>.png e resumo.json.
const WEAR := preload("res://world/shared/roads/HarborRoadWear.gd")
## Decalques de rua do CityChunkDressing anterior (o desgaste novo assume este papel quando ligado).
const OLD_ROAD_NODES := ["CityLook_decal_oil", "CityLook_decal_patch", "CityLook_decal_crack", "CityLook_manhole", "CityLook_drain"]
const SITES := [
	{"id": "porto", "point": Vector3(300.0, 0.1, 226.0), "time": 0.42},
	{"id": "industrial", "point": Vector3(158.0, 0.1, 108.0), "time": 0.42},
	{"id": "centro", "point": Vector3(82.0, 0.1, 108.0), "time": 0.42},
	{"id": "residencial", "point": Vector3(318.0, 0.1, -45.0), "time": 0.42},
]

var world


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Captura precisa da janela (renderizador de verdade).")
		quit(2)
		return
	var variant := "depois" if WEAR.enabled() else "antes"
	var selected := PackedStringArray()
	var close := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
		if arg.begins_with("--sites="): selected = arg.trim_prefix("--sites=").split(",")
		if arg == "--close": close = true
	seed(29102026)
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	# Carregamento sob a cortina conta tempo, não quadros (com a fila cheia passava de 2.400 quadros).
	var load_began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - load_began < 300000:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		print("HARBOR_GROUND sessão não ficou jogável em %d s" % ((Time.get_ticks_msec() - load_began) / 1000))
		quit(3)
		return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.session.weather.set_process(false)
	# O pátio do porto tem guarita: visita autorizada para a captura não virar perseguição.
	if world.session.get("urban_operations") != null: world.session.urban_operations.security.authorized_visit = true
	var folder := "res://evidence/harbor-ground-20261029/" + variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var report := {"variant": variant, "wear_enabled": WEAR.enabled(), "gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "resolution": str(root.size),
		"engine": Engine.get_version_info().string, "args": " ".join(OS.get_cmdline_user_args()), "sites": {}}
	for site in SITES:
		if not selected.is_empty() and site.id not in selected: continue
		world.session.weather.time_of_day = site.time
		world.session.weather.weather_state = 0
		world.session.weather._update()
		world.player.teleport(site.point)
		world.session.weather._process(0)
		world.production.region.set_focus(site.point)
		world.camera.heading = 0
		world.camera.target_size = 52
		world.camera.initialized = false
		# Trechos em volta montam em fatias; 9 s cobrem o acabamento e a fusão por célula.
		await create_timer(9.0).timeout
		var entry := {"position": str(world.player.global_position)}
		entry["draws"] = await _average_draws()
		var wear_nodes := _nodes_named(["HarborRoadWear"])
		var old_nodes := _nodes_named(OLD_ROAD_NODES)
		entry["wear_nodes"] = wear_nodes.size()
		entry["old_road_nodes"] = old_nodes.size()
		entry["wear_decals"] = _wear_decals(wear_nodes)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder + "/" + site.id + ".png")
		if close:
			world.camera.target_size = 22
			await create_timer(2.0).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder + "/" + site.id + "_perto.png")
			world.camera.target_size = 52
			await create_timer(2.0).timeout
		# Quanto do total é o chão de rua: esconde só esses nós, mede e devolve.
		for node in wear_nodes + old_nodes: node.visible = false
		entry["draws_without_road_wear"] = await _average_draws()
		for node in wear_nodes + old_nodes: node.visible = true
		entry["road_wear_draws"] = float(entry.draws) - float(entry.draws_without_road_wear)
		# Chuva: poças e remendos têm de acompanhar o asfalto molhado.
		# O clima está parado (set_process false): chuva e asfalto molhado entram direto, sem rampa.
		_set_rain(true)
		await create_timer(4.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder + "/" + site.id + "_chuva.png")
		_set_rain(false)
		report.sites[site.id] = entry
		print("HARBOR_GROUND ", variant, " ", site.id, " ", JSON.stringify(entry))
	report["wear_stats"] = WEAR.stats.duplicate(true)
	FileAccess.open(folder + "/resumo.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	quit(0)


func _set_rain(raining: bool) -> void:
	var weather = world.session.weather
	weather.weather_state = 2 if raining else 0
	weather.rain_level = 1.0 if raining else 0.0
	weather.coastal_wetness = 1.0 if raining else 0.0
	weather._update()
	weather._process(0)


func _average_draws() -> float:
	var total := 0.0
	for frame in 60:
		await RenderingServer.frame_post_draw
		total += float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	return total / 60.0


func _nodes_named(prefixes: Array) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var region: Node = world.production.region
	if region == null: return found
	for node in region.find_children("*", "GeometryInstance3D", true, false):
		var label := str(node.name)
		for prefix in prefixes:
			if label.begins_with(prefix) and (node as Node3D).visible:
				found.append(node)
				break
	return found


func _wear_decals(nodes: Array[Node3D]) -> int:
	var total := 0
	for node in nodes: total += int(node.get_meta(&"road_wear_decals", 0))
	return total
