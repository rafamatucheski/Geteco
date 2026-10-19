extends SceneTree
## Baia aberta do quartel pintado (estilo bombeiros) no jogo de verdade (Main.tscn), 19/10/2026.
## A entrada harbor_fire_station fica na baia da direita, um vão de ~5,4 m sem folha nem
## colisão, com o vestíbulo de 1,8 m de PaintedFireStation atrás. O jogador nasce 3 m à
## frente e anda reto para dentro em cinco faixas (rente a cada ombreira, 0,5 m para dentro
## de cada uma e o meio da baia), andando (3,5 m/s) e correndo (6,5 m/s), as velocidades do controle; a
## auditoria de portas anda a 1,6 m/s, a velocidade padrão do Actor automático. Último caso:
## parado no fundo do vestíbulo e depois empurrando para dentro.
## As ombreiras saem dos Doorway_front* sem folha da arte carregada (como test_door_audit).
## Uso (com tela, nunca --headless):
##   "$GODOT" --path . --script res://tests/capture/capture_fire_station_bay_walk.gd -- --no-save [--label=antes]
## Save isolado (fixture) e --no-save: nada é gravado. PNG em evidence/fire-station-bay-20261019/
## (fora do Git). Sai com 1 se alguma faixa não trocar para o interior.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const FOLDER := "res://evidence/fire-station-bay-20261019"
const ID := "harbor_fire_station"
const SPEEDS := [3.5, 6.5]
## Distância de cada ombreira até o centro do corpo do jogador nas faixas da beira; "rente"
## é o corpo (cápsula de 0,30 m) a 1 cm da parede, como quem desliza encostado nela.
const JAMB_INSET := 0.5
const JAMB_HUG := 0.31

var world
var failures: Array[String] = []
var label := "atual"

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("FIRE_BAY exige --no-save para não tocar no save do usuário.")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var fixture_path := FOLDER.path_join("fixture-save.json")
	# Campanha completa sem a fala pendente do pós-missão (modal bloquearia a entrada).
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
		push_error("FIRE_BAY o jogo não ficou pronto")
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
	var across := Vector3(-inward.z, 0, inward.x)
	await _settle(door - inward * 3.0)
	var bay := _bay(door, across)
	if bay.is_empty():
		failures.append("baia sem folha da entrada não encontrada na arte")
		_end()
		return
	print("FIRE_BAY %s entrada=%s ombreiras=[%+.2f, %+.2f] m do eixo da entrada (vão %.2f m, meio %+.2f) plano %.2f m atrás da entrada; gatilho=%+.2f±%.2f m editor=%s" % [label, _v(door), bay.left, bay.right, bay.right - bay.left, (bay.left + bay.right) * .5, bay.plane_depth, walk._opening_shift(ID), walk._half_width(ID), definition.get("editor_scale", "-")])
	var lanes := {"rente_esquerda": bay.left + JAMB_HUG, "esquerda": bay.left + JAMB_INSET, "meio": (bay.left + bay.right) * .5,
		"direita": bay.right - JAMB_INSET, "rente_direita": bay.right - JAMB_HUG}
	for speed in SPEEDS:
		for lane in lanes:
			await _walk_in(lane, lanes[lane], speed, door, inward, across, bay)
	await _from_vestibule(lanes.meio, door, inward, across, bay)
	_end()

func _end() -> void:
	print("FIRE_BAY %s falhas=%d" % [label, failures.size()])
	for failure in failures: print("  FALHA: ", failure)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

## Anda reto para dentro a `lateral` m do eixo da entrada. Registra onde a troca começa
## (WeaponShopEntrance._entering), a maior abertura do portão e, se não entrou, onde parou.
func _walk_in(lane: String, lateral: float, speed: float, door: Vector3, inward: Vector3, across: Vector3, bay: Dictionary) -> void:
	var walk = world.session.weapon_shop_entrance
	var player = world.player
	if world.gameplay.stars > 0: world.gameplay.clear_wanted()
	player.speed = speed
	player.automatic_direction = Vector3.ZERO
	player.teleport(door - inward * 3.0 + across * lateral + Vector3.UP * .08)
	for frame in 30: await physics_frame
	var name := "%s %.1f m/s (%+.2f m)" % [lane, speed, lateral]
	var result := await _push(walk, player, inward, 6000)
	_report(name, result, door, inward, across, bay)
	if not result.entered: await _shot("%s_%s_%02.0f_parado" % [label, lane, speed * 10.0])
	await _leave(door, inward)

## Parado no fundo do vestíbulo até o portão fechar e então empurrando para dentro: quem
## parou na baia (ou voltou de lado para o meio dela) tem de conseguir entrar sem recuar.
func _from_vestibule(lateral: float, door: Vector3, inward: Vector3, across: Vector3, bay: Dictionary) -> void:
	var walk = world.session.weapon_shop_entrance
	var player = world.player
	if world.gameplay.stars > 0: world.gameplay.clear_wanted()
	player.speed = SPEEDS[0]
	player.automatic_direction = Vector3.ZERO
	player.teleport(door + inward * (bay.plane_depth + 1.2) + across * lateral + Vector3.UP * .08)
	for frame in 150: await physics_frame
	var name := "vestíbulo parado %.1f s, portão %.2f" % [150.0 / 60.0, walk._door_amount]
	var result := await _push(walk, player, inward, 4000)
	_report(name, result, door, inward, across, bay)
	if not result.entered: await _shot("%s_vestibulo_parado" % label)
	await _leave(door, inward)

func _push(walk, player, inward: Vector3, ms: int) -> Dictionary:
	var result := {"entered":false, "start":Vector3.INF, "peak":0.0, "deepest":-INF, "stop":Vector3.INF}
	var until := Time.get_ticks_msec() + ms
	var last: Vector3 = player.global_position
	var still_since := Time.get_ticks_msec()
	while Time.get_ticks_msec() < until:
		if world.session.state.place_id == ID:
			result.entered = true
			break
		if not player.input_locked: player.automatic_direction = inward
		result.peak = maxf(result.peak, walk._door_amount)
		if walk._entering and not result.start.is_finite(): result.start = player.global_position
		if player.global_position.distance_to(last) > .03:
			last = player.global_position
			still_since = Time.get_ticks_msec()
		if not walk._entering and not player.input_locked and Time.get_ticks_msec() - still_since > 1200: break
		await physics_frame
	player.automatic_direction = Vector3.ZERO
	if not result.entered:
		var settle := Time.get_ticks_msec() + 6000
		while Time.get_ticks_msec() < settle and walk._entering: await physics_frame
		result.entered = world.session.state.place_id == ID
	result.stop = player.global_position if not result.entered else result.start
	return result

func _report(name: String, result: Dictionary, door: Vector3, inward: Vector3, across: Vector3, bay: Dictionary) -> void:
	if result.entered:
		var depth: float = (result.start - door).dot(inward) - bay.plane_depth
		print("FIRE_BAY %s %s: ENTROU, troca começou %.2f m %s do plano da baia, %+.2f m de lado; portão %.2f" % [label, name, absf(depth), "dentro" if depth >= 0.0 else "antes", (result.start - door).dot(across), result.peak])
		return
	var depth: float = (result.stop - door).dot(inward) - bay.plane_depth
	print("FIRE_BAY %s %s: NÃO ENTROU, parado em %s, %.2f m %s do plano da baia (vestíbulo %.1f m), %+.2f m de lado; portão %.2f" % [label, name, _v(result.stop), absf(depth), "dentro" if depth >= 0.0 else "antes", PaintedFireStation.VESTIBULE_DEPTH, (result.stop - door).dot(across), result.peak])
	failures.append(name + ": não entrou")

## Volta para a rua: sai pelo interior se entrou, e espera o bloqueio de reentrada passar.
func _leave(door: Vector3, inward: Vector3) -> void:
	var session = world.session
	var walk = session.weapon_shop_entrance
	if not session.state.place_id.is_empty():
		var until := Time.get_ticks_msec() + 8000
		while Time.get_ticks_msec() < until and (session.is_transition_blocked() or world.player.input_locked): await physics_frame
		for frame in 30: await physics_frame
		await session.leave_place()
		until = Time.get_ticks_msec() + 8000
		while Time.get_ticks_msec() < until and (walk._leaving or session.is_transition_blocked() or world.player.input_locked): await physics_frame
		if not session.state.place_id.is_empty(): failures.append("não saiu de " + session.state.place_id)
	world.player.automatic_direction = Vector3.ZERO
	world.player.teleport(door - inward * 5.0 + Vector3.UP * .08)
	for frame in 60: await physics_frame

## Ombreiras da baia sem folha que contém a entrada, em metros ao longo de `across` a partir
## da entrada, e a profundidade do plano pintado medida na direção de dentro.
func _bay(door: Vector3, across: Vector3) -> Dictionary:
	var art: Node = null
	for candidate in get_nodes_in_group("v2_walkin_facade"):
		if str(candidate.get_meta("place_id", "")) == ID: art = candidate
	if art == null: return {}
	for anchor in art.find_children("Doorway_front*", "Node3D", true, false):
		if not anchor.has_meta("leafless"): continue
		var size: Vector2 = anchor.get_meta("opening_size")
		var a: float = (anchor.global_transform * Vector3.ZERO - door).dot(across)
		var b: float = (anchor.global_transform * Vector3(size.x, 0, 0) - door).dot(across)
		if minf(a, b) > 0.0 or maxf(a, b) < 0.0: continue
		var plane: float = (anchor.global_position - door).dot(-anchor.global_basis.z.normalized())
		return {"left":minf(a, b), "right":maxf(a, b), "plane_depth":plane}
	return {}

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
	print("CAPTURE ", ProjectSettings.globalize_path(path), " jogador=", _v(world.player.global_position))

func _v(v: Vector3) -> String: return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
