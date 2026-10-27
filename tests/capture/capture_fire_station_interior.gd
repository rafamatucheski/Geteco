extends SceneTree
## Quartel de bombeiros no jogo de verdade (Main.tscn), 27/10/2026: fachada pintada vista da rua
## e o interior refeito (textura real, dois caminhões nas baias laterais, equipe de plantão).
## Entra pela baia como o jogador (WeaponShopEntrance) e fotografa com a câmera do jogo de três
## pontos do salão. Confere que os caminhões e a equipe existem e que viraram colisão.
## Uso (com tela, nunca --headless):
##   "$GODOT" --path . --script res://tests/capture/capture_fire_station_interior.gd -- --no-save [--label=depois]
## Save isolado (fixture) e --no-save: nada é gravado. PNG em evidence/fire-station-interior-20261027/
## (fora do Git). Sai com 1 se não entrar ou faltar caminhão, bombeiro ou colisão.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const FOLDER := "res://evidence/fire-station-interior-20261027"
const ID := "harbor_fire_station"
## Pontos do salão (coordenadas do interior): portão do meio, entre os caminhões, fundo.
const SPOTS := {"portao": Vector3(0, 0, 8.0), "meio": Vector3(-2.2, 0, 2.0), "fundo": Vector3(4.0, 0, -6.0)}

var world
var failures: Array[String] = []
var label := "atual"

func _initialize() -> void:
	create_timer(600.0, true, false, true).timeout.connect(func():
		push_error("FIRE_INTERIOR passou de 600 s")
		quit(2))
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		push_error("FIRE_INTERIOR precisa de janela e --no-save")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
	root.size = Vector2i(1600, 900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var fixture_path := FOLDER.path_join("fixture-save.json")
	var snapshot := FIXTURE.full_snapshot(Vector3(369.8, .08, -72.0), true)
	snapshot.campaign.aftermath = {"call_complete":true}
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshot, "\t"))
	file.close()
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	world.set_meta("menu_save_path", fixture_path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 240000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	if not (world.session != null and world.session.ready_for_play):
		push_error("FIRE_INTERIOR o jogo não ficou pronto")
		quit(3)
		return
	var weather = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	weather.time_of_day = 12.0 / 24.0
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	var walk = world.session.weapon_shop_entrance
	var definition: Dictionary = walk._definition_for(ID)
	var door: Vector3 = walk._door_position(ID, definition)
	var inward: Vector3 = walk._inward(ID)
	await _settle(door - inward * 9.0)
	await _shot("%s_fachada" % label)
	world.player.teleport(door - inward * 2.0 + Vector3.UP * .08)
	for frame in 30: await physics_frame
	var until := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < until and world.session.state.place_id != ID:
		if not world.player.input_locked: world.player.automatic_direction = inward
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	if world.session.state.place_id != ID:
		failures.append("não entrou no quartel")
		_end()
		return
	until = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < until and (world.session.is_transition_blocked() or world.player.input_locked): await physics_frame
	for frame in 120: await process_frame
	_check_contents()
	var place: Node3D = _place()
	for spot in SPOTS:
		if place != null: world.player.teleport(place.global_transform * SPOTS[spot] + Vector3.UP * .08)
		for frame in 90: await process_frame
		await _shot("%s_interior_%s" % [label, spot])
	_end()

func _place() -> Node3D:
	for node in root.find_children("*", "", true, false):
		if node.get("definition") is Dictionary and str(node.definition.get("id", "")) == ID and node.get("solid_bodies") != null: return node
	return null

func _check_contents() -> void:
	var place := _place()
	if place == null:
		failures.append("NativePlace do quartel não encontrado")
		return
	# Filhos diretos da arte: o segundo caminhão vira "ParkedPumper2" e o corpo do bombeiro tem nós próprios.
	var trucks: int = place.model.get_children().filter(func(child: Node): return str(child.name).begins_with("ParkedPumper")).size()
	var crew: int = place.model.get_children().filter(func(child: Node): return str(child.name).begins_with("OnDutyFirefighter")).size()
	var solids: Array[String] = []
	for body in place.solid_bodies: solids.append(str(body.get_meta("interior_solid_id", "")))
	var truck_solids := solids.filter(func(id: String): return id.begins_with("ParkedPumper")).size()
	var crew_solids := solids.filter(func(id: String): return id.begins_with("OnDutyFirefighter")).size()
	print("FIRE_INTERIOR %s caminhões=%d (colisão %d) equipe=%d (colisão %d)" % [label, trucks, truck_solids, crew, crew_solids])
	if trucks != 2 or truck_solids != 2: failures.append("caminhões parados: %d, colisão %d" % [trucks, truck_solids])
	if crew != 2 or crew_solids != 2: failures.append("equipe de plantão: %d, colisão %d" % [crew, crew_solids])

func _end() -> void:
	print("FIRE_INTERIOR %s falhas=%s" % [label, failures])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _settle(point: Vector3) -> void:
	world.player.teleport(point + Vector3.UP * .08)
	world.production.region.set_focus(point, true)
	for frame in 300:
		await process_frame
		if world.production.region.is_streaming_idle() and frame > 90: break
	for frame in 60: await process_frame

func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := FOLDER.path_join(name + ".png")
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("CAPTURE ", ProjectSettings.globalize_path(path))
