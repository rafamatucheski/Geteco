extends Node3D
const COURSE := preload("res://activities/mountain_downhill/MountainDownhillCourse.gd")
const RUN := preload("res://activities/mountain_downhill/MountainDownhillRun.gd")
const PILOT := preload("res://activities/mountain_downhill/MountainDownhillDriver.gd")
const PROGRESS := preload("res://systems/campaign/MountainDownhillProgress.gd")
const PROPS := preload("res://activities/mountain_downhill/MountainDownhillProps.gd")
const MODELS := ["sport_coupe","monaliza","porto_rosso","vertice_midengine","cobra_v8","muscle_classic"]
const NAMES := ["Akira","Maya","Ícaro","Yuri","Ren","Haruka","Dante"]
var session
var course := COURSE.new()
var active := false
var countdown := 0.0
var racers: Array[Dictionary] = []
var player_car
var last_result: Dictionary = {}
var props: Node3D
var hud: PanelContainer
var status: Label
var board: Label
var _old_lock := false
var _ui_clock := 0.0
var _scene_clock := 0.0
var _modal_motion: Array[Dictionary] = []
## Grampo dos portões 7–9 sem trânsito durante a prova (ProductionWorld.set_traffic_hold), do portão 5 ao 10
## para o carro que estiver chegando também sair. GETECO_DOWNHILL_TRAFFIC_HOLD=0 desliga para comparar.
const HOLD_ID := &"mountain_downhill"
const HOLD_GATES := Vector2i(5,10)
const HOLD_RADIUS := 14.0
## Playtest 30/10: "chegar ali, apertar e carregar o evento". O E não largava quando o carro parava
## perto da largada: os rivais nasciam antes de o carro do jogador ir para a vaga dele, e o próprio
## carro ocupava a vaga de um rival ("largada ocupada"). Agora a tela escurece, o carro vai para a
## vaga, o trânsito sai da grade, os rivais nascem, a tela clareia e começa a contagem com bipes.
## curtain = false monta tudo no mesmo quadro (testes do contrato transacional).
const CUES := preload("res://audio/v1_ambience/V1AudioCatalog.gd")
const FADE_OUT := .35
const FADE_IN := .45
const START_SPEED_LIMIT := 4.0
## (avanço na pista m, abertura da faixa m) de cada tentativa de vaga do rival.
const SLOT_FALLBACKS := [Vector2(0,0),Vector2(0,.6),Vector2(-3,.3),Vector2(3,.3),Vector2(-3,.9)]
var curtain := true
var staging := false
var _stage_generation := 0
var _shown_count := 0
var _cue_voice: AudioStreamPlayer
var banner: Label
## Bipes tocados ("3","2","1","go"), para o teste conferir sem ouvir.
var played_cues: Array[String] = []

func configure(owner_session) -> void:
	session = owner_session
	process_physics_priority = -10
	var saved: Variant = session.state.world_state.get("mountain_downhill",PROGRESS.defaults())
	if not PROGRESS.validate_wallet(saved,session.state.economy.snapshot()):
		session.controller.save_invalid = true
		session.show_message("Dados da descida inválidos; save preservado.")
	var gameplay = session.world.gameplay
	if not gameplay.player_died.is_connected(_on_player_died): gameplay.player_died.connect(_on_player_died)
	if not gameplay.player_arrested.is_connected(_on_player_arrested): gameplay.player_arrested.connect(_on_player_arrested)
	set_physics_process(false)
	CUES.activity("countdown")
	_cue_voice = AudioStreamPlayer.new()
	_cue_voice.name = "DownhillCue"
	_cue_voice.bus = &"UI" if AudioServer.get_bus_index(&"UI")>=0 else &"Master"
	_cue_voice.volume_db = -6
	add_child(_cue_voice)

func snapshot() -> Dictionary:
	return PROGRESS.data(session.state.world_state)

func save_block_reason() -> String:
	return "Encerre a descida noturna para salvar." if active or staging else ""

func objective() -> String:
	if active and racers.size() == 7:
		if countdown > 0: return String(TranslationServer.translate("Descida da Meia Noite · largada em %d")) %ceili(countdown)
		return String(TranslationServer.translate("Descida da Meia Noite · checkpoint %d/%d · %d/7")) %[mini(int(racers[6].run.checkpoint)+1,course.gate_offsets.size()),course.gate_offsets.size(),standings().find(racers[6])+1]
	return "Descida da Meia Noite · leve qualquer veículo à largada entre 20h e 5h"

func target_position() -> Vector3:
	if active and racers.size()==7: return course.gate(int(racers[6].run.checkpoint))
	return course.start_position()

func nearest_action() -> Dictionary:
	if not is_instance_valid(session) or staging: return {}
	if active: return {"id":"mountain_downhill","target":"cancel","label":"Abandonar a descida"}
	if session.controller.save_invalid: return {}
	if session.state.region_id != "mountain" or not session.state.place_id.is_empty(): return {}
	var point: Vector3 = session.world.player.global_position
	if session.world.driving.occupied and is_instance_valid(session.world.driving.car): point = session.world.driving.car.global_position
	if point.distance_to(course.start_position())>9.0: return {}
	var coordinator := get_tree().get_first_node_in_group("mountain_activities")
	if coordinator != null and not coordinator.can_start(self): return {}
	var saved := snapshot()
	if saved.wins>0 and not saved.reward_paid:
		return {"id":"mountain_downhill","target":"claim","label":"Receber prêmio da descida · R$ 2400"}
	return {"id":"mountain_downhill","target":"start","label":"Descida da Meia Noite · seis rivais" if is_night() else "Descida da Meia Noite · 20h–5h"}

func perform(target: String) -> bool:
	if target == "cancel":
		if not active: return false
		cancel_attempt("cancelled")
		return true
	var action := nearest_action()
	if action.is_empty() or str(action.target) != target: return false
	if target == "claim":
		if not PROGRESS.claim_reward(session.state.world_state,session.state.economy):
			session.show_message("Não foi possível receber o prêmio agora.")
			return false
		session.show_message("Prêmio da descida recebido.")
		session.save_game()
		return true
	if target != "start": return false
	var reason := start_block_reason()
	if not reason.is_empty():
		session.show_message(reason)
		return false
	if not curtain or not is_instance_valid(session.get("door_transition")): return _start()
	_stage_start()
	return true

## Largada sob a cortina: escurece, monta a grade, clareia e só então solta a contagem.
func _stage_start() -> void:
	staging = true
	_stage_generation += 1
	var generation := _stage_generation
	var car = session.world.driving.car
	var was_locked: bool = car.input_locked
	car.input_locked = true
	await session.door_transition.fade_to(1.0,FADE_OUT)
	if generation != _stage_generation or not staging: return
	# O carro vai para a vaga dele antes de qualquer rival nascer (era ele que ocupava a vaga deles).
	if is_instance_valid(car) and session.world.driving.car == car:
		_stop_car(car)
		var pose := course.grid(6)
		if session.world.production.vehicle_position_clear(car,pose.origin,pose.basis.get_euler().y): car.place(pose.origin,pose.basis.get_euler().y)
		_stop_car(car)
		car.reset_physics_interpolation()
	session.world.production.clear_ambient_traffic_near(_grid_points(),6.0)
	for i in 3: await get_tree().physics_frame
	if generation != _stage_generation or not staging: return
	var reason := start_block_reason()
	# _start guarda a trava de antes da cortina para devolver no fim da prova.
	if is_instance_valid(car): car.input_locked = was_locked
	var started := reason.is_empty() and _start()
	staging = false
	if not reason.is_empty(): session.show_message(reason)
	if not started:
		if is_instance_valid(car): car.input_locked = was_locked
		await session.door_transition.fade_to(0.0,FADE_IN)
		return
	# Contagem parada até a tela clarear; câmera já assentada no grid.
	set_physics_process(false)
	for entry in racers:
		if is_instance_valid(entry.car): entry.car.reset_physics_interpolation()
	for i in 6: await get_tree().process_frame
	await session.door_transition.fade_to(0.0,FADE_IN)
	if generation != _stage_generation or not active: return
	set_physics_process(true)

func _stop_car(car) -> void:
	car.speed = 0.0
	car.velocity = Vector3.ZERO
	car.horizontal_velocity = Vector3.ZERO
	car.throttle_input = 0.0
	car.steer_input = 0.0

func _grid_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in course.RACER_COUNT: points.append(course.grid(i).origin)
	return points

func is_night() -> bool:
	var time: float = session.weather.time_of_day if is_instance_valid(session.weather) else float(session.state.world_state.get("time",.32))
	return time >= 20.0/24.0 or time < 5.0/24.0

func start_block_reason() -> String:
	if active: return "A descida já começou."
	if session.controller.save_invalid: return "Save inválido preservado; atividade indisponível."
	if session.state.region_id != "mountain" or not session.state.place_id.is_empty(): return "Vá à largada na estrada da serra."
	if not is_night(): return "A descida acontece entre 20h e 5h."
	if session.world.gameplay.health<=0 or session.rescue_pending or session.arrest_pending: return "Aguarde a recuperação."
	if session.world.gameplay.stars>0: return "Despiste a polícia antes da largada."
	if not session.state.campaign.active_id.is_empty(): return "Conclua a missão atual antes de disputar a descida."
	var coordinator := get_tree().get_first_node_in_group("mountain_activities")
	if coordinator != null and not coordinator.can_start(self): return "Encerre a atividade atual antes da largada."
	var driving = session.world.driving
	if not driving.occupied or not is_instance_valid(driving.car): return "Entre em um veículo para correr."
	var car = driving.car
	if not eligible_car(car): return "Seu veículo não está em condições de correr."
	# Sob a cortina o carro é parado na vaga; só barra quem passa direto pela largada.
	if (car.input_locked and not staging) or car.external_input or absf(float(car.speed))>START_SPEED_LIMIT: return "Pare o carro na largada."
	if car.global_position.distance_to(course.start_position())>9.0: return "Aproxime o carro da largada."
	return ""

## Playtest 30/10: "tu pode correr com o que quiser". Antes só esportivos (lista de archetypes e
## limite de 1,4 × 3,0 m de meia-largura/meia-comprimento) largavam; agora qualquer veículo
## dirigível serve (moto, caminhão, jipe, lowrider, tanque). Fica só o que impede a prova de rodar:
## veículo vivo e com motor. Veículo grande demais para a grade cai no "largada ocupada" de _start().
static func eligible_car(car) -> bool:
	return is_instance_valid(car) and car.health>0 and not bool(car.get("engine_disabled"))

func _start() -> bool:
	player_car = session.world.driving.car
	_old_lock = player_car.input_locked
	var production = session.world.production
	var pose := course.grid(6)
	if not production.vehicle_position_clear(player_car,pose.origin,pose.basis.get_euler().y):
		session.show_message("A largada está ocupada. Libere o espaço e tente novamente.")
		return false
	# Primeiro o jogador vai para a vaga dele: parado a menos de 9 m da largada, o carro dele
	# ficava em cima da vaga de um rival e a largada era recusada. Falha devolve o carro aonde estava.
	var original: Transform3D = player_car.global_transform
	player_car.place(pose.origin,pose.basis.get_euler().y)
	_stop_car(player_car)
	production.clear_ambient_traffic_near(_grid_points(),6.0)
	for i in 6:
		var grid := course.grid(i)
		var car = null
		# Vaga cheia (dois carros largos lado a lado): tenta um pouco atrás, à frente e mais aberta.
		for slot in SLOT_FALLBACKS:
			grid = course.grid(i,slot.x,slot.y)
			car = production.spawn_vehicle(MODELS[i],grid.origin,grid.basis.get_euler().y)
			if car != null: break
		if car == null: return _abort_start(original,"A largada está ocupada. Libere o espaço e tente novamente.")
		car.set_meta("race_owned",true)
		car.set_meta("mountain_downhill_rival",true)
		car.vehicle_id = "mountain_downhill_rival_%d_%d"%[Time.get_ticks_usec(),i]
		car.paint_color = [Color("285575"),Color("ab422f"),Color("d6c259"),Color("777fa5"),Color("23382e"),Color("8d4148")][i]
		var pilot := PILOT.new()
		pilot.setup(car,course,i)
		pilot.tick(0,true,0)
		racers.append({"car":car,"index":i,"name":NAMES[i],"player":false,"pilot":pilot,"run":{}})
		if car.get_meta("awaiting_ground",false) or not production.vehicle_position_clear(car,grid.origin,grid.basis.get_euler().y):
			return _abort_start(original,"Aguarde o percurso carregar antes da largada.")
		var driver := preload("res://gameplay/CobraModel.gd").new()
		driver.tier = i%3
		driver.seated = true
		driver.cobra_uniform = i>=4
		var cabin: Dictionary = preload("res://gameplay/VehicleInterior.gd").spec(car)
		driver.position = Vector3(cabin.sx,cabin.floor,cabin.sz)
		car.add_child(driver)
		driver.fit_seat(car,cabin,true)
		car.set_meta("mountain_downhill_driver",driver)
		car.ensure_equipment(session.world)
	# Os seis rivais e a pose final do jogador precisam caber antes de mover/travar o Dante.
	if racers.size()!=6 or not production.vehicle_position_clear(player_car,pose.origin,pose.basis.get_euler().y):
		return _abort_start(original,"Não há espaço livre para os sete carros.")
	player_car.place(pose.origin,pose.basis.get_euler().y)
	player_car.speed = 0.0
	player_car.velocity = Vector3.ZERO
	player_car.horizontal_velocity = Vector3.ZERO
	player_car.input_locked = true
	var equipment = player_car.ensure_equipment(session.world)
	if is_instance_valid(equipment): equipment.headlights_on = true
	racers.append({"car":player_car,"index":6,"name":NAMES[6],"player":true,"pilot":null,"run":{}})
	_link_pilots()
	for entry in racers: entry.run = RUN.start(entry.car.vehicle_id,entry.car.global_position,course)
	countdown = course.COUNTDOWN
	active = true
	if OS.get_environment("GETECO_DOWNHILL_TRAFFIC_HOLD") != "0": production.set_traffic_hold(HOLD_ID,_hold_points(),HOLD_RADIUS)
	last_result = {}
	_ui_clock = 0
	_modal_motion.clear()
	_build_hud()
	set_physics_process(true)
	return true

func _abort_start(original: Transform3D, message: String) -> bool:
	_clear_rivals()
	if is_instance_valid(player_car):
		player_car.place(original.origin,original.basis.get_euler().y)
		_stop_car(player_car)
		player_car.input_locked = _old_lock
	session.show_message(message)
	return false

func _hold_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	var last := course.gate_offsets.size()-1
	var at: float = course.gate_offsets[clampi(HOLD_GATES.x,0,last)]-16.0
	var end: float = course.gate_offsets[clampi(HOLD_GATES.y,0,last)]+16.0
	while at <= end:
		points.append(course.point(at))
		at += 6.0
	return points

func _physics_process(delta: float) -> void:
	if not active: return
	var reason := _interruption()
	if not reason.is_empty(): cancel_attempt(reason); return
	if session.modal:
		_pause_for_menu()
		return
	_resume_from_menu()
	var hold := countdown>0.0
	countdown = maxf(0.0,countdown-delta)
	player_car.input_locked = _old_lock or hold
	_tick_countdown_cue()
	for entry in racers:
		var car = entry.car
		var alive: bool = is_instance_valid(car) and not car.is_queued_for_deletion() and car.health>0
		if not entry.player and alive:
			entry.pilot.tick(delta,hold or not str(entry.run.failure).is_empty(),int(entry.run.checkpoint))
			if not hold: _rescue_if_stuck(entry)
		RUN.tick(entry.run,delta,car.global_position if alive else Vector3.ZERO,str(car.vehicle_id) if alive else "",alive,hold,course)
	var player: Dictionary = racers[6]
	if not str(player.run.failure).is_empty(): cancel_attempt(str(player.run.failure)); return
	# Compute all seven crossings before ranking: finish fractions settle same-frame arrivals.
	if is_finite(float(player.run.finish)):
		_finish(standings().find(player)+1,float(player.run.finish))
		return
	_ui_clock -= delta
	if _ui_clock<=0.0:
		_ui_clock = .1
		_update_hud()

## Um bipe por número e um mais agudo no "VAI!", com o número grande no meio da tela.
func _tick_countdown_cue() -> void:
	var shown := ceili(countdown)
	if shown == _shown_count: return
	_shown_count = shown
	_cue(str(shown) if shown>0 else "go")
	if not is_instance_valid(banner): return
	banner.text = str(shown) if shown>0 else "VAI!"
	banner.modulate = Color(1,1,1,1) if shown>0 else Color("8ff0a4")
	banner.pivot_offset = banner.size*.5
	banner.scale = Vector2.ONE*1.35
	banner.visible = true
	var tween := banner.create_tween()
	tween.tween_property(banner,"scale",Vector2.ONE,.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if shown == 0:
		tween.tween_interval(.45)
		tween.tween_property(banner,"modulate:a",0.0,.35)
		tween.tween_callback(banner.hide)

func _cue(kind: String) -> void:
	played_cues.append(kind)
	var stream := CUES.activity("countdown")
	if stream == null or not is_instance_valid(_cue_voice): return
	_cue_voice.stream = stream
	_cue_voice.pitch_scale = 1.6 if kind == "go" else 1.0
	_cue_voice.play()

func _pause_for_menu() -> void:
	if _modal_motion.is_empty():
		for entry in racers:
			if not is_instance_valid(entry.car): continue
			var car = entry.car
			_modal_motion.append({"car":car,"speed":car.speed,"horizontal":car.horizontal_velocity,"velocity":car.velocity})
	# Mantém física e colisão ligadas para o ProductionWorld reter todo piso
	# sob os sete carros. Congela o movimento de direção e o timer juntos.
	for entry in racers:
		if not is_instance_valid(entry.car): continue
		var car = entry.car
		car.speed = 0.0
		car.horizontal_velocity = Vector3.ZERO
		car.velocity = Vector3.ZERO
		car.throttle_input = 0.0
		car.steer_input = 0.0
		car.brake_input = true
	player_car.input_locked = true

func _resume_from_menu() -> void:
	for motion in _modal_motion:
		if not is_instance_valid(motion.car) or motion.car.health<=0: continue
		motion.car.speed = motion.speed
		motion.car.horizontal_velocity = motion.horizontal
		motion.car.velocity = motion.velocity
	_modal_motion.clear()

func standings() -> Array[Dictionary]:
	var result: Array[Dictionary] = racers.duplicate()
	result.sort_custom(RUN.ahead)
	return result

func _interruption() -> String:
	if session.world.gameplay.health<=0 or session.rescue_pending: return "player_death"
	if session.arrest_pending: return "player_arrest"
	if not session.ready_for_play or session.is_transition_blocked(): return "world_transition"
	if session.state.region_id!="mountain" or not session.state.place_id.is_empty(): return "region_changed"
	if not is_instance_valid(player_car) or player_car.health<=0: return "race_vehicle_broken"
	if not session.world.driving.occupied or session.world.driving.car!=player_car: return "race_vehicle_left"
	return ""

func _finish(place: int, seconds: float) -> void:
	var recorded := PROGRESS.record_finish(session.state.world_state,place,seconds)
	var paid := recorded and PROGRESS.claim_reward(session.state.world_state,session.state.economy)
	last_result = {"place":place,"seconds":seconds,"paid":paid,"finished":true}
	_cleanup()
	session.show_message(String(TranslationServer.translate("Descida concluída · %d/7 · %.2f s")) %[place,seconds])
	session.save_game()

func cancel_attempt(reason: String = "cancelled") -> void:
	if staging:
		# Cortina no meio: nada foi montado ainda (ou _start já desfez); só clareia.
		staging = false
		_stage_generation += 1
		if is_instance_valid(session) and is_instance_valid(session.world.driving.car): session.world.driving.car.input_locked = false
		if is_instance_valid(session) and is_instance_valid(session.get("door_transition")): session.door_transition.fade_to(0.0,FADE_IN)
		return
	if not active: return
	last_result = {"finished":false,"reason":reason}
	_cleanup()
	if is_instance_valid(session) and reason in ["cancelled","race_vehicle_left","race_timeout","race_offtrack","race_interrupted","race_false_start"]:
		session.show_message("Descida interrompida. Volte à largada para tentar novamente.")

func _cleanup() -> void:
	active = false
	if is_instance_valid(session) and is_instance_valid(session.world) and is_instance_valid(session.world.production): session.world.production.clear_traffic_hold(HOLD_ID)
	set_physics_process(false)
	_modal_motion.clear()
	if is_instance_valid(player_car): player_car.input_locked = _old_lock or (is_instance_valid(session) and session.modal)
	_clear_rivals()
	if is_instance_valid(hud): hud.queue_free()
	if is_instance_valid(banner): banner.queue_free()
	if is_instance_valid(props):
		props.show_checkpoint(0,false)
		props.visible = false

## Rival engavetado volta para a pista (28/10, "ele só tem que chegar"): os carros são cinemáticos e um
## grampo com quatro carros encostados ficava parado até o fim da prova. Fora da vista da câmera basta
## RESCUE_HIDDEN s sem avançar; à vista, só depois de RESCUE_VISIBLE s. Nunca passa do próximo portão
## (a prova exige cruzar cada um) e o jogador nunca é movido.
const RESCUE_HIDDEN := 5.0
const RESCUE_VISIBLE := 15.0
static var rescue_enabled := OS.get_environment("GETECO_DOWNHILL_RESCUE") != "0"
var rescues := 0

func _rescue_if_stuck(entry: Dictionary) -> void:
	var pilot = entry.pilot
	if not rescue_enabled or float(pilot.stuck_time) < RESCUE_HIDDEN: return
	# Quem já chegou para depois da faixa: não é engavetamento.
	if is_finite(float(entry.run.finish)) or not str(entry.run.failure).is_empty(): return
	var car = entry.car
	var camera := get_viewport().get_camera_3d()
	var seen: bool = camera != null and camera.is_position_in_frustum(car.global_position) and camera.global_position.distance_to(car.global_position) < 90.0
	if seen and float(pilot.stuck_time) < RESCUE_VISIBLE: return
	var from: float = course.nearest_offset(car.global_position)
	var limit: float = float(course.length)-10.0
	var next := int(entry.run.checkpoint)
	if next < course.gate_offsets.size(): limit = minf(limit,float(course.gate_offsets[next])-3.0)
	for step in 6:
		var at := minf(from+float(step)*4.0,limit)
		var forward: Vector3 = course.direction(at)
		var right := forward.cross(Vector3.UP).normalized()
		var yaw := atan2(-forward.x,-forward.z)
		for lane in [1.8,-1.8]:
			var point: Vector3 = course.point(at)+right*lane+Vector3.UP*.08
			if not session.world.production.vehicle_position_clear(car,point,yaw): continue
			car.place(point,yaw)
			pilot.reset_after_rescue(lane)
			# A volta à pista não é "interrupção": o próximo quadro mede a partir daqui.
			entry.run.previous = car.global_position
			entry.run.outside = 0.0
			rescues += 1
			return
	# Sem vaga agora: tenta de novo daqui a pouco, sem gastar consulta todo quadro.
	pilot.stuck_time = RESCUE_HIDDEN-1.0

## Cada piloto enxerga os outros para ceder vaga a quem ficou diante de um carro contrário.
func _link_pilots() -> void:
	var pilots: Array = []
	for entry in racers:
		if entry.pilot != null: pilots.append(entry.pilot)
	for pilot in pilots: pilot.peers = pilots

func _clear_rivals() -> void:
	for entry in racers:
		if entry.player or not is_instance_valid(entry.car): continue
		var car = entry.car
		# Se o Dante pegar um carro rival, o cancelamento solta a posse dele em vez
		# de apagar o veículo ocupado debaixo do jogador.
		if is_instance_valid(session) and is_instance_valid(session.world) and is_instance_valid(session.world.driving) and session.world.driving.occupied and session.world.driving.car==car:
			car.remove_meta("race_owned")
			car.remove_meta("mountain_downhill_rival")
			car.set_external_driver(false)
			car.controlled = true
			car.player_damage_attribution = true
			var driver = car.get_meta("mountain_downhill_driver",null)
			if is_instance_valid(driver): driver.queue_free()
			car.remove_meta("mountain_downhill_driver")
		else:
			car.set_physics_process(false)
			car.queue_free()
	racers.clear()

func _process(delta: float) -> void:
	if not is_instance_valid(session): return
	_scene_clock -= delta
	if _scene_clock>0: return
	_scene_clock = .25
	var outdoors: bool = session.state.region_id=="mountain" and session.state.place_id.is_empty()
	if outdoors and not is_instance_valid(props):
		props = PROPS.new()
		session.world.add_child(props)
		props.build(course)
		props.show_checkpoint(0,active)
	if is_instance_valid(props): props.visible = outdoors and active

func _build_hud() -> void:
	hud = PanelContainer.new()
	hud.position = Vector2(855,105)
	hud.custom_minimum_size = Vector2(390,0)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.025,.045,.075,.92)
	style.border_color = Color("67c6ef")
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	hud.add_theme_stylebox_override("panel",style)
	session.world.hud.add_child(hud)
	var column := VBoxContainer.new()
	hud.add_child(column)
	status = Label.new()
	status.add_theme_font_size_override("font_size",16)
	column.add_child(status)
	board = Label.new()
	board.add_theme_font_size_override("font_size",16)
	column.add_child(board)
	banner = Label.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size",150)
	banner.add_theme_constant_override("outline_size",18)
	banner.add_theme_color_override("font_outline_color",Color(.02,.03,.05,.85))
	banner.visible = false
	session.world.hud.add_child(banner)
	_shown_count = 0
	_update_hud()

func _update_hud() -> void:
	if not is_instance_valid(status) or racers.size()!=7: return
	var place := standings().find(racers[6])+1
	var seconds := int(racers[6].run.elapsed)
	status.text = String(TranslationServer.translate("LARGADA · %d")) %ceili(countdown) if countdown>0 else "CHECKPOINT %d/%d · %d/7 · %02d:%02d"%[mini(int(racers[6].run.checkpoint)+1,course.gate_offsets.size()),course.gate_offsets.size(),place,floori(float(seconds)/60.0),seconds%60]
	var lines := PackedStringArray()
	var ordered := standings()
	for i in ordered.size():
		var entry: Dictionary = ordered[i]
		lines.append("%d  %s%s"%[i+1,entry.name," · CHEGOU" if is_finite(float(entry.run.finish)) else (" · FORA" if not str(entry.run.failure).is_empty() else "")])
	board.text = "\n".join(lines)
	if is_instance_valid(props): props.show_checkpoint(int(racers[6].run.checkpoint),true)

func _on_player_died() -> void: cancel_attempt("player_death")
func _on_player_arrested() -> void: cancel_attempt("player_arrest")

func _exit_tree() -> void:
	if active: _cleanup()
	if is_instance_valid(props): props.queue_free()
	if is_instance_valid(hud): hud.queue_free()
	if is_instance_valid(banner): banner.queue_free()
