extends Node2D
## Authored, finite Map 1 missions. The persistent ledger owns unlocks/rewards;
## this node owns world interactions, ordered checkpoints and live encounters.
signal changed
signal dialogue(speaker: String, text: String)
signal mission_finished(id: String, success: bool)

const FACTORY = preload("res://district/ModernTrafficFactory.gd")
const ENCOUNTER_PATH := "res://district/harbor_preview/cobras/CobraEncounter.gd"
const WORKSHOP := Vector2(8150, 1760)
const RESIDENT := Vector2(7210, 1850)
const SUPPLY := Vector2(8150, 2080)
const RACE_START := Vector2(7400, 1700)
const CENTER := Vector2(7700, 1700)
const INTERACT_DISTANCE := 82.0
var player: Node2D
var ledger: RefCounted
var territory: Node
var active_id := ""
var stage := 0
var elapsed := 0.0
var objective_position := Vector2.ZERO
var _encounter: Node2D
var _encounter_complete := false
var _race_path: Path2D
var _race_network: Node
var _race_legs: Array[Dictionary] = []
var _race_leg := 0
var _rival: Node2D
var _rival_follow: PathFollow2D
var _race_points := PackedVector2Array()
var _checkpoint := 0
var _race_elapsed := 0.0
var _race_started := false
var _rival_distance := 0.0
var _rival_previous := Vector2.ZERO
var _previous_subject := Vector2.ZERO
var _countdown := 0.0
var _subject_initialized := false
var _last_message := ""
var _optional_id := ""
var _neighbor: Node2D
var _contact: Node2D

func _ready() -> void:
	_spawn_neighbor()

func _spawn_neighbor() -> void:
	if is_instance_valid(_neighbor):
		_neighbor.queue_free()
	var actor_script = load("res://district/harbor_preview/cobras/CobraResident.gd")
	_neighbor = actor_script.new()
	_neighbor.name = "MissionNeighbor"
	_neighbor.guard = false
	_neighbor.profile = 1
	_neighbor.position = RESIDENT
	_neighbor.patrol = PackedVector2Array([RESIDENT])
	add_child(_neighbor)

func configure(subject: Node2D, state: RefCounted, local_territory: Node) -> void:
	player = subject
	ledger = state
	territory = local_territory
	if is_instance_valid(territory) and territory.has_signal("state_changed") and not territory.state_changed.is_connected(_on_territory_state_changed):
		territory.state_changed.connect(_on_territory_state_changed)
	# Runtime fixtures are never restored mid-combat. Resume at a safe mission
	# start, retaining completed missions and all one-time rewards in the ledger.
	if not String(ledger.data.get("active_id", "")).is_empty():
		ledger.fail()
	if is_instance_valid(territory) and territory.has_method("set_defeated"):
		territory.set_defeated(bool(ledger.data.get("defeated", false)))
	_set_access(int(ledger.data.get("cobra_access", 0)) > 0)

func start_mission(id: String) -> bool:
	if not active_id.is_empty() or ledger == null or not ledger.begin(id):
		return false
	active_id = id
	_play_feedback(ProceduralAudio.get_mission_start_stream())
	if id == "cobra_contact":
		_ensure_contact()
	if id == "cobra_collection" and (not is_instance_valid(_neighbor) or _neighbor.get("is_dead") == true):
		_spawn_neighbor() # explicit retry recreates this mission's finite cast
	stage = 0
	elapsed = 0.0
	_encounter_complete = false
	_set_access(id in ["cobra_contact", "cobra_race"])
	if id in ["cobra_collection", "cobra_supply", "cobra_finale"]:
		_provision_defense()
	match id:
		"cobra_contact": objective_position = WORKSHOP
		"cobra_race": objective_position = RACE_START
		"cobra_collection": objective_position = RESIDENT
		"cobra_supply": objective_position = SUPPLY
		"cobra_finale": objective_position = WORKSHOP
	_say("Maciota", _briefing(id))
	changed.emit()
	queue_redraw()
	return true

func interact() -> bool:
	if not is_instance_valid(player) or player.get("is_dead") == true:
		return false
	if active_id.is_empty():
		return _optional_interaction()
	if active_id == "cobra_contact" and (not is_instance_valid(_contact) or _contact.get("is_dead") == true):
		fail_mission(_tr("Ferrugem não pode mais receber a entrega. Reorganize a visita.", "Ferrugem can no longer receive the delivery. Arrange another visit."))
		return true
	if _subject().global_position.distance_to(objective_position) > INTERACT_DISTANCE:
		return false
	# Talking, collecting evidence and rescuing a resident require disembarking.
	if active_id != "cobra_race" and _subject() != player:
		_say("Dante", _tr("Preciso descer do carro.", "I need to get out of the car."))
		return true
	match active_id:
		"cobra_contact":
			if stage == 0:
				_set_stage(1)
				_say("Cobra — Ferrugem", _tr("Maciota mandou a peça? Deixa aqui. Teu irmão esteve aqui procurando um motorista. Quer falar com a turma? Faz a prova de rua.", "Maciota sent the part? Leave it here. Your brother came here looking for a driver. Want to talk to the crew? Run the street trial."))
			else:
				_finish()
		"cobra_race":
			if not _race_started:
				if _subject() == player:
					_say("Ferrugem", _tr("Venha com um carro. A pickup da oficina está disponível.", "Bring a car. The workshop pickup is available."))
				else:
					_prepare_race()
		"cobra_collection":
			if stage == 0:
				_say("Moradora", _tr("Eles voltaram para cobrar. Não deixa que levem meu filho.", "They're collecting again. Don't let them take my son."))
				_start_encounter("ambush", PackedVector2Array([RESIDENT + Vector2(0, -90), RESIDENT + Vector2(60, -70)]))
			elif _encounter_complete:
				_say("Moradora", _tr("Você ficou. Ninguém fica. Eles guardam os registros no fundo da quadra.", "You stayed. Nobody stays. They keep the records behind the block."))
				_finish()
		"cobra_supply":
			if stage == 0:
				_start_encounter("ambush", PackedVector2Array([SUPPLY + Vector2(-35, 0), SUPPLY + Vector2(0, -65)]))
			elif _encounter_complete:
				_say("Dante", _tr("Rotas, pagamentos e uma reunião na oficina. É a ligação que faltava.", "Routes, payments and a meeting at the workshop. That's the missing link."))
				_finish()
		"cobra_finale":
			if stage == 0:
				var points := PackedVector2Array([WORKSHOP + Vector2(45, 0), WORKSHOP + Vector2(-35, 65), WORKSHOP + Vector2(-35, -65)])
				if bool(ledger.data.get("optional_flags", {}).get("neighbor_route", false)):
					points.remove_at(2)
				_start_encounter("boss", points)
			elif _encounter_complete:
				_say("Dante", _tr("Uma transferência para fora de Harbor… e as iniciais dele. Isso não prova nada. Ainda.", "A transfer out of Harbor… and his initials. That proves nothing. Not yet."))
				_finish()
	return true

func _physics_process(delta: float) -> void:
	if ledger == null or not is_instance_valid(player) or get_tree().paused:
		return
	if active_id.is_empty():
		return
	if String(ledger.data.get("active_id", "")) != active_id:
		_cleanup() # a restored save replaced the active ledger
		return
	if player.get("is_dead") == true:
		fail_mission(_tr("Você foi hospitalizado. A missão pode ser tentada novamente.", "You were hospitalized. You can retry the mission."))
		return
	if active_id == "cobra_contact" and (not is_instance_valid(_contact) or _contact.get("is_dead") == true):
		fail_mission(_tr("O contato morreu. A entrega falhou.", "Your contact died. The delivery failed."))
		return
	if active_id == "cobra_collection" and is_instance_valid(_neighbor) and _neighbor.get("is_dead") == true:
		fail_mission(_tr("A moradora morreu. A proteção falhou.", "The resident died. You failed to protect her."))
		return
	if player.get("is_in_dialogue") == true or player.get("is_control_disabled") == true:
		if is_instance_valid(_rival):
			_rival.set_process(false)
		return
	elapsed += delta
	if _race_started:
		_tick_race(delta)
	# Combat cannot survive an interior transition, leaving an invisible boss
	# elsewhere while a hospital/garage UI is active. Retreat remains retryable.
	elif stage > 0 and is_instance_valid(_encounter) and _subject().global_position.distance_to(objective_position) > 1500.0:
		fail_mission(_tr("Você recuou. Reorganize-se e tente de novo.", "You withdrew. Regroup and try again."))

func _start_encounter(kind: String, points: PackedVector2Array) -> void:
	var script = load(ENCOUNTER_PATH)
	if script == null:
		fail_mission(_tr("Encontro indisponível.", "Encounter unavailable."))
		return
	_encounter = script.new()
	_encounter.name = "CampaignEncounter"
	_encounter.configure(kind, points)
	_encounter.completed.connect(_on_encounter_completed)
	add_child(_encounter)
	_set_stage(1)
	if is_instance_valid(territory) and territory.has_method("set_encounter_active"):
		territory.set_encounter_active(true)
	_set_access(true) # encounter actors, not every ambient guard, own this fight

func _on_encounter_completed() -> void:
	_encounter_complete = true
	_set_stage(2)
	_say("Dante", _tr("Área segura. Vou conferir aqui.", "Area clear. I'll check here."))

func _prepare_race() -> void:
	_cleanup_race()
	_race_points.clear()
	for quarter in range(1, 5):
		var angle := PI + float(quarter) * PI * 0.5
		_race_points.append(CENTER + Vector2(cos(angle), sin(angle)) * 300.0)
	if not _resolve_race_lanes():
		fail_mission(_tr("Circuito indisponível. Verifique a malha.", "Circuit unavailable. Check the road network."))
		return
	_rival = FACTORY.spawn_moving_vehicle(_race_path, "CobraRaceRival", "ranch_pickup", 0.04, 105.0, 5)
	_rival_follow = _rival.get_parent() as PathFollow2D
	_plan_rival_leg()
	_rival.set_process(false)
	_rival.set_physics_process(false)
	_rival_previous = _rival.global_position
	_rival_distance = 0.0
	_checkpoint = 0
	_countdown = 3.0
	_race_elapsed = 0.0
	_subject_initialized = false
	_race_started = true
	objective_position = RACE_START
	_set_stage(1)
	_say("Ferrugem", _tr("Três segundos. Uma volta, sem cortar o jardim. Cruze os quatro portões.", "Three seconds. One lap, no cutting through the garden. Pass all four gates."))

func _tick_race(delta: float) -> void:
	if not is_instance_valid(_rival):
		fail_mission(_tr("A prova foi interrompida. Tente novamente.", "The race was interrupted. Try again."))
		return
	var car := _subject()
	if car == player:
		fail_mission(_tr("Você abandonou o carro. Tente novamente.", "You left the car. Try again."))
		return
	if _countdown > 0.0:
		if car.global_position.distance_to(RACE_START) > 100.0:
			fail_mission(_tr("Queimou a largada. Tente novamente.", "False start. Try again."))
			return
		_countdown -= delta
		if _countdown <= 0.0:
			_rival.set_process(true)
			_rival.set_physics_process(true)
			objective_position = _race_points[0]
			changed.emit()
		return
	_race_elapsed += delta
	if is_instance_valid(_rival):
		_rival.set_process(true)
		var follow := _rival.get_parent() as PathFollow2D
		if follow == null:
			fail_mission(_tr("O carro rival saiu da prova. Reinicie na largada.", "The rival left the race. Restart at the starting line."))
			return
		if _race_leg < _race_legs.size() and follow.get_parent() == _race_network.get_lane_path(String(_race_legs[_race_leg].to_lane_id)):
			_race_leg += 1
			_plan_rival_leg()
	if _subject_initialized and car.global_position.distance_to(_previous_subject) > maxf(80.0, delta * 900.0):
		fail_mission(_tr("Percurso interrompido. Volte à largada.", "Route interrupted. Return to the start."))
		return
	_previous_subject = car.global_position
	_subject_initialized = true
	if absf(car.global_position.distance_to(CENTER) - 300.0) > 70.0:
		fail_mission(_tr("Saiu do circuito. Tente novamente.", "You left the circuit. Try again."))
		return
	if is_instance_valid(_rival):
		_rival_distance += _rival.global_position.distance_to(_rival_previous)
		_rival_previous = _rival.global_position
	if _race_leg >= 4 or _rival_distance >= 1880.0 or _race_elapsed > 100.0:
		fail_mission(_tr("O rival venceu. A prova continua disponível.", "The rival won. The race remains available."))
		return
	if car.global_position.distance_to(_race_points[_checkpoint]) < 85.0:
		_checkpoint += 1
		if _checkpoint == _race_points.size():
			_say("Ferrugem", _tr("Você sabe dirigir. Só não confunde isso com mandar aqui.", "You can drive. Don't mistake that for being in charge."))
			_finish()
		else:
			objective_position = _race_points[_checkpoint]
			changed.emit()
	queue_redraw()

func _finish() -> void:
	var id := active_id
	if not ledger.complete():
		return
	var reward: Dictionary = ledger.claim_reward(id)
	_play_feedback(ProceduralAudio.get_mission_passed_stream())
	if not reward.is_empty() and player.get("money") != null:
		player.money += int(reward.get("cash", 0))
	_cleanup()
	if id == "cobra_finale" and is_instance_valid(territory):
		territory.set_defeated(true)
	_say("Maciota · telefone", get_brother_clue(id))
	mission_finished.emit(id, true)

func _play_feedback(stream: AudioStream) -> void:
	var sound := AudioStreamPlayer.new()
	sound.process_mode = Node.PROCESS_MODE_ALWAYS
	sound.bus = &"SFX"
	sound.stream = stream
	sound.volume_db = -10.0
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()

func fail_mission(reason: String = "") -> void:
	if active_id.is_empty():
		return
	var id := active_id
	ledger.fail()
	_cleanup()
	_say("Dante", reason)
	mission_finished.emit(id, false)

func _cleanup_race() -> void:
	if is_instance_valid(_rival):
		if _rival.get("is_driven_by_player") == true and _rival.has_method("exit_vehicle"):
			_rival.exit_vehicle()
		_rival.queue_free()
	if is_instance_valid(_rival_follow):
		_rival_follow.queue_free()
	_rival_follow = null
	_race_path = null
	_rival = null
	_race_started = false

func _resolve_race_lanes() -> bool:
	_race_legs.clear()
	_race_leg = 0
	for node in get_tree().current_scene.find_children("*", "", true, false):
		if not node.has_method("get_graph_data") or not node.has_method("get_lane_path"):
			continue
		var graph: Dictionary = node.get_graph_data()
		var connections: Array = graph.get("lane_connections", [])
		for connection in connections:
			if String(connection.from_road_id).get_file() == "cobra_court_northwest" and String(connection.to_road_id).get_file() == "cobra_court_northeast":
				_race_legs.append(connection)
				break
		if _race_legs.is_empty():
			continue
		for road in ["cobra_court_southeast", "cobra_court_southwest", "cobra_court_northwest"]:
			for connection in connections:
				if String(connection.from_lane_id) == String(_race_legs.back().to_lane_id) and String(connection.to_road_id).get_file() == road:
					_race_legs.append(connection)
					break
		if _race_legs.size() == 4:
			_race_network = node
			_race_path = node.get_lane_path(String(_race_legs[0].from_lane_id))
			return is_instance_valid(_race_path)
		_race_legs.clear()
	return false

func _plan_rival_leg() -> void:
	if not is_instance_valid(_rival) or _race_leg >= _race_legs.size():
		return
	var follow := _rival.get_parent() as PathFollow2D
	var leg: Dictionary = _race_legs[_race_leg]
	follow.set_meta("traffic_planned_connection_id", String(leg.connection_id))
	follow.set_meta("traffic_planned_junction_index", int(leg.junction_index))

func _cleanup() -> void:
	_cleanup_race()
	if is_instance_valid(_encounter):
		_encounter.queue_free()
	_encounter = null
	active_id = ""
	stage = 0
	objective_position = Vector2.ZERO
	if is_instance_valid(territory) and territory.has_method("set_encounter_active"):
		territory.set_encounter_active(false)
	_set_access(int(ledger.data.get("cobra_access", 0)) > 0)
	changed.emit()
	queue_redraw()

func _optional_interaction() -> bool:
	if ledger == null or not is_instance_valid(_neighbor) or _neighbor.get("is_dead") == true or _subject() != player or player.global_position.distance_to(RESIDENT) > INTERACT_DISTANCE:
		return false
	var flags: Dictionary = ledger.data.get("optional_flags", {})
	if bool(flags.get("neighbor_route", false)):
		return false
	flags["neighbor_route"] = true
	ledger.data["optional_flags"] = flags
	_say("Moradora", _tr("Obrigada por parar para ouvir. O beco dá nos fundos da oficina. Quando precisar, eu distraio um deles.", "Thanks for stopping to listen. The alley leads behind the workshop. When you need it, I'll distract one of them."))
	changed.emit()
	return true

func _set_access(value: bool) -> void:
	if is_instance_valid(territory) and territory.has_method("set_mission_access"):
		territory.set_mission_access(value)

func _ensure_contact() -> void:
	# Reuse the physical workshop guard. Only an explicit mission retry replaces
	# this one dead actor, preserving the territory's finite three-person roster.
	var guards: Array = territory.guards if is_instance_valid(territory) else []
	if guards.size() > 2 and is_instance_valid(guards[2]) and not guards[2].is_dead:
		_contact = guards[2]
		return
	var actor_script = load("res://district/harbor_preview/cobras/CobraResident.gd")
	if is_instance_valid(_contact):
		_contact.queue_free()
	_contact = actor_script.new()
	_contact.name = "CobraWorkshopContact"
	_contact.guard = true
	_contact.profile = 2
	_contact.territory = territory
	_contact.patrol = PackedVector2Array([WORKSHOP])
	if is_instance_valid(territory) and guards.size() > 2:
		if is_instance_valid(guards[2]):
			guards[2].queue_free()
		guards[2] = _contact
		_contact.position = territory.to_local(WORKSHOP)
		territory.add_child(_contact)
	else:
		_contact.position = to_local(WORKSHOP)
		add_child(_contact) # isolated contract fixture, still a real actor

func _on_territory_state_changed(_previous: String, next: String) -> void:
	if next != "combat" or ledger == null or not is_instance_valid(territory):
		return
	if bool(territory.get_status().get("aggressor", false)):
		ledger.data.cobra_access = 0
		if active_id in ["cobra_contact", "cobra_race"]:
			fail_mission(_tr("Você rompeu o acordo ao atacar os moradores.", "You broke the agreement by attacking the locals."))
		changed.emit()

func _provision_defense() -> void:
	# Bounded equipment support, not an unlimited weapon grant. Only bring an
	# empty/low pistol up to one useful reserve, using the production loot API.
	if not player.has_method("add_weapon_loot"):
		return
	var ammunition = player.get("weapon_ammo")
	var rounds := 0
	if ammunition is Dictionary:
		var pistol: Dictionary = ammunition.get("pistol", {})
		rounds = int(pistol.get("clip", 0)) + int(pistol.get("reserve", 0))
	if rounds < 36:
		player.add_weapon_loot(&"pistol", 36 - rounds)

func _subject() -> Node2D:
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		if vehicle is Node2D and vehicle.get("is_driven_by_player") == true:
			return vehicle
	return player

func _set_stage(value: int) -> void:
	stage = value
	ledger.set_stage(value)
	changed.emit()

func _say(speaker: String, message: String) -> void:
	_last_message = message
	dialogue.emit(speaker, message)

func get_status() -> Dictionary:
	var near := is_instance_valid(player) and _subject().global_position.distance_to(objective_position) <= INTERACT_DISTANCE
	return {"active_id":active_id, "stage":stage, "objective":get_objective(), "position":objective_position, "target":objective_position, "can_interact":near and not active_id.is_empty(), "checkpoint":_checkpoint, "checkpoint_count":4, "countdown":maxf(0.0,_countdown), "race_seconds":_race_elapsed, "message":_last_message}

func get_objective() -> String:
	match active_id:
		"cobra_contact": return _tr("Oficina Cobra: entregue a peça e converse [E].", "Cobra workshop: deliver the part and talk [E].")
		"cobra_race": return (_tr("Portão %d/4", "Gate %d/4") % mini(_checkpoint+1,4)) if _race_started else _tr("Leve um carro até a largada [R].", "Bring a car to the starting line [R].")
		"cobra_collection": return _tr("Proteja a moradora; depois fale com ela [E].", "Protect the resident, then talk to her [E].") if stage > 0 else _tr("Ouça a moradora ameaçada [E].", "Hear the threatened resident [E].")
		"cobra_supply": return _tr("Neutralize os cobradores e recolha os registros [E].", "Stop the collectors and recover the records [E].")
		"cobra_finale": return _tr("Derrote a liderança e procure a pista na oficina [E].", "Defeat the leadership and search the workshop for a clue [E].")
	return ""

func get_brother_clue(id: String) -> String:
	match id:
		"primeiro_giro": return _tr("A peça está certa. O contato é Ferrugem, na oficina dos Cobras. Ele recebeu teu irmão procurando trabalho. Leva a peça até ele; o serviço já está no quadro.", "The part checks out. Your contact is Ferrugem at the Cobras workshop. He met your brother when he was looking for work. Take him the part; the job is on the board.")
		"cobra_contact": return _tr("Ferrugem confirmou: teu irmão perguntou por um motorista da turma das corridas. A prova é tua chance de se aproximar deles. Já pode aceitar no quadro.", "Ferrugem confirmed your brother asked for a driver from the racing crew. The trial is your chance to get close to them. It is ready on the board.")
		"cobra_race": return _tr("O motorista falou comigo: deixou teu irmão perto da casa de uma moradora em Ashbend. Os Cobras estão cobrando dela. Ajuda a mulher e pergunta o que viu.", "The driver called me: he dropped your brother near the home of a resident in Ashbend. The Cobras are extorting her. Help her and ask what she saw.")
		"cobra_collection": return _tr("A moradora reconheceu teu irmão. Ele também perguntou pelos registros de carga. Ela indicou onde os Cobras guardam os papéis; vamos seguir essa pista.", "The resident recognized your brother. He also asked about cargo records. She told us where the Cobras keep their papers; let us follow that lead.")
		"cobra_supply": return _tr("As datas desses registros batem com a passagem dele pelo cais. A autorização saiu da oficina da liderança. É lá que podemos descobrir qual carga ele acompanhou.", "The dates in those records match his visit to the docks. The authorization came from the leaders workshop. That is where we can learn which shipment he followed.")
		"cobra_finale": return _tr("Uma transferência para fora de Harbor e as iniciais dele. Temos uma rota para investigar, mas ainda precisamos confirmar se ele embarcou. Guarda esse documento, Dante.", "A transfer out of Harbor and his initials. We have a route to investigate, but still need to confirm he boarded. Keep that document, Dante.")
	return ""

func _briefing(id: String) -> String:
	match id:
		"cobra_contact": return _tr("Leva a peça que você buscou para Ferrugem, na oficina dos Cobras. Ele falou com teu irmão. Usa a entrega para puxar conversa.", "Take the part you collected to Ferrugem at the Cobras workshop. He spoke to your brother. Use the delivery to start a conversation.")
		"cobra_race": return _tr("O motorista que teu irmão procurou anda com a turma das corridas. Ferrugem te espera na praça; completa a prova para ganhar a confiança deles.", "The driver your brother sought runs with the racing crew. Ferrugem is waiting at the square; finish the trial to earn their trust.")
		"cobra_collection": return _tr("O motorista deixou teu irmão perto dessa moradora. Protege ela da cobrança dos Cobras; talvez aceite contar o que viu.", "The driver dropped your brother near the home of this resident. Protect her from the Cobras extortion; she may tell you what she saw.")
		"cobra_supply": return _tr("Teu irmão procurava os mesmos registros. A moradora apontou os fundos da quadra. Recupera os papéis e corta o abastecimento dos cobradores.", "Your brother sought those same records. The resident pointed us behind the block. Recover the papers and cut the collectors supply.")
		"cobra_finale": return _tr("A autorização da carga veio da liderança. Enfrenta os Cobras na oficina e procura o documento que liga teu irmão à transferência.", "The cargo authorization came from the leaders. Face the Cobras at their workshop and find the document linking your brother to the transfer.")
	return ""

func _tr(pt: String, en: String) -> String:
	return en if TranslationServer.get_locale().begins_with("en") else pt

func _draw() -> void:
	# Authored evidence remains physically legible even without a HUD marker.
	var evidence := to_local(SUPPLY)
	draw_rect(Rect2(evidence-Vector2(17,12),Vector2(34,24)),Color("645340"))
	draw_rect(Rect2(evidence-Vector2(10,8),Vector2(20,15)),Color("c7bda2"))
	for i in 3:
		draw_line(evidence+Vector2(-7,-4+i*4),evidence+Vector2(5,-4+i*4),Color("514e43"),1)
	if active_id.is_empty():
		return
	var point := to_local(objective_position)
	draw_arc(point, 28, 0, TAU, 32, Color("e5b85c"), 3, true)
	draw_line(point+Vector2(-12,0),point+Vector2(12,0),Color("e5b85c"),2)
