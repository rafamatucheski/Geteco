extends SceneTree
const RAIL := preload("res://world/harbor/HarborRailLine.gd")
const ROUTE := preload("res://geodata/rail/HarborMountainRailRoute.gd")
var failures := 0
var checks := 0

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var fixture := Node2D.new()
	root.add_child(fixture)
	current_scene = fixture
	var rail := RAIL.new()
	fixture.add_child(rail)
	var player := Node2D.new()
	player.add_to_group("player")
	fixture.add_child(player)
	var train := rail.get_node("AmbientTrain")
	train.set_process(false)
	rail.set_process(false)
	var plan: RefCounted = rail.regional_route
	var curve: Curve2D = rail.get_route_curve()
	var length: float = curve.get_baked_length()
	check(rail.get_node_or_null("HarborMountainRailScenery/RegionalRailSupports") != null, "Estruturas regionais construídas")
	check(plan.sections.size() == 3, "Porto, ponte de ligação e serra no mesmo percurso")
	check(length > 30000.0, "A ligação percorre as coordenadas reais dos mapas")
	check(curve.sample_baked(0).distance_to(curve.sample_baked(length)) < 0.01, "Circuito fechado sem salto no retorno")
	for section in plan.sections:
		var middle: float = (section.start + section.end) * 0.5
		var state: Dictionary = rail.get_track_state_at_offset(middle)
		check(state.above_ground and state.opacity > 0.99, "Trecho visível: " + String(section.id))
		train._progress = section.end + 35.0
		train._update_pose()
		check(train.locomotive.modulate.a == 0.0 and train._freight_visuals[0].modulate.a > 0.9, "Portal recorta cada peça separadamente: " + String(section.id))
		if String(section.id) != "harbor":
			player.global_position = curve.sample_baked(middle, true)
			rail._process(0.3)
			check(rail._reveal_amount == 1.0, "A passagem por baixo funciona na região: " + String(section.id))
	for point in ROUTE.MOUNTAIN_POINTS:
		check(plan.is_mountain_reserved(point), "Clareira dos trilhos: " + str(point))
	check(not plan.is_mountain_reserved(Vector2(6350,560)), "A serraria fica fora da faixa ferroviária")
	check(not plan.is_mountain_reserved(Vector2(7480,760)), "Chalé preservado fora da faixa ferroviária")
	var road := preload("res://world/mountain_pass/MountainPassRoad.gd").new()
	fixture.add_child(road)
	var dirt_builder = preload("res://world/mountain_pass/MountainSceneryBuilder.gd")
	dirt_builder._init_dirt_roads()
	var bad_supports := 0
	for rect: Rect2 in rail._regional_scenery.supports:
		var local := rect.get_center() - ROUTE.MOUNTAIN_OFFSET
		if road.is_point_on_road(local, 100.0) or dirt_builder._is_point_on_dirt_road(local, 65.0): bad_supports += 1
	check(bad_supports == 0, "Pilares não ocupam a estrada da montanha nem estradas de terra")
	var harbor_roads := preload("res://world/harbor/HarborMountainConnector.gd").road_definitions()
	for rect: Rect2 in rail._regional_scenery.supports:
		for definition in harbor_roads:
			var points: PackedVector2Array = definition.points
			for index in points.size() - 1:
				if rect.get_center().distance_to(Geometry2D.get_closest_point_to_segment(rect.get_center(),points[index],points[index+1])) < 105.0: bad_supports += 1
	check(bad_supports == 0, "A ponte rodoviária continua livre de pilares ferroviários")
	var identity := train.get_instance_id()
	var wagon_ids: Array[int] = []
	for wagon in train._freight_visuals: wagon_ids.append(wagon.get_instance_id())
	train._progress = rail._visible_start + 200.0
	train._update_pose()
	train.speed = 105.0
	var travel := 0.0
	var elapsed := 0.0
	var worst_step := 0.0
	var visited: Array[String] = []
	var previous_offset: float = train._progress
	while travel < length + 100.0 and elapsed < 900.0:
		var previous: Vector2 = train.global_position
		train._process(1.0 / 20.0)
		var step: float = fposmod(train._progress - previous_offset, length)
		travel += step
		previous_offset = train._progress
		elapsed += 1.0 / 20.0
		worst_step = maxf(worst_step, previous.distance_to(train.global_position))
		var state := rail.get_track_state_at_offset(train._progress)
		var id := String(state.section)
		if visited.is_empty() or visited[-1] != id: visited.append(id)
	check(travel >= length, "Uma volta completa executada com o controlador real do trem")
	check(worst_step < 15.0, "Nenhum teleporte nas transições nem na volta do circuito")
	check(visited == ["harbor","tunnel","bay","tunnel","mountain","tunnel","harbor"], "Ordem real da viagem: " + str(visited))
	check(train.get_instance_id() == identity, "Mesmo trem do início ao fim")
	for i in wagon_ids.size(): check(train._freight_visuals[i].get_instance_id() == wagon_ids[i], "Mesmo vagão após mudar de região")
	var directory := "res://docs/measurements/rail-route-0910"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var export_data := {"length":length,"cycle_seconds":elapsed,"sections":[],"landmarks":[],"route":[],"mountain_road":[]}
	for point in curve.tessellate_even_length(5, 50.0): export_data.route.append([point.x,point.y])
	for section in plan.sections:
		var entry := {"id":section.id,"label":section.label,"start":section.start,"end":section.end,"points":[]}
		for point in plan.sampled_section(section): entry.points.append([point.x,point.y])
		export_data.sections.append(entry)
	for marker in plan.landmarks: export_data.landmarks.append({"id":marker.id,"label":marker.label,"position":[marker.position.x,marker.position.y]})
	for point in road.smooth_points:
		var global := point + ROUTE.MOUNTAIN_OFFSET
		export_data.mountain_road.append([global.x,global.y])
	FileAccess.open(directory+"/route.json",FileAccess.WRITE).store_string(JSON.stringify(export_data,"\t"))
	print("HARBOR_MOUNTAIN_RAIL checks=%d failures=%d length=%.1f cycle_seconds=%.1f max_step=%.3f sections=%s" % [checks, failures, length, elapsed, worst_step, visited])
	fixture.queue_free()
	await process_frame
	quit(1 if failures else 0)
