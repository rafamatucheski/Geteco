extends SceneTree

## Etapa 2 -- reprodução com dados reais (não presume a causa) de:
##   (a) viatura de polícia girando/travando repetidamente durante perseguição real
##   (b) ambulância/coroner cortando pela quadra ao ser despachada para o hospital
## Roda HarborGame.tscn de verdade (Vulkan, sem --headless), dispara uma
## perseguição real via WantedManager e um atropelamento sobrevivível real
## via AnimatedPedestrian3D.get_run_over() perto do hospital (mesmo padrão de
## tests/test_rescue_and_burial_flow.gd), depois instrumenta cada
## emergency_vehicle real por 45s: nº de ciclos de ré (is_reversing
## false->true), deslocamento líquido, e se o roteador linkou rede/lane ou
## caiu sem rota nenhuma. Nada é teleportado; nenhuma colisão é desligada.
##
## Uso: Godot..._console.exe --path D:/geteco/game --script res://tests/reproduce_review_0909_stage2.gd

const GAME_SCENE := "res://world/harbor/HarborGame.tscn"
const WARMUP_FRAMES := 90
const OBSERVE_SECONDS := 45.0

var game: Node2D
var _log_lines: PackedStringArray = []
var _tracked: Dictionary = {} # instance_id -> stats dict

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var settings := root.get_node("SettingsManager")
	settings.set_resolution(Vector2i(1280, 720))
	settings.set_window_mode(0)
	for i in 5:
		await process_frame

	var packed := load(GAME_SCENE) as PackedScene
	game = packed.instantiate() as Node2D
	root.add_child(game)
	current_scene = game
	for i in WARMUP_FRAMES:
		await process_frame

	# HarborGame plays a paused arrival cutscene on first load
	# (HarborArrivalMission._begin_arrival(), get_tree().paused=true) that
	# blocks HarborEmergencyDirector.request_dispatch()'s can_process() check
	# -- found by direct reproduction (an earlier run here showed every
	# dispatch silently returning null with paused=true). Skip it the same
	# way a real player would (the button the cutscene itself exposes),
	# not by touching pause state directly.
	var campaign = game.get("campaign_controller")
	if campaign and campaign.has_method("skip_cinematic"):
		campaign.call("skip_cinematic")
	for i in 60:
		await process_frame
	_log("REVIEW0909_STAGE2_DEBUG tree_paused_after_skip=%s" % [str(paused)])

	var car := game.get_node("PlayerCar") as CharacterBody2D
	var player := game.get_node("Player") as CharacterBody2D
	# Delegacia: prédio Police ocupa x:985-1175 y:1785-2035 (HarborDistrict.gd);
	# PatrolAccess (a garagem/saída de veículo) é o Rect2(985,2035,190,105)
	# logo ao sul, marcador em (1080,2085) -- fora do footprint do prédio.
	# Um teste anterior colocou o carro em (1150,1980), DENTRO do prédio, o
	# que bloqueava o spawn-clear de todo despacho; corrigido aqui.
	# On dock_street itself (centerline y~2200), south of the depot apron so
	# the player car doesn't sit on the spawn/exit point and block it.
	car.global_position = Vector2(1080, 2200)
	car.rotation = 0.0
	car.velocity = Vector2.ZERO
	player.global_position = car.global_position + Vector2(-48, 0)
	for i in 3:
		await physics_frame
	game.call("_drive")

	var weather: CanvasModulate = game.get("weather")
	weather.time_of_day = 0.5
	weather.set_biome(weather.current_biome)
	weather.set_weather(1)

	var wanted = root.get_node("WantedManager")
	wanted.reset_crime()
	for i in 3:
		await process_frame
	wanted.report_crime(120) # perseguição real: viaturas reais despachadas

	# Atropelamento sobrevivível real perto do hospital (ClinicAccess ~(1910,1705))
	# para forçar despacho real de ambulância nessa área, mesmo padrão de
	# tests/test_rescue_and_burial_flow.gd.
	var victim: Node2D = null
	for p in get_nodes_in_group("pedestrian"):
		if is_instance_valid(p) and not bool(p.get("is_incapacitated")) and not bool(p.get("is_dead")) \
				and p.global_position.distance_to(Vector2(1910, 1705)) < 900.0:
			victim = p
			break
	if victim:
		victim.global_position = Vector2(1950, 1680)
		if victim.has_method("get_run_over"):
			victim.call("get_run_over", Vector2(140, 0))
			_log("REVIEW0909_STAGE2 victim_placed=%s pos=%s" % [victim.name, str(victim.global_position)])
	else:
		_log("REVIEW0909_STAGE2 victim_placed=none (no pedestrian found near hospital within 900px)")

	var elapsed := 0.0
	var frame_i := 0
	while elapsed < OBSERVE_SECONDS:
		var phase := int(elapsed) % 6
		Input.action_press("ui_up")
		if phase < 2:
			Input.action_press("ui_left"); Input.action_release("ui_right")
		elif phase >= 3 and phase < 5:
			Input.action_press("ui_right"); Input.action_release("ui_left")
		else:
			Input.action_release("ui_left"); Input.action_release("ui_right")

		var t0 := Time.get_ticks_usec()
		await process_frame
		elapsed += (Time.get_ticks_usec() - t0) / 1000000.0
		frame_i += 1
		if frame_i % 6 == 0: # ~10Hz sampling of emergency vehicles
			_sample_vehicles()

	Input.action_release("ui_up")
	Input.action_release("ui_left")
	Input.action_release("ui_right")
	_report()
	_write_report()
	quit(0)

func _sample_vehicles() -> void:
	for v in get_nodes_in_group("emergency_vehicle"):
		if not is_instance_valid(v):
			continue
		var id := v.get_instance_id()
		if not _tracked.has(id):
			_tracked[id] = {
				"type": int(v.get("type")),
				"first_pos": v.global_position,
				"last_pos": v.global_position,
				"was_reversing": bool(v.get("is_reversing")),
				"reverse_cycles": 0,
				"total_dist": 0.0,
				"samples": 0,
				"no_route_samples": 0,
			}
		var s: Dictionary = _tracked[id]
		var now_reversing: bool = bool(v.get("is_reversing"))
		if now_reversing and not s.was_reversing:
			s.reverse_cycles += 1
		s.was_reversing = now_reversing
		s.total_dist += v.global_position.distance_to(s.last_pos)
		s.last_pos = v.global_position
		s.samples += 1
		var router = v.get("_lane_router")
		if router != null:
			var has_network: bool = is_instance_valid(router.network)
			var has_linked: bool = is_instance_valid(router.linked_lane)
			var has_legs: bool = not router.legs.is_empty()
			if not has_network and not has_linked and not has_legs:
				s.no_route_samples += 1
		_tracked[id] = s

func _report() -> void:
	for id in _tracked.keys():
		var s: Dictionary = _tracked[id]
		var net_disp: float = s.first_pos.distance_to(s.last_pos)
		var type_names := ["POLICE", "AMBULANCE", "FIRE", "CORONER"]
		var type_name: String = type_names[s.type] if s.type >= 0 and s.type < 4 else str(s.type)
		_log("REVIEW0909_STAGE2_VEHICLE id=%d type=%s reverse_cycles=%d samples=%d total_dist=%.0f net_displacement=%.0f no_route_samples=%d last_pos=%s" % [
			id, type_name, s.reverse_cycles, s.samples, s.total_dist, net_disp, s.no_route_samples, str(s.last_pos)
		])
		if s.reverse_cycles >= 3 and net_disp < 250.0:
			_log("REVIEW0909_STAGE2_FINDING vehicle_id=%d SPINNING_IN_PLACE reverse_cycles=%d net_displacement=%.0f" % [id, s.reverse_cycles, net_disp])
		if s.no_route_samples > 0 and s.samples > 0 and float(s.no_route_samples) / float(s.samples) > 0.3:
			_log("REVIEW0909_STAGE2_FINDING vehicle_id=%d NO_ROUTE_MOST_OF_TIME fraction=%.2f" % [id, float(s.no_route_samples) / float(s.samples)])

func _log(line: String) -> void:
	print(line)
	_log_lines.append(line)

func _write_report() -> void:
	var out_dir := "D:/geteco/perf-review-0909"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path := out_dir.path_join("review0909_stage2.txt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_log_lines))
		f.close()
	print("REVIEW0909_STAGE2_REPORT " + path)
