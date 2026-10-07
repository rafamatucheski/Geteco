extends SceneTree
## Bueiro/entrada movido e girado no editor, vivido no jogo: a estrutura externa aparece no lugar novo e girada, o
## recorte da calçada acompanha, a descida (escada ou entrada a pé) respeita a rotação e a saída volta junto da estrutura.
## Uso: -- --no-save --skip-arrival only=<id> [turn=<graus>]
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
const MANHOLES := preload("res://world/editing/WorldManholes.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
var world
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failures.append(label)

func run() -> void:
	var id := "sewer_market"
	var turn := 90.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("only="): id = arg.trim_prefix("only=")
		if arg.begins_with("turn="): turn = arg.trim_prefix("turn=").to_float()
	var area := MANHOLES.region_of(id)
	var base := MANHOLES.base_position(id)
	var target := base + Vector2(5.0, -3.0)
	var key := "manhole/" + id
	var doc := DATA.empty_document()
	doc.regions[area][key] = {"id": key, "type": "manhole", "place_id": id, "label": MANHOLES.label(id), "position": [target.x, target.y], "rotation": turn, "locked": false}
	if area == "desert": doc.regions[area][key]["editor_region"] = "desert"
	check(DATA.validate_document(doc).is_empty(), "documento de edição valida")
	Engine.set_meta("geteco_world_edit_document", doc)
	var definition := PLACES.get_definition(id)
	var entry: Vector3 = definition.entry_position
	check(is_equal_approx(definition.exterior_position.x, target.x) and is_equal_approx(definition.exterior_position.z, target.y), id + ": definição no lugar editado")
	if area == "desert":
		var snapshot := FIXTURE.full_snapshot(entry + Vector3(0, 0.08, 3.0), true)
		snapshot.region_id = "desert"
		snapshot.world.pedestrian = {"region": "desert", "position": [entry.x, 0.08, entry.z + 3.0]}
		var path := FIXTURE.write_fixture(FIXTURE.output_dir("manhole-moved-" + id), "save.json", snapshot)
		world = load("res://Main.tscn").instantiate()
		world.set_meta("menu_save_path", path)
	else:
		world = load("res://Main.tscn").instantiate()
		world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 120000
	while (world.session == null or not world.session.ready_for_play) and Time.get_ticks_msec() < deadline: await physics_frame
	check(world.session != null and world.session.ready_for_play, "mundo integrado inicia")
	if not failures.is_empty(): quit(1); return
	var session = world.session
	var state = session.state
	var region = world.production.region if area == "desert" else session.controller.region
	region.set_focus(entry)
	if region.has_method("prepare_collision_at"): region.prepare_collision_at(entry)
	for i in 30: await physics_frame
	if area == "desert":
		world.player.controlled_automatically = true
		world.player.automatic_direction = Vector3.ZERO
	world.player.teleport(entry + Vector3(-0.8, 0.08, 0.0) if area == "harbor" else entry + Vector3(0, 0.08, 0))
	for i in 60: await physics_frame
	var hatch: Node3D = session._find_sewer_hatch(id)
	check(is_instance_valid(hatch), id + ": estrutura carregada no lugar novo")
	if not is_instance_valid(hatch): quit(1); return
	check(Vector2(hatch.global_position.x - target.x, hatch.global_position.z - target.y).length() < 0.05, id + ": estrutura na posição editada")
	check(absf(wrapf(hatch.global_rotation.y - deg_to_rad(turn), -PI, PI)) < 0.02, id + ": estrutura girada")
	var old_spot := Vector2(base.x, base.y)
	var old_hatch: Node3D = null
	for chunk in region.get_children():
		for node in chunk.find_children(id, "Node3D", true, false):
			if Vector2(node.global_position.x - old_spot.x, node.global_position.z - old_spot.y).length() < 0.5: old_hatch = node
	check(old_hatch == null, id + ": nada ficou no lugar antigo")
	var action: Dictionary = session.nearest()
	check(action.get("id", "") == "enter" and action.get("place", "") == id, id + ": E no lugar novo leva ao bueiro")
	var entered: bool = await session.enter_place(id, false, id)
	check(entered and state.place_id == id, id + ": entra pela estrutura girada")
	if not entered: quit(1); return
	check(is_zero_approx(hatch.open_amount), id + ": estrutura fecha depois da descida")
	var left: bool = await session.leave_place()
	check(left and state.place_id.is_empty(), id + ": sai")
	for i in 20: await physics_frame
	var back := Vector2(world.player.global_position.x - target.x, world.player.global_position.z - target.y).length()
	check(back < 4.0, id + ": reaparece junto do lugar novo (%.2f m)" % back)
	check(not world.player.input_locked, id + ": controles livres")
	Engine.remove_meta("geteco_world_edit_document")
	print("MANHOLE_MOVED_SESSION failures=", failures)
	world.free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)
