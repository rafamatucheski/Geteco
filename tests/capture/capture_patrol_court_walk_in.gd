extends SceneTree
## Sobrados do Patrol Court (atrás da delegacia) e orla do porto no jogo de verdade
## (Main.tscn), 19/10/2026. Fotos de dia da orla onde o editor tinha tirado o asfalto e
## dos quatro sobrados; depois o jogador nasce 3 m à frente de cada porta pintada e
## empurra o direcional para dentro, como no controle. Mede quanto tempo a troca leva.
## Uso (com tela, nunca --headless):
##   tools/run_godot_locked.sh --path . --script res://tests/capture/capture_patrol_court_walk_in.gd -- --no-save [--label=x]
## Save isolado (fixture). PNG em evidence/patrol-court-20261019/ (fora do Git).
## Sai com 1 se algum sobrado não entrar em 6 s.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const CATALOG := preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const FOLDER := "res://evidence/patrol-court-20261019"
const HOUSES := ["PatrolCourtWest", "PatrolCourtMiddle", "PatrolCourtNorth", "PatrolCourtSouth"]
## Trecho da orla onde as peças Harbor_Road tinham sido apagadas/arrastadas para a água.
const WATERFRONT := [Vector3(-24, 0, 150), Vector3(5, 0, 150)]

var world
var label := "atual"
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("PATROL_WALK exige --no-save para não tocar no save do usuário.")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var fixture_path := FOLDER.path_join("fixture-save.json")
	# Mesmo ponto de nascer da sonda da porta de vidro: perto do Patrol Court o save
	# isolado abria a tela da oficina por cima do jogo e as fotos saíam pretas.
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
		push_error("PATROL_WALK o jogo não ficou pronto")
		quit(3)
		return
	world.player.set_meta(preload("res://gameplay/DamageProtection.gd").META, true)
	var weather = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	weather.time_of_day = 12.0 / 24.0
	world.player.controlled_automatically = false
	world.camera.set_process_unhandled_input(false)
	for index in WATERFRONT.size():
		await _settle(WATERFRONT[index])
		await _shot("%s_orla_%d" % [label, index])
	for id in HOUSES:
		var def: Dictionary = CATALOG.for_source(id)
		if def.is_empty():
			failures.append(id + " sem interior no catálogo")
			print("PATROL_WALK %s %s: sem interior (exterior_only)" % [label, id])
			continue
		var inward := Vector3.FORWARD.rotated(Vector3.UP, float(def.exterior_rotation))
		var door: Vector3 = def.entry_position - inward * .9
		# Numa rodada o jogador acordou no hospital entre um sobrado e outro; sai de
		# qualquer interior antes de medir o próximo.
		if not world.session.state.place_id.is_empty():
			print("PATROL_WALK %s %s: estava em %s, saindo antes" % [label, id, world.session.state.place_id])
			await world.session.leave_place()
			for frame in 120: await physics_frame
		await _settle(door - inward * 6.0)
		await _shot("%s_%s" % [label, id])
		await _walk_in(def, door, inward)
	_set_stick(Vector3.ZERO)
	print("PATROL_WALK %s falhas=%d" % [label, failures.size()])
	for failure in failures: print("  FALHA: ", failure)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _walk_in(def: Dictionary, door: Vector3, inward: Vector3) -> void:
	var player = world.player
	if world.gameplay.stars > 0: world.gameplay.clear_wanted()
	player.teleport(door - inward * 3.0 + Vector3.UP * .08)
	for frame in 30: await physics_frame
	print("PATROL_WALK %s %s porta=%s dentro=%s jogador=%s vida=%s" % [label, def.source_id, door, inward, player.global_position, player.get("health")])
	var started := Time.get_ticks_msec()
	var until := started + 6000
	var frame_ms := 0.0
	var last := started
	var entered := false
	while Time.get_ticks_msec() < until:
		if world.session.state.place_id == def.id:
			entered = true
			break
		_set_stick(Vector3.ZERO if player.input_locked else inward)
		await process_frame
		var now := Time.get_ticks_msec()
		frame_ms = maxf(frame_ms, float(now - last))
		last = now
	_set_stick(Vector3.ZERO)
	var took := Time.get_ticks_msec() - started
	if entered:
		print("PATROL_WALK %s %s: ENTROU em %d ms a partir de 3 m da porta (maior quadro %.0f ms)" % [label, def.source_id, took, frame_ms])
		for frame in 40: await process_frame
		await _shot("%s_%s_dentro" % [label, def.source_id])
		var session = world.session
		var wait := Time.get_ticks_msec() + 8000
		while Time.get_ticks_msec() < wait and (session.is_transition_blocked() or player.input_locked): await physics_frame
		await session.leave_place()
		wait = Time.get_ticks_msec() + 8000
		while Time.get_ticks_msec() < wait and (session.is_transition_blocked() or player.input_locked): await physics_frame
	else:
		print("PATROL_WALK %s %s: NÃO ENTROU em 6 s, parado em %s" % [label, def.source_id, player.global_position])
		failures.append(str(def.source_id) + " não entrou")
		await _shot("%s_%s_nao_entrou" % [label, def.source_id])

func _set_stick(direction: Vector3) -> void:
	var controls: Node = root.get_node("GameInput")
	controls.touch_sprint = false
	if direction.is_zero_approx():
		controls.touch_move = Vector2.ZERO
		return
	var right: Vector3 = world.camera.global_basis.x
	var back: Vector3 = world.camera.global_basis.z
	right.y = 0
	back.y = 0
	controls.touch_move = Vector2(direction.dot(right.normalized()), direction.dot(back.normalized())).normalized()

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
