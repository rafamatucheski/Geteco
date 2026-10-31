extends Node3D
## Ato 1 do roteiro de diretor (21/10/2026), cadeia paralela entre as missões principais de Harbor.
## Etapas e contrato do save em HelenaAct1State; falas em data/campaign/helena-act1-dialogue.json.
##   M02-B "Cobrança em dobro": Helena no caixa do North Pier -> Neco na baia -> três carros pelo guincho
##     do Neco (o mesmo de MissionWorld, com um serviço "chain:debt:N"), o último com Cobras chegando.
##   M04-B "O desmanche do Neco": Neco no pátio -> escolha: prensa (a prensa de sempre, que paga a sucata)
##     ou devolver o carro ao cliente do Maciota em Westgate.
##   M05-B "Posto de lavagem": Helena no cais -> cofre do posto dos Cobras (a loja "Fuel" do North
##     Frontage, que já existe: nenhum prédio novo) depois da meia-noite, com a Helena no telefone ->
##     fuga -> envelopes nas três portas de M02-B.
##   M06-B "O que a Helena guardou": Helena no cais -> à noite, North Pier só com o vigia da noite, sem
##     ser visto, gaveta da Helena (carimbo 0417) -> Helena na rua ao lado do banco.
##   "Carona" (opcional): Helena no ponto Cais / Serviços à noite; o carro para do lado e leva até o canal.
##   Despedida (fim de M07): Helena com a mala no cais ao amanhecer, depois da ligação do Maciota.
##   M00: TV do terminal com o noticiário do delegado Prado (só imagem e legenda da TV).
## Nada aqui avança enquanto uma missão principal está ativa: as duas cadeias nunca disputam o mesmo
## objetivo. Atores e adereços são montados só perto (uma vez) e devolvidos ao se afastar.
const STATE := preload("res://systems/campaign/HelenaAct1State.gd")
const LINES := preload("res://systems/campaign/HelenaAct1Lines.gd")
const HELENA := preload("res://runtime/harbor_act1/HelenaCharacter.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const PART := preload("res://assets/regions/source/characters/pedestrians/CitizenDetails.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const UNIT := 1.0 / 16.0
## Cais do porto: o ponto da encomenda de M01 (MissionWorld.targets.harbor_parcel), chão de pedestre.
const DOCK := Vector3(3515, 0, 1450) * UNIT
const DOCK_POINTS := [Vector3(2.2, 0, 1.6), Vector3(-2.2, 0, 1.6), Vector3(0, 0, 3.0), Vector3(2.6, 0, -1.6)]
## Ponto de ônibus "Cais / Serviços" (UrbanTransitPresentation.STOPS[4]); abrigo calculado como lá.
const STOP_INDEX := 4
const STOP_FALLBACK := Vector3(3090, 0, 830) * UNIT
const STOP_POINTS := [Vector3(-2.4, 0, 0), Vector3(2.4, 0, 0), Vector3(0, 0, 2.6), Vector3(0, 0, -2.6), Vector3(-3.2, 0, 2.0)]
const BANK_SIDE_POINTS := [Vector3(6.5, 0, 1.5), Vector3(-6.5, 0, 1.5), Vector3(6.5, 0, 3.5), Vector3(-6.5, 0, 3.5)]
## Calçada perto da porta da dona Cida (último carro de M02-B), onde Helena assiste de longe.
const CIDA_POINTS := [Vector3(7, 0, 6.5), Vector3(-7, 0, 6.5), Vector3(7, 0, -6.5), Vector3(-7, 0, -6.5)]
const RIDE_DROP_PLACE := "canal_north"
## Cliente do Maciota em Westgate: a pista da westgate_drive, 8 m ao norte do ponto Westgate / Hospital.
const PRESS_CLIENT := Vector3(400, 0, 1600) * UNIT
const PRESS_CAR_ID := "act1_scraped_car"
const PRESS_CAR_MODEL := "union_sedan"
## Interior "harbor_fuel" (FuelStoreArt3D, 14 x 10 m): parede do fundo, entre as geladeiras (x até -1,65)
## e o balcão (x a partir de 2,9). Lugar livre de sólido e de prateleira.
const FUEL_SAFE := Vector3(1.6, 0, -4.55)
const FUEL_SAFE_REACH := 1.6
const SAFE_SECONDS := 3.0
const WASH_SECONDS := 120.0
## Interior do North Pier: o caixa da Helena (Robberies.helena_position).
const BANK_DRAWER := Vector3(-2.65, 0, -1.9)
const BANK_DRAWER_REACH := 1.8
## O vigia da noite (Robberies, guarda 1) olha num cone; meio segundo visto dispara o alarme.
const GUARD_RANGE := 8.0
const GUARD_COS := .77
const GUARD_SWEEP := .55
const SEEN_SECONDS := .5
## TV do terminal (M00): no piso do cais (PortLifeSolids começa em z 192; antes disso é a passarela do
## barco e água), 3 m a leste do caminho do desembarque (HarborPassengerTerminal.ARRIVAL até
## Arrival.ARRIVAL), virada para quem desce do barco.
const TV_POINT := Vector3(236.0, 0, 193.0)
const SPAWN_DISTANCE := 60.0
const RELEASE_DISTANCE := 80.0
const TALK_DISTANCE := 2.0
const ENVELOPE_REACH := 5.0
const RIDE_LINE_SECONDS := 4.6
const COBRA_AGENT := preload("res://gameplay/CobraAgent.gd")

var session
var helena: CharacterBody3D
var _helena_scene := ""
var _clock := 0.0
var _retry := 0.0
## Missão escolhida no diário (J): mostra objetivo e marcador de uma missão que ainda não começou.
var _focus := ""
## M02-B: Cobras do terceiro carro e Helena olhando de longe depois da entrega.
var _cobras: Array = []
var _cobras_called := false
var _watch_clock := 0.0
## M04-B: o carro raspado (montado de novo depois de carregar).
var press_car: CharacterBody3D
## M05-B: relógio do gerente, cofre e fuga.
var _heist_running := false
var _heist_left := 0.0
var _heist_spent := false
var _safe_left := 0.0
var _safe_prop: Node3D
var _escape_clock := 0.0
var _police_called := false
var _envelopes := 0
## M06-B: vigia da noite.
var _seen := 0.0
var _caught := false
var _sweep := 0.0
## Carona.
var _riding := false
var _ride_car: Node3D
var _ride_line := 0
var _ride_clock := 0.0
## M00.
var _tv: Node3D
## Snapshot da campanha e missão da cadeia em foco, renovados a cada tique (0,15 s): o marcador e o
## objetivo perguntam a cada quadro, e o snapshot é uma cópia.
var _campaign_cache: Dictionary = {}
var _active_cache := ""

func configure(owner_session) -> void:
	session = owner_session
	name = "HelenaAct1"
	if session.mission_world != null and session.mission_world.has_signal("tow_event"):
		session.mission_world.tow_event.connect(_on_tow_event)

# --- Estado ----------------------------------------------------------------------------------------

func _world() -> Dictionary:
	return session.state.world_state

func _campaign() -> Dictionary:
	if _campaign_cache.is_empty(): _refresh()
	return _campaign_cache

func _refresh() -> void:
	_campaign_cache = session.state.campaign.snapshot()
	_active_cache = active_id()

func stage(id: String) -> String:
	return STATE.stage(_world(), id)

func _ready_for(id: String, campaign: Dictionary) -> bool:
	return STATE.ready(_world(), campaign, id)

func hour() -> float:
	return float(session.weather.time_of_day) * 24.0 if session.weather != null else 12.0

func _night() -> bool:
	var h := hour()
	return h >= 22.0 or h < 5.0

func _late_night() -> bool:
	return hour() < 5.0

func _evening() -> bool:
	var h := hour()
	return h >= 20.0 or h < 5.0

func _dawn() -> bool:
	var h := hour()
	return h >= 5.0 and h < 9.0

func _idle() -> bool:
	return session.state.campaign.active_id.is_empty() and session.state.intro.stage == "complete"

func _outside() -> bool:
	return session.state.region_id == "harbor" and session.state.place_id.is_empty()

func _free_on_foot() -> bool:
	return session.ready_for_play and not session.modal and not session.world.driving.occupied and session.world.gameplay.health > 0 and not session.is_transition_blocked()

## Missão da cadeia em andamento (etapa aberta), a escolhida no diário, ou a despedida quando chega a hora.
func active_id() -> String:
	if not _idle(): return ""
	var campaign := _campaign()
	for id in STATE.ORDER:
		var current := stage(id)
		if current != "" and current != "done" and _ready_for(id, campaign): return id
	if _riding: return "ride"
	if not _focus.is_empty() and _ready_for(_focus, campaign) and stage(_focus) == "": return _focus
	if _ready_for("farewell", campaign) and stage("farewell") == "": return "farewell"
	return ""

func focus(id: String) -> void:
	_focus = id
	_refresh()

## Entradas do diário: uma por missão disponível e ainda não concluída.
func journal_entries() -> Array:
	var result: Array = []
	if session == null: return result
	_refresh()
	var campaign := _campaign()
	for id in STATE.ORDER:
		if not _ready_for(id, campaign) or STATE.complete(_world(), id): continue
		var text := STATE.objective_for(_world(), id)
		if text.is_empty(): continue
		result.append({"id": id, "text": String(TranslationServer.translate(str(STATE.CHAIN[id].title))) + " · " + String(TranslationServer.translate(text))})
	return result

func objective() -> String:
	var id := _active_cache
	if id.is_empty() or not _idle(): return ""
	if id == "ride" and _riding: return "Leve a Helena até o Canal North."
	if id == "debt" and STATE.debt_tow_index(_world()) >= 0 and _tow_blocked(): return "Termine o serviço de guincho atual antes de pegar o carro de volta."
	if id == "wash" and stage("wash") == "envelopes": return "Deixe os envelopes nas portas de quem pagou em dobro (%d/3)." % _envelope_count()
	if id == "folder" and stage("folder") == "night" and _caught: return "O vigia te viu. Saia do banco e volte outra noite."
	if id == "wash" and stage("wash") == "station" and _heist_running: return String(TranslationServer.translate("Arrombe o cofre antes de o gerente voltar · %d s")) % ceili(maxf(0.0, _heist_left))
	return STATE.objective_for(_world(), id)

func target_position() -> Vector3:
	var id := _active_cache if _idle() else ""
	var current := stage(id) if not id.is_empty() else ""
	match id:
		"debt":
			match current:
				"": return _bank_entry()
				"neco": return session.mission_world.targets.neco
				_:
					var index := STATE.debt_tow_index(_world())
					if index < 0: return Vector3.INF
					var mw = session.mission_world
					if _chain_job_index() == index and mw.loaded: return STATE.DEBT_CARS[index].drop
					if _chain_job_index() == index and is_instance_valid(mw.cargo): return mw.cargo.global_position
					return STATE.DEBT_CARS[index].pickup
		"press":
			match current:
				"": return session.mission_world.targets.neco
				"press": return session.mission_world.targets.neco_bay
				"return": return press_car.global_position if is_instance_valid(press_car) and not _in_press_car() else PRESS_CLIENT
		"wash":
			match current:
				"": return _helena_or(DOCK)
				"station": return PLACES.get_definition("harbor_fuel").entry_position
				"envelopes":
					for i in 3:
						if not _envelopes & (1 << i): return STATE.DEBT_CARS[i].drop
		"folder":
			match current:
				"": return _helena_or(DOCK)
				"night": return _bank_entry()
				"handoff": return _helena_or(_bank_entry())
		"ride":
			if _riding: return PLACES.get_definition(RIDE_DROP_PLACE).entry_position
			return _helena_or(_stop_origin())
		"farewell": return _helena_or(DOCK)
	return Vector3.INF

## Alvo dentro de um interior (o marcador do FullSession troca a saída por ele).
func indoor_target() -> Vector3:
	if session == null or not is_instance_valid(session.room) or not _idle(): return Vector3.INF
	var place: String = session.state.place_id
	if place == "harbor_bank":
		if stage("debt") == "" and _active_cache == "debt": return session.robberies.helena_position()
		if stage("folder") == "night" and bank_night_shift() and not _caught: return session.room.to_global(BANK_DRAWER)
	if place == "harbor_fuel" and stage("wash") == "station" and _heist_running: return session.room.to_global(FUEL_SAFE)
	return Vector3.INF

func _helena_or(point: Vector3) -> Vector3:
	return helena.global_position if is_instance_valid(helena) else point

func _bank_entry() -> Vector3:
	return PLACES.get_definition("harbor_bank").entry_position

func _stop_origin() -> Vector3:
	var transit = session.controller.get("urban_transit") if session.controller != null else null
	if transit != null and STOP_INDEX < transit.definitions.size(): return transit.definitions[STOP_INDEX].position
	return STOP_FALLBACK

# --- Ganchos dos sistemas que já existem -----------------------------------------------------------

## Robberies: de noite, durante M06-B, o North Pier fica só com o vigia da noite (guarda 1), sem caixas.
func bank_night_shift() -> bool:
	return session != null and _idle() and stage("folder") == "night" and _night()

## Robberies: na noite do assalto de M05-B o posto está fechado e o gerente saiu.
func fuel_closed() -> bool:
	return session != null and _idle() and stage("wash") == "station" and _late_night()

## GarageRewards: o carro raspado acabou de virar sucata na prensa (a prensa já pagou o Neco-preço).
func on_scrapped(car) -> void:
	if car != press_car and str(car.vehicle_id) != PRESS_CAR_ID: return
	press_car = null
	if stage("press") != "press": return
	if STATE.finish(_world(), session.state.campaign.snapshot(), session.state.economy, "press").ok:
		_refresh()
		session.show_message(String(TranslationServer.translate("Missão concluída: %s")) % String(TranslationServer.translate(str(STATE.CHAIN.press.title))))

# --- Interação -------------------------------------------------------------------------------------

func nearest_action() -> Dictionary:
	if session == null or not _idle() or session.state.region_id != "harbor" or not _free_on_foot(): return {}
	var player: Vector3 = session.world.player.global_position
	var campaign := _campaign()
	if not session.state.place_id.is_empty(): return _indoor_action(player, campaign)
	if is_instance_valid(helena) and player.distance_to(helena.global_position) <= TALK_DISTANCE and _helena_scene in ["dock", "bank_side"]:
		return _action("helena:" + _helena_scene, "Conversar com Helena")
	var neco: Vector3 = session.mission_world.targets.neco
	if player.distance_to(neco) < 2.3:
		if stage("debt") == "neco": return _action("neco:debt", "Conversar com Neco")
		if stage("press") == "" and _ready_for("press", campaign): return _action("neco:press", "Conversar com Neco")
	if stage("wash") == "envelopes":
		for i in 3:
			if not _envelopes & (1 << i) and player.distance_to(STATE.DEBT_CARS[i].drop) <= ENVELOPE_REACH:
				return _action("envelope:%d" % i, "Deixar envelope")
	return {}

func _indoor_action(player: Vector3, campaign: Dictionary) -> Dictionary:
	if not is_instance_valid(session.room): return {}
	match str(session.state.place_id):
		"harbor_bank":
			if stage("debt") == "" and _ready_for("debt", campaign) and not session.robberies.bank_unavailable() and player.distance_to(session.robberies.helena_position()) < 1.6:
				return _action("bank_helena", "Conversar com Helena")
			if stage("folder") == "night" and bank_night_shift() and not _caught and not session.robberies.data.bank_alarm and player.distance_to(session.room.to_global(BANK_DRAWER)) < BANK_DRAWER_REACH:
				return _action("bank_drawer", "Abrir a gaveta da Helena")
		"harbor_fuel":
			if stage("wash") == "station" and _heist_running and _safe_left <= 0 and player.distance_to(session.room.to_global(FUEL_SAFE)) < FUEL_SAFE_REACH:
				return _action("fuel_safe", "Arrombar o cofre")
	return {}

func nearest_vehicle_action() -> Dictionary:
	if session == null or not _idle() or not _outside() or _riding or not is_instance_valid(helena) or _helena_scene != "stop": return {}
	var car = session.world.driving.car
	if not session.world.driving.occupied or not is_instance_valid(car) or car.health <= 0 or str(car.archetype).begins_with("bike_"): return {}
	if car.global_position.distance_to(helena.global_position) > 9.0 or car.horizontal_velocity.length() > 1.5: return {}
	return _action("ride_offer", "Oferecer carona")

func _action(target: String, label: String) -> Dictionary:
	return {"id": "helena_act1", "target": target, "label": label}

func perform(action: Dictionary) -> bool:
	var target := str(action.get("target", ""))
	if target.is_empty(): return false
	var expected: Dictionary = nearest_vehicle_action() if session.world.driving.occupied else nearest_action()
	if expected.get("target", "") != target: return false
	if target.begins_with("helena:"): return _talk_helena(target.trim_prefix("helena:"))
	if target.begins_with("envelope:"): return _drop_envelope(int(target.trim_prefix("envelope:")))
	match target:
		"neco:debt":
			_say("debt_neco", func(): _advance("debt", "tow1"); _start_debt_tow())
			return true
		"neco:press":
			_say("press_yard", _press_choice)
			return true
		"bank_helena":
			_say("debt_bank", func(): _advance("debt", "neco"))
			return true
		"bank_drawer": return _take_folder()
		"fuel_safe":
			_safe_left = SAFE_SECONDS
			_speak("wash_drawer")
			return true
		"ride_offer": return _start_ride()
	return false

func _talk_helena(scene: String) -> bool:
	if is_instance_valid(helena):
		helena.face(session.world.player.global_position)
		helena.set_talking(true)
	match scene:
		"dock":
			if stage("wash") == "" and _ready_for("wash", _campaign()):
				_say("wash_dock", func(): _advance("wash", "station"))
				return true
			if stage("folder") == "" and _ready_for("folder", _campaign()):
				_say("folder_dock", func(): _advance("folder", "night"))
				return true
			if stage("farewell") == "" and _ready_for("farewell", _campaign()):
				_say("farewell", func(): _finish("farewell"); _release_helena())
				return true
		"bank_side":
			if stage("folder") == "handoff":
				_say("folder_handoff", func(): _finish("folder"); _release_helena())
				return true
	return false

func _say(section: String, on_done := Callable()) -> void:
	session.show_dialogue(LINES.lines(section), func():
		if is_instance_valid(helena): helena.set_talking(false)
		if on_done.is_valid() and session.world.gameplay.health > 0: on_done.call())

## Fala curta sem parar o jogo (telefone, rádio, carona).
func _speak(section: String, index := 0) -> void:
	var rows := LINES.lines(section)
	if index < 0 or index >= rows.size(): return
	session.show_speech(str(rows[index].speaker), str(rows[index].message), RIDE_LINE_SECONDS, false)

func _advance(id: String, to_stage: String) -> bool:
	if not STATE.advance(_world(), session.state.campaign.snapshot(), id, to_stage): return false
	if _focus == id: _focus = ""
	_refresh()
	session.save_game()
	return true

func _finish(id: String) -> bool:
	var result: Dictionary = STATE.finish(_world(), session.state.campaign.snapshot(), session.state.economy, id)
	if not result.ok:
		if str(result.get("reason", "")) == "wallet_full": session.show_message("Carteira cheia. Gaste um pouco e volte para concluir.")
		return false
	if _focus == id: _focus = ""
	_refresh()
	var title := String(TranslationServer.translate(str(STATE.CHAIN[id].title)))
	if int(result.amount) > 0:
		preload("res://gameplay/RewardAudio.gd").play(self, "cash")
		session.show_message(String(TranslationServer.translate("Missão concluída: %s")) % title)
	elif id != "ride" and id != "farewell":
		session.show_message(String(TranslationServer.translate("Missão concluída: %s")) % title)
	session.save_game()
	return true

# --- M02-B: guincho ----------------------------------------------------------------------------------

func _chain_job_index() -> int:
	var job: Dictionary = session.mission_world.tow_job
	if job.get("chain") != "debt": return -1
	return int(job.get("index", -1))

func _tow_blocked() -> bool:
	var job: Dictionary = session.mission_world.tow_job
	return not job.is_empty() and job.get("chain") != "debt"

func _start_debt_tow() -> void:
	var index := STATE.debt_tow_index(_world())
	if index < 0 or not _outside() or not _idle(): return
	if _chain_job_index() == index or not session.mission_world.tow_job.is_empty(): return
	if session.mission_world.begin_tow_job({"chain": "debt", "index": index}): session.save_game()

func _on_tow_event(kind: String) -> void:
	if kind != "unloaded" or not _idle(): return
	var index := STATE.debt_tow_index(_world())
	if index < 0 or _chain_job_index() != index or not session.mission_world.can_finish_tow_job(): return
	if not session.mission_world.finish_tow_job(): return
	if index < 2:
		_advance("debt", "tow%d" % (index + 2))
		_start_debt_tow()
		return
	_release_cobras()
	_watch_clock = 14.0
	_finish("debt")

func _update_cobras() -> void:
	if stage("debt") != "tow3" or not _outside():
		_release_cobras()
		return
	var pickup: Vector3 = STATE.DEBT_CARS[2].pickup
	var player: Vector3 = session.world.player.global_position
	if player.distance_to(pickup) > 160.0:
		_release_cobras()
		_cobras_called = false
		return
	if not _cobras.is_empty() or _cobras_called or session.mission_world.loaded or player.distance_to(pickup) > 45.0: return
	_cobras_called = true
	var began := STALL_WORK.begin()
	for offset in [Vector3(-7, 0, -6), Vector3(7, 0, -6)]:
		var point: Vector3 = pickup + offset
		if not session.position_clear(point + Vector3.UP * .05): continue
		var enemy = COBRA_AGENT.new()
		enemy.configure(session.world.gameplay, 0)
		enemy.position = point + Vector3.UP * .05
		add_child(enemy)
		_cobras.append(enemy)
	STALL_WORK.finish_slow("harbor_act1.cobras", began, 2000)
	if not _cobras.is_empty(): _speak("debt_cobras")

func _release_cobras() -> void:
	for enemy in _cobras:
		if not is_instance_valid(enemy): continue
		enemy.set_process(false)
		enemy.set_physics_process(false)
		enemy.collision_layer = 0
		enemy.collision_mask = 0
		enemy.queue_free()
	_cobras.clear()
	if stage("debt") != "tow3": _cobras_called = false

# --- M04-B: prensa ou devolver ----------------------------------------------------------------------

func _press_choice() -> void:
	session._menu("O carro raspado")
	session._button("Mandar para a prensa", func():
		session.close_menu()
		if _advance("press", "press"): _speak("press_chose_press"))
	session._button("Devolver ao cliente do Maciota", func():
		session.close_menu()
		if _advance("press", "return"): _speak("press_chose_return"))

func _in_press_car() -> bool:
	return session.world.driving.occupied and session.world.driving.car == press_car

func _update_press_car() -> void:
	var current := stage("press")
	if current not in ["press", "return"] or session.state.region_id != "harbor":
		return
	if is_instance_valid(press_car) and not press_car.is_queued_for_deletion():
		if press_car.health <= 0 and not press_car.controlled and session.world.player.global_position.distance_to(press_car.global_position) > 80.0:
			# Carcaça queimada longe do jogador: um carro novo volta para a baia.
			press_car.vehicle_id = "wrecked_" + PRESS_CAR_ID
			press_car = null
			return
		if current == "return" and press_car.health > 0 and not _in_press_car() and press_car.global_position.distance_to(PRESS_CLIENT) < 10.0 and press_car.horizontal_velocity.length() < .3:
			_finish_return()
		return
	press_car = null
	var bay: Vector3 = session.mission_world.targets.neco_bay
	if not session.state.place_id.is_empty() or session.world.player.global_position.distance_to(bay) > 70.0: return
	var began := STALL_WORK.begin()
	var car = session.controller.spawn_vehicle(PRESS_CAR_MODEL, bay + Vector3.UP * .12, PI)
	STALL_WORK.finish_slow("harbor_act1.press_car", began, 2000)
	if car == null: return
	if car.has_meta("awaiting_ground"):
		# Chão ainda não carregado ou baia ocupada: descarta só este carro novo e tenta depois.
		car.collision_layer = 0
		car.collision_mask = 0
		session.controller.vehicles.erase(car)
		car.queue_free()
		return
	car.vehicle_id = PRESS_CAR_ID
	car.set_meta("region_id", "harbor")
	car.paint_color = Color("5b6b74")
	# Na devolução a prensa recusa o carro (GarageRewards.PROTECTED_META): prensar de novo pagaria a
	# sucata outra vez a cada carro remontado.
	if current == "return": car.set_meta("garage_reward", true)
	press_car = car

func _finish_return() -> void:
	if not _finish("press"): return
	press_car.vehicle_id = "returned_" + PRESS_CAR_ID
	press_car = null

# --- M05-B: posto de lavagem -------------------------------------------------------------------------

func _update_heist(delta: float) -> void:
	var current := stage("wash")
	if current == "station":
		var inside: bool = session.state.place_id == "harbor_fuel" and is_instance_valid(session.room) and session.world.gameplay.health > 0
		if not inside:
			_heist_running = false
			_heist_spent = false
			_safe_left = 0.0
			_free_safe()
			return
		if not _heist_running and not _heist_spent and _late_night() and _idle():
			_heist_running = true
			_heist_left = WASH_SECONDS
			_build_safe()
			_speak("wash_manager")
		if not _heist_running: return
		_heist_left -= delta
		if _safe_left > 0:
			if session.world.player.global_position.distance_to(session.room.to_global(FUEL_SAFE)) > FUEL_SAFE_REACH + .4:
				_safe_left = 0.0
				session.show_message("Fique junto do cofre para arrombar.")
			else:
				_safe_left -= delta
				if _safe_left <= 0: _open_safe()
				return
		if _heist_left <= 0:
			_heist_running = false
			_heist_spent = true
			_speak("wash_late")
			session.world.gameplay.register_crime(15, PLACES.get_definition("harbor_fuel").entry_position)
		return
	if current == "escape":
		if not _outside() or session.world.gameplay.health <= 0: return
		var stars: int = session.world.gameplay.stars
		_escape_clock += delta
		if stars > 0 and not _police_called and _escape_clock > 3.0:
			_police_called = true
			_speak("wash_police")
		if stars == 0 and _escape_clock > 1.0:
			_speak("wash_clear")
			_envelopes = 0
			_advance("wash", "envelopes")

func _open_safe() -> void:
	_heist_running = false
	_heist_spent = true
	_free_safe()
	session.world.gameplay.register_crime(25, PLACES.get_definition("harbor_fuel").entry_position)
	preload("res://gameplay/RewardAudio.gd").play(self, "pickup")
	session.show_message("Envelopes do cofre dos Cobras recolhidos. Saia e despiste a polícia.")
	_escape_clock = 0.0
	_police_called = false
	_advance("wash", "escape")

func _build_safe() -> void:
	_free_safe()
	if not is_instance_valid(session.room): return
	_safe_prop = Node3D.new()
	_safe_prop.name = "CobraSafe"
	_safe_prop.position = FUEL_SAFE
	session.room.add_child(_safe_prop)
	PART.piece(_safe_prop, Vector3(.72, .82, .56), Vector3(0, .41, 0), Color("3c4146"))
	PART.piece(_safe_prop, Vector3(.6, .66, .02), Vector3(0, .43, .29), Color("4c535a"))
	PART.piece(_safe_prop, Vector3(.12, .12, .03), Vector3(.12, .48, .31), Color("b9a35e"))

func _free_safe() -> void:
	if is_instance_valid(_safe_prop): _safe_prop.queue_free()
	_safe_prop = null

func _envelope_count() -> int:
	return int(bool(_envelopes & 1)) + int(bool(_envelopes & 2)) + int(bool(_envelopes & 4))

func _drop_envelope(index: int) -> bool:
	if index < 0 or index > 2 or _envelopes & (1 << index): return false
	_envelopes |= 1 << index
	preload("res://gameplay/RewardAudio.gd").play(self, "pickup")
	session.show_message(String(TranslationServer.translate("Envelope na porta de %s. Sem assinatura.")) % str(STATE.DEBT_CARS[index].owner))
	if _envelopes == 7: _finish("wash")
	return true

# --- M06-B: a pasta ----------------------------------------------------------------------------------

func _update_folder(delta: float) -> void:
	if session.state.place_id != "harbor_bank":
		_caught = false
		_seen = 0.0
		return
	if not bank_night_shift() or _caught or not is_instance_valid(session.room): return
	var guard = _night_guard()
	if guard == null: return
	var player: Node3D = session.world.player
	var armed: bool = session.state.equipped_weapon not in ["", "fists"]
	if not armed and not session.robberies.data.bank_shots:
		# Ronda parada: o vigia vira a cabeça entre o cofre e a porta.
		_sweep += delta * GUARD_SWEEP
		guard.visual.rotation.y = PI * .5 + sin(_sweep) * 1.25
	var facing: Vector3 = -guard.visual.global_basis.z
	facing.y = 0
	var offset: Vector3 = player.global_position - guard.global_position
	offset.y = 0
	var visible := offset.length() < GUARD_RANGE and facing.normalized().dot(offset.normalized()) > GUARD_COS
	if visible:
		var ray := PhysicsRayQueryParameters3D.create(guard.global_position + Vector3.UP * 1.6, player.global_position + Vector3.UP * 1.5, 1, [guard.get_rid(), player.get_rid()])
		visible = get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
	_seen = _seen + delta if visible else maxf(0.0, _seen - delta)
	if _seen < SEEN_SECONDS and not session.robberies.data.bank_alarm: return
	_caught = true
	if not session.robberies.data.bank_alarm: session.robberies._start_alarm(true)
	_speak("folder_seen")

func _night_guard():
	for actor in session.robberies._actors:
		if is_instance_valid(actor) and actor.guard and not actor.dead and is_instance_valid(actor.visual): return actor
	return null

func _take_folder() -> bool:
	if _caught or session.robberies.data.bank_alarm: return false
	session.show_dialogue([{"speaker": String(TranslationServer.translate("Pasta da Helena")), "message": String(TranslationServer.translate("Na cópia, o carimbo de conferência: 0417."))}], func():
		_advance("folder", "handoff"))
	return true

# --- Carona ------------------------------------------------------------------------------------------

func _start_ride() -> bool:
	_riding = true
	_ride_car = session.world.driving.car
	_ride_line = 0
	_ride_clock = 0.0
	_release_helena()
	_speak("ride", 0)
	return true

func _update_ride(delta: float) -> void:
	if not _riding: return
	var car = session.world.driving.car
	if not session.world.driving.occupied or car != _ride_car or not is_instance_valid(car) or car.health <= 0 or session.world.gameplay.stars > 0 or session.state.region_id != "harbor" or not _idle():
		_riding = false
		_ride_car = null
		_speak("ride_abort")
		return
	_ride_clock += delta
	var rows := LINES.lines("ride")
	if _ride_clock >= RIDE_LINE_SECONDS and _ride_line + 1 < rows.size():
		_ride_clock = 0.0
		_ride_line += 1
		_speak("ride", _ride_line)
	var drop: Vector3 = PLACES.get_definition(RIDE_DROP_PLACE).entry_position
	if car.global_position.distance_to(drop) < 14.0 and car.horizontal_velocity.length() < 1.0:
		_riding = false
		_ride_car = null
		_speak("ride_drop")
		_finish("ride")

# --- Helena em cena ----------------------------------------------------------------------------------

## Onde a Helena espera agora: {scene, points (mundo), suitcase} ou vazio.
func scene_def() -> Dictionary:
	if not _idle() or _riding: return {}
	var campaign := _campaign()
	if stage("debt") == "tow3" or _watch_clock > 0:
		var drop: Vector3 = STATE.DEBT_CARS[2].drop
		return {"scene": "cida", "points": _offset_points(drop, CIDA_POINTS), "suitcase": false}
	if stage("folder") == "handoff":
		return {"scene": "bank_side", "points": _offset_points(_bank_entry(), BANK_SIDE_POINTS), "suitcase": false}
	if (stage("wash") == "" and _ready_for("wash", campaign)) or (stage("folder") == "" and _ready_for("folder", campaign)):
		return {"scene": "dock", "points": _offset_points(DOCK, DOCK_POINTS), "suitcase": false}
	if stage("farewell") == "" and _ready_for("farewell", campaign) and _dawn():
		return {"scene": "dock", "points": _offset_points(DOCK, DOCK_POINTS), "suitcase": true}
	if stage("ride") == "" and _ready_for("ride", campaign) and _evening():
		return {"scene": "stop", "points": _offset_points(_stop_origin(), STOP_POINTS), "suitcase": false}
	return {}

func _offset_points(origin: Vector3, offsets: Array) -> Array:
	var result: Array = []
	for offset in offsets: result.append(origin + offset)
	return result

func _update_helena() -> void:
	var def := scene_def() if _outside() else {}
	var scene := str(def.get("scene", ""))
	var player: Vector3 = session.world.player.global_position
	if is_instance_valid(helena):
		if scene != _helena_scene or player.distance_to(helena.global_position) > RELEASE_DISTANCE:
			_release_helena()
		else:
			if _helena_scene == "cida" and stage("debt") == "done" and _watch_clock <= 0: _release_helena()
			elif not session.modal: helena.face(player)
			return
	if scene.is_empty() or player.distance_to(def.points[0]) > SPAWN_DISTANCE: return
	var space := get_world_3d().direct_space_state
	for guess: Vector3 in def.points:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(guess + Vector3.UP * 3.0, guess - Vector3.UP * 2.0, 1))
		if hit.is_empty() or float(hit.normal.y) < .9: continue
		var point: Vector3 = hit.position + Vector3.UP * .05
		if not session.position_clear(point): continue
		var began := STALL_WORK.begin()
		helena = HELENA.new()
		helena.with_suitcase = bool(def.suitcase)
		helena.position = point
		add_child(helena)
		STALL_WORK.finish_slow("harbor_act1.helena", began, 2000)
		_helena_scene = scene
		helena.face(player)
		return

func _release_helena() -> void:
	if is_instance_valid(helena):
		helena.hide()
		helena.collision_layer = 0
		helena.queue_free()
	helena = null
	_helena_scene = ""

# --- M00: TV do terminal -----------------------------------------------------------------------------

func _update_tv() -> void:
	var near: bool = session.state.region_id == "harbor" and session.state.place_id.is_empty() and session.world.player.global_position.distance_to(TV_POINT) < 90.0
	if not near:
		if is_instance_valid(_tv) and session.world.player.global_position.distance_to(TV_POINT) > 130.0:
			_tv.queue_free()
			_tv = null
		return
	if is_instance_valid(_tv): return
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(TV_POINT + Vector3.UP * 3.0, TV_POINT - Vector3.UP * 2.0, 1))
	if hit.is_empty(): return
	var began := STALL_WORK.begin()
	_tv = build_tv()
	_tv.position = hit.position
	# Tela virada para o oeste, para quem anda do barco até a rua.
	_tv.rotation.y = -PI * .5
	add_child(_tv)
	STALL_WORK.finish_slow("harbor_act1.tv", began, 2000)

## TV de noticiário num pedestal: tela clara com o delegado de terno entregando uma medalha e a tarja
## do plantão. Sem som (a cena é muda no roteiro) e sem colisão (não bloqueia o desembarque).
static func build_tv() -> Node3D:
	var tv := Node3D.new()
	tv.name = "TerminalNewsTV"
	PART.piece(tv, Vector3(.12, 1.5, .12), Vector3(0, .75, 0), Color("2a2d30"))
	PART.piece(tv, Vector3(.5, .05, .4), Vector3(0, .03, 0), Color("2a2d30"))
	PART.piece(tv, Vector3(1.24, .76, .1), Vector3(0, 1.82, 0), Color("15181b"))
	PART.piece(tv, Vector3(1.12, .64, .02), Vector3(0, 1.83, .055), Color("7f9fb8"))
	# Delegado (terno escuro) e o homenageado, de perfil, com a medalha entre os dois.
	PART.piece(tv, Vector3(.16, .34, .01), Vector3(-.2, 1.72, .068), Color("1f2a3a"))
	PART.piece(tv, Vector3(.09, .1, .01), Vector3(-.2, 1.94, .068), Color("c99a7a"))
	PART.piece(tv, Vector3(.16, .3, .01), Vector3(.18, 1.7, .068), Color("4d5a46"))
	PART.piece(tv, Vector3(.09, .1, .01), Vector3(.18, 1.9, .068), Color("b98a66"))
	PART.piece(tv, Vector3(.05, .05, .012), Vector3(0, 1.78, .07), Color("d9b44a"))
	PART.piece(tv, Vector3(1.12, .13, .012), Vector3(0, 1.575, .07), Color("8c1d1d"))
	var label := Label3D.new()
	label.name = "NewsTicker"
	label.text = "PLANTÃO · DELEGADO AURÉLIO PRADO É HOMENAGEADO"
	label.font_size = 48
	label.pixel_size = .0042
	label.position = Vector3(0, 1.575, .08)
	label.modulate = Color("f1ece0")
	label.outline_size = 0
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tv.add_child(label)
	return tv

# --- Laço ----------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if session == null or not session.ready_for_play: return
	_clock += delta
	if _clock < .15: return
	var step := _clock
	_clock = 0.0
	_refresh()
	_watch_clock = maxf(0.0, _watch_clock - step)
	_update_tv()
	_update_ride(step)
	_update_heist(step)
	_update_folder(step)
	_update_press_car()
	_update_cobras()
	_update_helena()
	_retry -= step
	if _retry <= 0:
		_retry = 1.0
		if STATE.debt_tow_index(_world()) >= 0 and _chain_job_index() < 0: _start_debt_tow()
