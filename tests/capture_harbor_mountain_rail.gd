extends SceneTree
const OUTPUT := "res://docs/measurements/rail-route-0910"
const ROUTE := preload("res://geodata/rail/HarborMountainRailRoute.gd")
var failures := 0

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures += 1

func _run() -> void:
	create_timer(240).timeout.connect(func(): quit(2))
	root.size = Vector2i(1440,900)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.get_node("CampaignState").set_campaign_flag(&"harbor_delivery_complete",true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 30: await process_frame
	var scene := current_scene
	var rail = scene.get_node("FreightRail")
	var train = rail.get_node("AmbientTrain")
	var original_train: int = train.get_instance_id()
	var original_progress: float = train._progress
	var stream := scene.get_node("ContinuousWorld")
	await stream.ensure_mountain()
	while not stream.ready_for_crossing: await process_frame
	check(train.get_instance_id() == original_train, "O carregamento da serra preserva a instância do trem")
	check(train._progress > original_progress, "O trem continua avançando enquanto a serra é carregada")
	check(not stream.mountain.can_process(), "Região distante permanece adormecida após carregar")
	var sleeping_progress: float = train._progress
	for i in 8: await physics_frame
	check(train._progress > sleeping_progress, "O relógio do trem continua com a região distante adormecida")
	train.set_process(false)
	check(get_nodes_in_group("regional_railway").size() == 1, "Somente uma ferrovia e uma composição no mundo contínuo")
	var mountain: Node2D = stream.mountain
	check(mountain.global_position == ROUTE.MOUNTAIN_OFFSET, "A rota usa o deslocamento real da região")
	var trees := mountain.find_children("*", "Node2D", true, false).filter(func(node: Node): return node.get_script() == load("res://world/mountain_pass/MountainPine3D.gd"))
	var blocked := 0
	for tree: Node2D in trees:
		if rail.regional_route.is_mountain_reserved(mountain.to_local(tree.global_position)): blocked += 1
	check(blocked == 0, "Trilhos sem árvores na faixa reservada (%d árvores verificadas)" % trees.size())
	var player: Node2D = scene.get_node("Player")
	player.set_physics_process(false)
	root.get_node("WantedManager").clear_wanted_level()
	var camera := Camera2D.new()
	camera.process_mode = Node.PROCESS_MODE_ALWAYS
	scene.add_child(camera)
	camera.make_current()
	var shots := [
		["01-ponte-ferroviaria", Vector2(8000,-4920), Vector2(8010,-4560), Vector2(7990,-4740), 0.9],
		["02-serraria", ROUTE.MOUNTAIN_OFFSET+Vector2(6460,1110), ROUTE.MOUNTAIN_OFFSET+Vector2(6400,1035), ROUTE.MOUNTAIN_OFFSET+Vector2(6400,850), 0.9],
		["03-curva-da-floresta", ROUTE.MOUNTAIN_OFFSET+Vector2(9190,220), ROUTE.MOUNTAIN_OFFSET+Vector2(9080,250), ROUTE.MOUNTAIN_OFFSET+Vector2(9160,350), 1.55],
		["04-encosta-nevada", ROUTE.MOUNTAIN_OFFSET+Vector2(8040,-2140), ROUTE.MOUNTAIN_OFFSET+Vector2(7930,-2110), ROUTE.MOUNTAIN_OFFSET+Vector2(8100,-2080), 1.55],
		["05-tunel-norte", ROUTE.MOUNTAIN_OFFSET+Vector2(7500,-3080), ROUTE.MOUNTAIN_OFFSET+Vector2(7390,-3050), ROUTE.MOUNTAIN_OFFSET+Vector2(7550,-3000), 1.65],
	]
	for shot in shots:
		player.global_position = shot[2]
		player.reset_physics_interpolation()
		camera.global_position = shot[3]
		camera.zoom = Vector2.ONE * float(shot[4])
		camera.reset_smoothing()
		camera.force_update_scroll()
		stream._update_region()
		train._progress = rail.get_route_curve().get_closest_offset(rail.to_local(shot[1]))
		for i in 24:
			await physics_frame
			camera.zoom = Vector2.ONE * float(shot[4])
			camera.force_update_scroll()
			train._update_pose()
			rail._process(1.0/60.0)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT+"/"+shot[0]+".png")
		print("RAIL_ROUTE_CAPTURE ", shot[0])
	check(stream.current_region == "mountain", "A ferrovia chega ao mapa ativo da montanha")
	check(train.get_instance_id() == original_train, "O trem permanece o mesmo após todas as transições")
	var map = get_first_node_in_group("minimap")
	check(map != null, "Minimapa presente na cena real")
	var overlay := rail.get_children().filter(func(node: Node): return node.get_script() == load("res://geodata/rail/RailMinimapOverlay.gd"))
	check(overlay.size() == 1 and overlay[0].minimap != null, "Traçado ferroviário conectado ao minimapa")
	print("HARBOR_MOUNTAIN_RAIL_RENDER failures=%d" % failures)
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
