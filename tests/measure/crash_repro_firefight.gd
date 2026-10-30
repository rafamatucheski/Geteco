extends Node
## RASCUNHO (29/10) — reprodução do crash c0000005 em RenderForwardClustered::_render_scene (ordenação da
## lista transparente) que só aparece no jogo livre do jogador: a pé no porto, tiroteio com a polícia
## chegando, policiais descendo das viaturas (mocap, recorte de portas), muitos mortos e sangue no chão.
##
## Por que não é o --benchmark-stress: lá o jogador fica escondido (player.visible = false, sem física), o
## alvo da polícia é o carro andando a 25 m/s (driving.occupied), então police_can_see() nunca vê ninguém, a
## viatura quase nunca estaciona (_police_parked volta a "enroute" com alvo motorizado), quase nenhuma equipe
## desce perto da câmera e os tiros vão para pontos vazios 18 m à frente do carro (quase ninguém morre por
## bala). A câmera segue o carro, então a silhueta de oclusão dos policiais (material_overlay transparente,
## PoliceOcclusionSilhouette, só a < 70 m da câmera) quase nunca entra na lista transparente.
##
## Este nó faz o contrário: jogador visível, a pé, parado perto de --play-at, câmera normal do jogo (a
## configuração camera_view do settings.cfg usado), estrelas mantidas num piso para a central mandar
## equipes de novo e de novo, e tiro contínuo (Gameplay.fire_at, o caminho do jogo) no policial vivo mais
## perto, depois no civil vivo mais perto. Não teleporta ninguém, não mexe em v-sync/limite de fps.
##
## NÃO RODA NO RELEASE COMO ESTÁ: o export exclui tests/** (export_presets.cfg) e ignora --script. Para
## usar, copiar para runtime/FirefightRepro.gd e acrescentar em ProductionWorld, ao lado do
## RELEASE_BENCHMARK (mesma guarda: sessão pronta e rua viva):
##     if not _firefight_repro_started and "--repro-firefight" in OS.get_cmdline_user_args():
##         _firefight_repro_started = true
##         var repro: Node = load("res://runtime/FirefightRepro.gd").new()
##         repro.name = "FirefightRepro"
##         repro.world = world
##         add_child(repro)
##
## Opções (depois do `--`): --repro-firefight --firefight-seconds=360 --firefight-stars=4
##   --firefight-weapon=ak47 --firefight-god=1 --firefight-aim=1 --firefight-strafe=0
##   --firefight-civilians=1 --firefight-range=32 --label=x
## Batimento a cada 5 s no stdout ("REPRO_FIREFIGHT ...") e em user://repro-firefight/<label>.log com
## flush por linha, para a última linha sobreviver ao crash.
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const HEARTBEAT_SECONDS := 5.0

var world: Node
var label := "firefight"
var seconds := 360.0
var star_floor := 4
var weapon := "ak47"
var god := true
var aim_hold := true
var strafe := false
var shoot_civilians := true
var max_range := 32.0

var _log: FileAccess
var _clock := 0.0
var _beat_clock := 0.0
var _crime_clock := 0.0
var _strafe_clock := 0.0
var _strafe_left := false
var _anchor := Vector3.INF
var _shots := 0
var _shots_officer := 0
var _shots_civilian := 0
var _shots_empty := 0
var _officer_kills := 0
var _civilian_kills := 0
var _seen_officers := {}
var _seen_dead := {}
var _peak_units := 0
var _peak_foot := 0
var _frames := 0
var _worst_ms := 0.0
var _beat_worst_ms := 0.0
var _previous_usec := 0

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
		if argument.begins_with("--firefight-seconds="): seconds = maxf(10.0, float(argument.trim_prefix("--firefight-seconds=")))
		if argument.begins_with("--firefight-stars="): star_floor = clampi(int(argument.trim_prefix("--firefight-stars=")), 0, 6)
		if argument.begins_with("--firefight-weapon="): weapon = argument.trim_prefix("--firefight-weapon=")
		if argument.begins_with("--firefight-god="): god = argument.trim_prefix("--firefight-god=") != "0"
		if argument.begins_with("--firefight-aim="): aim_hold = argument.trim_prefix("--firefight-aim=") != "0"
		if argument.begins_with("--firefight-strafe="): strafe = argument.trim_prefix("--firefight-strafe=") != "0"
		if argument.begins_with("--firefight-civilians="): shoot_civilians = argument.trim_prefix("--firefight-civilians=") != "0"
		if argument.begins_with("--firefight-range="): max_range = clampf(float(argument.trim_prefix("--firefight-range=")), 5.0, 80.0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://repro-firefight"))
	_log = FileAccess.open("user://repro-firefight/%s.log" % label, FileAccess.WRITE)
	_run.call_deferred()

func _line(text: String) -> void:
	var stamped := "REPRO_FIREFIGHT t=%.1f %s" % [_clock, text]
	print(stamped)
	if _log != null:
		_log.store_line("%d %s" % [Time.get_ticks_msec(), stamped])
		_log.flush()

func _run() -> void:
	# Mesma espera do ReleaseBenchmark: 3 s seguidos jogável e com 3D ligado (o filme da balsa
	# começa ~1 s depois de ready_for_play quando não há --skip-arrival).
	var stable_since := -1
	while stable_since < 0 or Time.get_ticks_msec() - stable_since < 3000:
		await get_tree().process_frame
		var playable: bool = not get_tree().paused and world.session.ready_for_play and not get_viewport().disable_3d
		if not playable: stable_since = -1
		elif stable_since < 0: stable_since = Time.get_ticks_msec()
	var gameplay = world.gameplay
	_line("start playable_ms=%d occupied=%s region=%s player=%s dispatch=%s camera_view=%s" % [stable_since,
		str(world.driving.occupied), str(world.session.state.region_id), str(world.player.global_position),
		str(is_instance_valid(world.get("dispatch"))), str(_camera_view())])
	if world.driving.occupied:
		_line("ABORT jogador ao volante; o cenário é a pé")
		_finish(2)
		return
	if not is_instance_valid(world.get("dispatch")):
		_line("ABORT despacho desligado (não passe --no-dispatch)")
		_finish(2)
		return
	_anchor = world.player.global_position
	world.session.state.economy.activate_arsenal_cheat()
	if not gameplay.equip_slot(weapon): _line("aviso: equip_slot(%s) recusou; arma=%s" % [weapon, gameplay.equipped()])
	if god and not gameplay.god_mode: gameplay.toggle_god_mode()
	_hold_stars(gameplay, true)
	_previous_usec = Time.get_ticks_usec()
	while _clock < seconds:
		await get_tree().physics_frame
		var now := Time.get_ticks_usec()
		var frame_ms := (now - _previous_usec) / 1000.0
		_previous_usec = now
		_frames += 1
		_worst_ms = maxf(_worst_ms, frame_ms)
		_beat_worst_ms = maxf(_beat_worst_ms, frame_ms)
		var delta := get_physics_process_delta_time()
		_clock += delta
		var span := STALL_WORK.begin()
		_tick(gameplay, delta)
		STALL_WORK.finish_slow("repro.firefight", span, 2000)
		_beat_clock += delta
		if _beat_clock >= HEARTBEAT_SECONDS:
			_beat_clock = 0.0
			_heartbeat(gameplay)
	_heartbeat(gameplay)
	_line("DONE shots=%d officer_kills=%d civilian_kills=%d worst_ms=%.1f" % [_shots, _officer_kills, _civilian_kills, _worst_ms])
	_finish(0)

func _finish(code: int) -> void:
	for action in ["aim", "move_left", "move_right"]:
		if InputMap.has_action(action): Input.action_release(action)
	if _log != null: _log.close()
	get_tree().quit(code)

func _tick(gameplay, delta: float) -> void:
	_crime_clock -= delta
	if _crime_clock <= 0.0:
		_crime_clock = 1.0
		_hold_stars(gameplay, false)
	_count_dead()
	if aim_hold and InputMap.has_action("aim"): Input.action_press("aim")
	if strafe: _strafe(delta)
	if gameplay.cooldown > 0 or gameplay.reload_timer > 0: return
	var target: Node3D = _nearest_officer()
	var kind := "officer"
	if target == null and shoot_civilians:
		target = _nearest_civilian()
		kind = "civilian"
	var point: Vector3
	if target != null: point = target.global_position + Vector3.UP * 1.1
	else:
		# Sem alvo: tiro para o lado da rua, como quem atira a esmo; mantém o crime de disparo.
		kind = "empty"
		point = world.player.global_position + Vector3(sin(_clock), 0.0, cos(_clock)) * 15.0 + Vector3.UP
	if gameplay.fire_at(point):
		_shots += 1
		if kind == "officer": _shots_officer += 1
		elif kind == "civilian": _shots_civilian += 1
		else: _shots_empty += 1

## Piso de estrelas: abaixo de 5 a central para depois de DEPLOYMENT[estrelas] equipes por perseguição
## (DispatchRules); com 4 o jogo ainda escala sozinho com as mortes de policiais e civis.
func _hold_stars(gameplay, first: bool) -> void:
	if star_floor <= 0: return
	if int(gameplay.stars) < star_floor:
		var needed: int = int(gameplay.STAR_THRESHOLDS[star_floor]) - int(gameplay.crime_points)
		gameplay.register_crime(maxi(needed, 1), world.player.global_position, "repro_firefight")
	elif first:
		gameplay.report_contact(world.player.global_position)

func _strafe(delta: float) -> void:
	_strafe_clock -= delta
	if _strafe_clock <= 0.0:
		_strafe_clock = 2.5
		_strafe_left = not _strafe_left
	var offset: float = world.player.global_position.x - _anchor.x
	var go_left := _strafe_left if absf(offset) < 4.0 else offset > 0.0
	Input.action_release("move_right" if go_left else "move_left")
	Input.action_press("move_left" if go_left else "move_right")

func _officers() -> Array:
	var list: Array = []
	var seen := {}
	for unit in world.dispatch.units:
		for officer in unit.officers:
			if is_instance_valid(officer) and not seen.has(officer.get_instance_id()):
				seen[officer.get_instance_id()] = true
				list.append(officer)
	for officer in world.gameplay.police:
		if is_instance_valid(officer) and not seen.has(officer.get_instance_id()):
			seen[officer.get_instance_id()] = true
			list.append(officer)
	return list

func _nearest_officer() -> Node3D:
	var best: Node3D = null
	var best_distance := max_range
	var origin: Vector3 = world.player.global_position
	for officer in _officers():
		if bool(officer.get("dead")) or not officer.is_inside_tree() or not officer.is_visible_in_tree(): continue
		var distance: float = origin.distance_to(officer.global_position)
		if distance < best_distance:
			best_distance = distance
			best = officer
	return best

func _nearest_civilian() -> Node3D:
	var best: Node3D = null
	var best_distance := minf(max_range, 25.0)
	var origin: Vector3 = world.player.global_position
	for actor in world.people:
		if not is_instance_valid(actor) or bool(actor.get("dead")) or not actor.is_inside_tree() or not actor.is_visible_in_tree(): continue
		var distance: float = origin.distance_to(actor.global_position)
		if distance > 2.0 and distance < best_distance:
			best_distance = distance
			best = actor
	return best

## Conta mortes pela transição vivo→morto de quem já foi visto vivo (policial ou civil).
func _count_dead() -> void:
	for officer in _officers():
		var key: int = officer.get_instance_id()
		var dead := bool(officer.get("dead"))
		if not _seen_officers.has(key): _seen_officers[key] = dead
		elif dead and not _seen_officers[key]:
			_seen_officers[key] = true
			_officer_kills += 1
	if _frames % 15 != 0: return
	for actor in world.people:
		if not is_instance_valid(actor): continue
		var key: int = actor.get_instance_id()
		var dead := bool(actor.get("dead"))
		if not _seen_dead.has(key): _seen_dead[key] = dead
		elif dead and not _seen_dead[key]:
			_seen_dead[key] = true
			_civilian_kills += 1

func _heartbeat(gameplay) -> void:
	var units: int = world.dispatch.units.size()
	var foot: int = world.dispatch.foot_officer_count()
	_peak_units = maxi(_peak_units, units)
	_peak_foot = maxi(_peak_foot, foot)
	var alive := 0
	var near_camera := 0
	var camera := get_viewport().get_camera_3d()
	for officer in _officers():
		if bool(officer.get("dead")): continue
		alive += 1
		if camera != null and camera.global_position.distance_to(officer.global_position) < 70.0: near_camera += 1
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	_line("fps=%.0f worst_ms=%.1f stars=%d crime=%d units=%d foot=%d officers_alive=%d near_cam=%d officer_kills=%d civilian_kills=%d shots=%d/%d/%d/%d weapon=%s player=(%.1f,%.1f) health=%.0f occupied=%s draws=%d objects=%d nodes=%d" % [
		fps, _beat_worst_ms, int(gameplay.stars), int(gameplay.crime_points), units, foot, alive, near_camera,
		_officer_kills, _civilian_kills, _shots, _shots_officer, _shots_civilian, _shots_empty, str(gameplay.equipped()),
		world.player.global_position.x, world.player.global_position.z, float(gameplay.health), str(world.driving.occupied),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	_beat_worst_ms = 0.0

func _camera_view() -> int:
	var settings: Node = get_node_or_null("/root/V2Settings")
	return int(settings.get("camera_view")) if settings != null and "camera_view" in settings else -1
