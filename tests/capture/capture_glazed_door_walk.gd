extends SceneTree
## Porta de vidro recuada da Union (harbor_clothing) e do posto (harbor_fuel) no jogo de
## verdade (Main.tscn), 19/10/2026. A folha (UrbanLandmarkFrontage3D._build_walkup_door)
## perde a colisão a 10% e só chega aos 0,85 que a travessia pede ~0,25 s depois de o
## jogador começar a empurrar; atrás dela há um vestíbulo de 0,93 m. O jogador nasce 3 m à
## frente e entra pelo mesmo caminho do controle: `GameInput.touch_move` com o direcional no
## fim do curso, andando (3,5 m/s) e com `touch_sprint` (6,5 m/s), no meio da folha e a
## 0,3 m de cada lado. A auditoria de portas anda a 1,6 m/s (Actor.speed) e não via o caso.
## Último caso de cada porta: parado no fundo do vestíbulo até a folha fechar e então
## empurrando para dentro.
## Uso (com tela, nunca --headless):
##   tools/run_godot_locked.sh --path . --script res://tests/capture/capture_glazed_door_walk.gd -- --no-save [--label=x]
## Save isolado (fixture) e --no-save: nada é gravado. PNG só de quem não entrou, em
## evidence/glazed-door-walk-20261019/ (fora do Git). Sai com 1 se algum caso não entrar.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const FOLDER := "res://evidence/glazed-door-walk-20261019"
const IDS := ["harbor_clothing", "harbor_fuel"]
const SPRINT := {"andando": false, "correndo": true}
const LANES := {"meio": 0.0, "esquerda": -0.3, "direita": 0.3}
## Onde a janela de travessia dessas duas portas acabava antes desta sonda.
const OLD_INNER := 0.3

var world
var failures: Array[String] = []
var label := "atual"

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("GLAZED_DOOR exige --no-save para não tocar no save do usuário.")
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
		push_error("GLAZED_DOOR o jogo não ficou pronto")
		quit(3)
		return
	var weather = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	weather.time_of_day = 12.0 / 24.0
	world.player.controlled_automatically = false
	world.camera.set_process_unhandled_input(false)
	var walk = world.session.weapon_shop_entrance
	for id in IDS:
		var definition: Dictionary = walk._definition_for(id)
		var door: Vector3 = walk._door_position(id, definition)
		var inward: Vector3 = walk._inward(id)
		var across := Vector3(-inward.z, 0, inward.x)
		await _settle(door - inward * 3.0)
		print("GLAZED_DOOR %s %s porta=%s dentro=%s meia_largura=%.2f editor=%s" % [label, id, _v(door), _v(inward), walk._half_width(id), definition.get("editor_scale", "-")])
		for gait in SPRINT:
			for lane in LANES:
				await _walk_in(id, "%s %s" % [gait, lane], door - inward * 3.0 + across * LANES[lane], SPRINT[gait], door, inward, across)
		# O corpo para a ~0,63 m (cápsula contra o fundo); 0,55 m fica atrás da folha fechada.
		await _walk_in(id, "vestíbulo parado, folha fechada", door + inward * .55, false, door, inward, across, 150)
	_end()

func _end() -> void:
	_set_stick(Vector3.ZERO, false)
	print("GLAZED_DOOR %s falhas=%d" % [label, failures.size()])
	for failure in failures: print("  FALHA: ", failure)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

## Direcional no fim do curso na direção do mundo pedida, pela base da câmera (o mesmo
## caminho de Actor e de WeaponShopEntrance._movement_intent).
func _set_stick(direction: Vector3, sprint: bool) -> void:
	var controls: Node = root.get_node("GameInput")
	controls.touch_sprint = sprint and not direction.is_zero_approx()
	if direction.is_zero_approx():
		controls.touch_move = Vector2.ZERO
		return
	var right: Vector3 = world.camera.global_basis.x
	var back: Vector3 = world.camera.global_basis.z
	right.y = 0
	back.y = 0
	controls.touch_move = Vector2(direction.dot(right.normalized()), direction.dot(back.normalized())).normalized()

## Parte de `start`, espera `idle_frames` parado (a folha fecha) e empurra para dentro até a
## troca (WeaponShopEntrance._entering) ou o corpo parar. Registra onde a troca começou, a
## maior velocidade e a maior abertura da folha; se não entrou, onde parou.
func _walk_in(id: String, name: String, start: Vector3, sprint: bool, door: Vector3, inward: Vector3, across: Vector3, idle_frames := 30) -> void:
	var walk = world.session.weapon_shop_entrance
	var player = world.player
	if world.gameplay.stars > 0: world.gameplay.clear_wanted()
	_set_stick(Vector3.ZERO, false)
	player.teleport(start + Vector3.UP * .08)
	for frame in idle_frames: await physics_frame
	var closed: float = walk._door_amount
	var result := {"entered":false, "start":Vector3.INF, "peak":0.0, "speed":0.0, "frame_ms":0.0}
	var until := Time.get_ticks_msec() + 6000
	var last: Vector3 = player.global_position
	var last_ms := Time.get_ticks_msec()
	var still_since := last_ms
	while Time.get_ticks_msec() < until:
		if world.session.state.place_id == id:
			result.entered = true
			break
		if walk._entering:
			if not result.start.is_finite(): result.start = player.global_position
			# Solta o direcional como quem vê o zoom da porta começar.
			_set_stick(Vector3.ZERO, false)
		elif not player.input_locked:
			_set_stick(inward, sprint)
		result.peak = maxf(result.peak, walk._door_amount)
		await process_frame
		var now := Time.get_ticks_msec()
		var step: float = (player.global_position - last).length()
		# Velocidade que o Actor pediu (direcional × 3,5 ou 6,5), não a distância por quadro.
		result.speed = maxf(result.speed, Vector2(player.velocity.x, player.velocity.z).length())
		result.frame_ms = maxf(result.frame_ms, float(now - last_ms))
		if step > .03: still_since = now
		last = player.global_position
		last_ms = now
		if not walk._entering and not player.input_locked and now - still_since > 1200: break
	_set_stick(Vector3.ZERO, false)
	if not result.entered:
		var settle := Time.get_ticks_msec() + 6000
		while Time.get_ticks_msec() < settle and walk._entering: await physics_frame
		result.entered = world.session.state.place_id == id
	var where: Vector3 = result.start if result.start.is_finite() else player.global_position
	var depth: float = (where - door).dot(inward)
	var side: float = (where - door).dot(across)
	var case := "%s %s (folha antes %.2f, maior velocidade %.1f m/s, maior quadro %.0f ms)" % [id, name, closed, result.speed, result.frame_ms]
	if result.entered:
		print("GLAZED_DOOR %s %s: ENTROU, troca começou a %+.2f m do plano da folha%s, %+.2f m de lado; folha %.2f" % [label, case, depth, " (fora da janela antiga de %.1f m)" % OLD_INNER if depth > OLD_INNER else "", side, result.peak])
	else:
		print("GLAZED_DOOR %s %s: NÃO ENTROU, parado em %s, %+.2f m do plano da folha, %+.2f m de lado; folha %.2f" % [label, case, _v(where), depth, side, result.peak])
		failures.append(case + ": não entrou")
		await _shot("%s_%s_%s" % [label, id, name.replace(" ", "_").replace(",", "")])
	await _leave(id, door, inward)

## Volta para a rua: sai pelo interior se entrou, e espera o bloqueio de reentrada passar.
func _leave(id: String, door: Vector3, inward: Vector3) -> void:
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
	world.player.teleport(door - inward * 5.0 + Vector3.UP * .08)
	for frame in 60: await physics_frame

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
