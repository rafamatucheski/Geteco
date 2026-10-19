extends SceneTree
## Entradas do banco e da delegacia pintados no jogo de verdade (Main.tscn), 19/10/2026.
## A entrada de verdade (WeaponShopEntrance._door_position) tem de estar no vão pintado e
## a folha tem de abrir para quem empurra fora do centro: o banco tinha a entrada 0,68 m
## atrás das folhas e a delegacia só abria até 0,95 m do meio de um vão de ~1,6 m.
## Para cada uma: o jogador parado 0,9 m à frente da entrada, depois empurrando a
## LATERAL m do centro (folhas abertas em volta dele) e o ponto onde ele cruza para o
## interior, medido em relação ao centro das folhas pintadas (como test_door_audit).
## No fim, a fita de investigação do banco fechado, que segue a mesma entrada.
## Uso (com tela, nunca --headless):
##   "$GODOT" --path . --script res://tests/capture/capture_bank_police_entrances.gd -- --no-save [--hours=12,21.5]
## Save isolado (fixture) e --no-save: nada é gravado. PNG em evidence/door-entrances-20261019/
## (fora do Git). Sai com 1 se alguma entrada não abrir, não entrar ou cruzar longe das folhas.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const FOLDER := "res://evidence/door-entrances-20261019"
## Desvio lateral do empurrão: delegacia além dos 0,95 m antigos; banco perto da borda de 1,1 m.
const LATERAL := {"harbor_bank": 1.0, "harbor_police": 1.2}

var world
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("ENTRANCES exige --no-save para não tocar no save do usuário.")
		quit(2)
		return
	var hours := [12.0]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--hours="):
			hours = []
			for hour in argument.trim_prefix("--hours=").split(","): hours.append(float(hour))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var fixture_path := FOLDER.path_join("fixture-save.json")
	# Campanha completa sem a fala pendente do pós-missão: diálogo aberto bloqueia o empurrão.
	var snapshot := FIXTURE.full_snapshot(Vector3(40.6, .08, 20.0), true)
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
		push_error("ENTRANCES o jogo não ficou pronto")
		quit(3)
		return
	var weather = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	for hour in hours:
		weather.time_of_day = hour / 24.0
		for id in LATERAL: await _entrance(id, int(hour))
	weather.time_of_day = hours[0] / 24.0
	await _tape()
	print("ENTRANCES failures=", failures.size())
	for failure in failures: print("  FALHA: ", failure)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _entrance(id: String, hour: int) -> void:
	var walk = world.session.weapon_shop_entrance
	var door: Vector3 = walk._door_position(id, walk._definition_for(id))
	var inward: Vector3 = walk._inward(id)
	var across := Vector3(-inward.z, 0, inward.x)
	var lateral: float = LATERAL[id]
	if world.gameplay.stars > 0: world.gameplay.clear_wanted()
	await _settle(door - inward * .9)
	var opening := _opening(id)
	if not opening.is_finite():
		failures.append(id + ": sem folhas pintadas de entrada")
		return
	var offset := opening - door
	print("ENTRANCE %s entrada=%s vão=%s afastamento=%.2f m (fundo %.2f, lado %.2f) meia_largura=%.2f" % [id, _v(door), _v(opening), Vector2(offset.x, offset.z).length(), offset.dot(inward), offset.dot(across), walk._half_width(id)])
	await _shot("%s_parado_%02dh" % [id, hour])
	# Empurra fora do centro: a folha tem de abrir e o jogador cruzar perto dela.
	var start: Vector3 = door - inward * 1.6 + across * lateral
	world.player.teleport(start + Vector3.UP * .08)
	for frame in 20: await physics_frame
	var facade := _facade(id)
	var peak := 0.0
	var crossing := Vector3.INF
	var shot := false
	var until := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < until and world.session.state.place_id != id:
		if not world.player.input_locked: world.player.automatic_direction = inward
		if is_instance_valid(facade): peak = maxf(peak, float(facade.open_amount))
		if walk._entering and not crossing.is_finite(): crossing = world.player.global_position
		if not shot and peak >= .6 and not walk._entering:
			shot = true
			world.player.automatic_direction = Vector3.ZERO
			await _shot("%s_empurrando_%02dh" % [id, hour])
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	var entered: bool = world.session.state.place_id == id
	if not crossing.is_finite():
		failures.append("%s: empurrando a %.1f m do centro não atravessou (abriu %.2f; parou em %s, modal=%s)" % [id, lateral, peak, _v(world.player.global_position), world.session.modal])
	else:
		var depth := (crossing - opening).dot(inward)
		var side := (crossing - door).dot(across)
		print("ENTRANCE %s empurrão a %.1f m: abriu %.2f, cruzou em %s, %.2f m %s das folhas, %.2f m de lado" % [id, lateral, peak, _v(crossing), absf(depth), "dentro" if depth >= 0.0 else "antes", side])
		if absf(depth) > .35: failures.append("%s: cruzou a %.2f m das folhas" % [id, depth])
	if peak < .85: failures.append("%s: a folha abriu só %.2f" % [id, peak])
	if not entered: failures.append(id + ": não entrou")
	if entered: await _back_out()

## Fita de investigação do banco fechado: segue a entrada, na frente das folhas pintadas.
func _tape() -> void:
	var heist = world.session.robberies
	var walk = world.session.weapon_shop_entrance
	var door: Vector3 = walk._door_position("harbor_bank", walk._definition_for("harbor_bank"))
	var inward: Vector3 = walk._inward("harbor_bank")
	var before: String = heist.data.aftermath
	heist.data.aftermath = "closed"
	heist.data.elapsed_days = 0.0
	await _settle(door - inward * 3.0)
	var tape: Node3D = heist.aftermath_controller._tape if heist.aftermath_controller != null else null
	if not is_instance_valid(tape) or not tape.visible: failures.append("fita do banco fechado não apareceu")
	else: print("ENTRANCE fita do banco em %s (%.2f m à frente da entrada)" % [_v(tape.global_position), (door - tape.global_position).dot(inward)])
	await _shot("harbor_bank_fita")
	heist.data.aftermath = before

func _back_out() -> void:
	var session = world.session
	var until := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < until and (session.is_transition_blocked() or world.player.input_locked or not is_instance_valid(session.room)): await physics_frame
	for frame in 20: await physics_frame
	world.player.teleport(session.room.exit_position + Vector3(0, .08, -.53))
	for frame in 5: await physics_frame
	world.player.automatic_direction = Vector3.BACK
	until = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < until and not session.state.place_id.is_empty(): await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	until = Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < until and (session.weapon_shop_entrance._leaving or world.player.input_locked): await physics_frame
	if not session.state.place_id.is_empty(): failures.append("não saiu de " + session.state.place_id)

func _settle(point: Vector3) -> void:
	world.player.teleport(point + Vector3.UP * .08)
	world.player.rotation.y = 0.0
	world.production.region.set_focus(point, true)
	for frame in 300:
		await process_frame
		if world.production.region.is_streaming_idle() and frame > 90: break
	for frame in 60: await process_frame

func _facade(id: String) -> Node:
	for candidate in get_nodes_in_group("v2_walkin_facade"):
		if str(candidate.get_meta("place_id", "")) == id: return candidate
	return null

## Centro visível do vão de entrada: o meio das folhas pintadas fechadas (test_door_audit).
func _opening(id: String) -> Vector3:
	var facade := _facade(id)
	if facade == null: return Vector3.INF
	var art: Node = facade.get_parent() if str(facade.name) == "WalkupDoor" else facade
	for anchor in art.find_children("Doorway_front*", "Node3D", true, false):
		if not anchor.has_meta("walk_in"): continue
		var sum := Vector3.ZERO
		var count := 0
		for leaf in anchor.get_children():
			if not leaf is PaintedFacadeKit.PaintedDoor: continue
			sum += leaf.global_transform * (leaf.hinge.position + leaf.hinge.get_child(0).position)
			count += 1
		if count > 0: return Vector3(sum.x, 0, sum.z) / Vector3(count, 1, count)
	return Vector3.INF

func _shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := FOLDER.path_join(label + ".png")
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("CAPTURE ", ProjectSettings.globalize_path(path), " jogador=", _v(world.player.global_position))

func _v(v: Vector3) -> String: return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
