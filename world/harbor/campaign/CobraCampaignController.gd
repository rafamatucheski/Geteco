extends Node2D
## Authored, finite Map 1 missions. The persistent ledger owns unlocks/rewards;
## this node owns world interactions, ordered checkpoints and live encounters.
signal changed
signal dialogue(speaker: String, text: String)
signal mission_finished(id: String, success: bool)

const ENCOUNTER_PATH := "res://world/harbor/cobras/CobraEncounter.gd"
const NEIGHBORHOOD = preload("res://world/harbor/cobras/CobraNeighborhood.gd")
const RACE_RADIUS: float = NEIGHBORHOOD.RADIUS
const RACE_HALF_WIDTH: float = NEIGHBORHOOD.WIDTH * 0.5 + 18.0
const RACE_RETURN_SECONDS := 4.0
const RACE_HOUR := 21
const RACE_TIME_LIMIT := 100.0
const RACE_LANE_RADIUS: float = NEIGHBORHOOD.RADIUS + NEIGHBORHOOD.WIDTH * 0.25
const WORKSHOP := Vector2(8150, 1760)
const RESIDENT := Vector2(7210, 1850)
const SUPPLY := Vector2(8150, 2080)
const RACE_START: Vector2 = NEIGHBORHOOD.CENTER + Vector2.LEFT * RACE_LANE_RADIUS
const CENTER: Vector2 = NEIGHBORHOOD.CENTER
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
var _race_points := PackedVector2Array()
var _checkpoint := 0
var _race_elapsed := 0.0
var _race_started := false
var _previous_subject := Vector2.ZERO
var _countdown := 0.0
var _subject_initialized := false
var _last_message := ""
var _optional_id := ""
var _neighbor: Node2D
var _contact: Node2D
var _story_tow: RefCounted
var _race_car: Node2D
var _race_route := PackedVector2Array()
var _race_progress := 0.0
var _race_previous_angle := PI
var _outside_seconds := 0.0
var _was_on_track := true
var _track_exit_angle := PI
var _starting_position := Vector2.ZERO
var _race_traffic: Node2D

func _ready() -> void:
	_spawn_neighbor()

func _spawn_neighbor() -> void:
	if is_instance_valid(_neighbor):
		_forget_replaced_mission_actor(_neighbor)
		_neighbor.queue_free()
	var actor_script = load("res://world/harbor/cobras/CobraResident.gd")
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
	_story_tow = load("res://world/harbor/campaign/HarborStoryTow.gd").new()
	_story_tow.configure(self)
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
	if id == "cobra_contact" and _story_tow != null:
		_story_tow.start()
	if id == "cobra_race":
		_race_traffic = load("res://world/harbor/campaign/CobraRaceTraffic.gd").new()
		add_child(_race_traffic)
		if not _race_traffic.configure(self):
			fail_mission(_tr("A organização da prova está indisponível. Tente novamente pelo quadro do Maciota.", "The trial cannot be organized right now. Retry at Maciota's board."))
			return false
		_resolve_race_route()
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
	if active_id == "cobra_contact" and _story_tow != null:
		return _story_tow.interact()
	if _subject().global_position.distance_to(objective_position) > INTERACT_DISTANCE:
		return false
	# Talking, collecting evidence and rescuing a resident require disembarking.
	if active_id != "cobra_race" and _subject() != player:
		_say("Dante", _tr("Preciso descer do carro.", "I need to get out of the car."))
		return true
	match active_id:
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
	if player.get("is_arrested") == true:
		fail_mission(_tr("Você foi preso. Volte ao quadro do Maciota para tentar novamente.", "You were arrested. Return to Maciota's board to retry."))
		return
	if active_id == "cobra_contact" and (not is_instance_valid(_contact) or _contact.get("is_dead") == true):
		fail_mission(_tr("O contato morreu. A entrega falhou.", "Your contact died. The delivery failed."))
		return
	if active_id == "cobra_collection" and is_instance_valid(_neighbor) and _neighbor.get("is_dead") == true:
		fail_mission(_tr("A moradora morreu. A proteção falhou.", "The resident died. You failed to protect her."))
		return
	if player.get("is_in_dialogue") == true or player.get("is_control_disabled") == true:
		return
	elapsed += delta
	if active_id == "cobra_contact" and _story_tow != null:
		_story_tow.tick(delta)
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
	if is_instance_valid(_race_traffic) and not _race_traffic.is_clear():
		_say("Ferrugem", _tr("Estou fechando a entrada da praça. Ainda há %d carros saindo; espere fora do cruzamento. A contagem só começa com a pista livre. Pode cancelar pelo Diário [J], sem pagar.", "I'm closing the square entrance. %d cars are still leaving; wait clear of the junction. The countdown starts only when the route is clear. You can cancel in the Journal [J] at no cost.") % _race_traffic.remaining)
		return
	var chosen_car := _subject()
	if chosen_car == player or _vehicle_broken(chosen_car):
		_say("Ferrugem", _tr("Esse carro não pode correr. Traga um carro funcionando até a largada [R].", "That car cannot race. Bring a working car to the starting line [R]."))
		return
	if chosen_car.get("velocity") is Vector2 and chosen_car.get("velocity").length() > 20.0:
		_say("Ferrugem", _tr("Pare sobre a marca de largada, apontando para o primeiro portão ao norte, e aperte [R].", "Stop on the starting mark, facing the first gate to the north, and press [R]."))
		return
	if Vector2.RIGHT.rotated(chosen_car.global_rotation).dot(Vector2.UP) < 0.65:
		_say("Ferrugem", _tr("Vire o carro para o primeiro portão, ao norte. Pare e aperte [R] quando estiver alinhado.", "Point the car toward the first gate, to the north. Stop and press [R] when aligned."))
		return
	for clock_bridge in get_tree().get_nodes_in_group("medical_campaign_clock"):
		if clock_bridge.has_method("ensure_race_night") and not clock_bridge.ensure_race_night():
			return
	_cleanup_race()
	_race_car = chosen_car
	_starting_position = chosen_car.global_position
	_race_points.clear()
	for quarter in range(1, 5):
		var angle := PI + float(quarter) * PI * 0.5
		_race_points.append(CENTER + Vector2(cos(angle), sin(angle)) * RACE_LANE_RADIUS)
	if not _resolve_race_route():
		fail_mission(_tr("A prova não está disponível. Volte ao quadro do Maciota para tentar novamente.", "The race is unavailable. Return to Maciota's board to retry."))
		return
	_checkpoint = 0
	_countdown = 3.0
	_race_elapsed = 0.0
	_race_progress = 0.0
	_outside_seconds = 0.0
	_was_on_track = true
	_subject_initialized = false
	_race_started = true
	objective_position = RACE_START
	_set_stage(1)
	_say("Ferrugem", _tr("Teu irmão também chegou calado. Vamos ver se dirige como ele. Fique parado até JÁ! Você tem 100 segundos: norte, leste, sul e chegada aqui. Cruze os quatro portões na ordem. Siga as setas pela faixa externa. Sem armas. Se sair do asfalto, volte pelo mesmo lugar em quatro segundos.", "Your brother was quiet too. Let's see if you drive like him. Stay still until GO! You have 100 seconds: north, east, south, then finish here. Cross all four gates in order. Follow the arrows in the outer lane. No weapons. If you leave the road, rejoin at the same place within four seconds."))

func _vehicle_broken(vehicle: Node2D) -> bool:
	return not is_instance_valid(vehicle) or vehicle.get("is_broken") == true or vehicle.get("is_exploding") == true or vehicle.get("is_exploded") == true or (vehicle.get("health") != null and int(vehicle.get("health")) <= 0)

func _tick_race(delta: float) -> void:
	if _vehicle_broken(_race_car):
		fail_mission(_tr("Seu carro não pode continuar. Repare ou troque o carro e aceite a prova de novo no quadro do Maciota.", "Your car cannot continue. Repair or replace it and accept the race again at Maciota's board."))
		return
	var car := _subject()
	if car != _race_car:
		fail_mission(_tr("Você saiu do carro da prova. Volte ao quadro do Maciota para tentar novamente.", "You left your race car. Return to Maciota's board to retry."))
		return
	if _countdown > 0.0:
		if car.global_position.distance_to(_starting_position) > 18.0:
			fail_mission(_tr("Queimou a largada. Espere JÁ! na próxima tentativa pelo quadro do Maciota.", "False start. Wait for GO! on your next attempt from Maciota's board."))
			return
		var previous_second := ceili(_countdown)
		_countdown = maxf(0.0, _countdown - delta)
		if ceili(_countdown) != previous_second:
			_play_feedback(preload("res://audio/rewards/RewardAudioBank.gd").sound("checkpoint"))
			changed.emit()
			queue_redraw()
		if _countdown <= 0.0:
			_race_previous_angle = (car.global_position - CENTER).angle()
			_race_progress = wrapf(_race_previous_angle - PI, -PI, PI)
			_previous_subject = car.global_position
			_subject_initialized = true
			objective_position = _race_points[0]
			changed.emit()
		return
	_race_elapsed += delta
	if _subject_initialized and car.global_position.distance_to(_previous_subject) > maxf(80.0, delta * 900.0):
		fail_mission(_tr("Percurso interrompido. Tente novamente pelo quadro do Maciota.", "Route interrupted. Retry at Maciota's board."))
		return
	_previous_subject = car.global_position
	_subject_initialized = true
	var on_track := absf(car.global_position.distance_to(CENTER) - RACE_RADIUS) <= RACE_HALF_WIDTH
	var angle := (car.global_position - CENTER).angle()
	if on_track and _was_on_track:
		_race_progress += wrapf(angle - _race_previous_angle, -PI, PI)
	elif on_track:
		var rejoin_progress := wrapf(angle - _track_exit_angle, -PI, PI)
		if absf(rejoin_progress) > 0.3:
			fail_mission(_tr("Você cortou o trajeto. Ao sair da pista, volte pelo mesmo lugar. Tente de novo no quadro do Maciota.", "You cut the route. When leaving the road, rejoin at the same place. Retry at Maciota's board."))
			return
		_race_progress += rejoin_progress
	elif not on_track:
		if _was_on_track:
			_track_exit_angle = _race_previous_angle
		_outside_seconds += delta
		if _outside_seconds >= RACE_RETURN_SECONDS or car.global_position.distance_to(CENTER) < RACE_RADIUS * 0.5:
			fail_mission(_tr("Você abandonou o trajeto. A prova pode ser aceita de novo no quadro do Maciota.", "You left the route. Accept the race again at Maciota's board."))
			return
	if on_track:
		_outside_seconds = 0.0
	_race_previous_angle = angle
	_was_on_track = on_track
	if _race_elapsed >= RACE_TIME_LIMIT:
		fail_mission(_tr("O tempo da prova acabou. Aceite novamente no quadro do Maciota.", "Race time expired. Accept again at Maciota's board."))
		return
	# Ordered directed progress prevents reversing into gates or shortcutting
	# across the garden. The finish requires the full lap, not an 85px near miss.
	var required_progress := float(_checkpoint + 1) * PI * 0.5
	if on_track and _race_progress >= required_progress and car.global_position.distance_to(_race_points[_checkpoint]) < 85.0:
		_checkpoint += 1
		if _checkpoint == _race_points.size():
			_say("Ferrugem", _tr("Tá. Você dirige bem. O motorista vai atender o Maciota. Teu irmão queria sair de Harbor, mas não parecia estar fugindo.", "All right. You can drive. The driver will take Maciota's call. Your brother wanted out of Harbor, but he didn't look like he was running away."))
			_finish()
		else:
			_play_feedback(preload("res://audio/rewards/RewardAudioBank.gd").sound("checkpoint"))
			objective_position = _race_points[_checkpoint]
			changed.emit()
	queue_redraw()

func _finish() -> void:
	var id := active_id
	var previous_respect := int(ledger.data.get("civilian_reputation", 0))
	if not ledger.complete():
		return
	var reward: Dictionary = ledger.claim_reward(id)
	_play_feedback(ProceduralAudio.get_mission_passed_stream())
	if not reward.is_empty() and player.get("money") != null:
		player.money += int(reward.get("cash", 0))
	get_tree().call_group("hud", "show_mission_passed", int(reward.get("cash", 0)), maxi(0, int(ledger.data.get("civilian_reputation", 0)) - previous_respect))
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
	sound.volume_db = -2.0
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
	_race_started = false
	_race_car = null
	_race_route.clear()
	_outside_seconds = 0.0
	_countdown = 0.0

func _resolve_race_route() -> bool:
	_race_route.clear()
	# Cache the actual forward driving lane from the production graph. Its
	# clockwise direction uses the OUTER lane, keeping Dante with traffic.
	for node in get_tree().current_scene.find_children("*", "", true, false):
		if not node.has_method("get_graph_data") or not node.has_method("get_lane_path"):
			continue
		var graph: Dictionary = node.get_graph_data()
		var found := 0
		for id in ["cobra_court_northwest", "cobra_court_northeast", "cobra_court_southeast", "cobra_court_southwest"]:
			for lane in graph.get("lanes", []):
				if String(lane.road_id).get_file() == id and int(lane.direction) == 1:
					for point in lane.points:
						_race_route.append(node.to_global(point))
					found += 1
					break
		if found == 4:
			return _race_route.size() > 4
		_race_route.clear()
	return false

func _cleanup() -> void:
	if is_instance_valid(_race_traffic):
		_race_traffic.cleanup()
		_race_traffic.queue_free()
	_race_traffic = null
	if _story_tow != null:
		_story_tow.cleanup()
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
	var actor_script = load("res://world/harbor/cobras/CobraResident.gd")
	if is_instance_valid(_contact):
		_forget_replaced_mission_actor(_contact)
		_contact.queue_free()
	_contact = actor_script.new()
	_contact.name = "CobraWorkshopContact"
	_contact.guard = true
	_contact.profile = 2
	_contact.territory = territory
	_contact.patrol = PackedVector2Array([WORKSHOP])
	if is_instance_valid(territory) and guards.size() > 2:
		if is_instance_valid(guards[2]):
			_forget_replaced_mission_actor(guards[2])
			guards[2].queue_free()
		guards[2] = _contact
		_contact.position = territory.to_local(WORKSHOP)
		territory.add_child(_contact)
	else:
		_contact.position = to_local(WORKSHOP)
		add_child(_contact) # isolated contract fixture, still a real actor

func _forget_replaced_mission_actor(actor: Node) -> void:
	# Explicit mission retries replace this finite actor. Its stable medical
	# identity would otherwise immediately apply the old death to the new cast.
	# Never reset unrelated residents or the global medical ledger.
	var care := get_node_or_null("/root/NPCMedicalCare")
	var identity := String(actor.get_meta("medical_identity", ""))
	if care == null or identity.is_empty(): return
	care.incidents.erase(identity)
	care.residents.erase(identity)
	care.records().erase(identity)

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
	return {"active_id":active_id, "stage":stage, "objective":get_objective(), "position":objective_position, "target":objective_position, "can_interact":near and not active_id.is_empty(), "checkpoint":_checkpoint, "checkpoint_count":4, "countdown":maxf(0.0,_countdown), "race_seconds":_race_elapsed, "message":_last_message, "route":_race_route, "race_phase":("countdown" if _countdown > 0.0 else "racing") if _race_started else ("clearing" if is_instance_valid(_race_traffic) and not _race_traffic.is_clear() else "approach"), "race_preparation_cars":_race_traffic.remaining if is_instance_valid(_race_traffic) else 0, "race_time_left":maxf(0.0, RACE_TIME_LIMIT - _race_elapsed), "race_return_seconds":maxf(0.0, RACE_RETURN_SECONDS - _outside_seconds) if _outside_seconds > 0.0 else 0.0}

func get_objective() -> String:
	match active_id:
		"cobra_contact": return _story_tow.objective_text() if _story_tow != null else _tr("Oficina Cobra: entregue a peça e converse [E].", "Cobra workshop: deliver the part and talk [E].")
		"cobra_race":
			if not _race_started:
				if is_instance_valid(_race_traffic) and not _race_traffic.is_clear():
					return _tr("Preparando praça · %d carros saindo. Aguarde fora da pista. Cancelar: Diário [J].", "Preparing square · %d cars leaving. Wait off the track. Cancel: Journal [J].") % _race_traffic.remaining
				return _tr("Pare um carro na largada, apontando ao norte. Iniciar [R].", "Stop a car at the start, facing north. Start [R].")
			if _countdown > 0.0:
				return _tr("LARGADA EM %d · Fique parado até JÁ!", "START IN %d · Stay still until GO!") % ceili(_countdown)
			if _outside_seconds > 0.0:
				return _tr("VOLTE À PISTA PELO MESMO LUGAR · %d s", "REJOIN THE ROAD AT THE SAME PLACE · %d s") % ceili(RACE_RETURN_SECONDS - _outside_seconds)
			if _checkpoint == 3:
				return _tr("CHEGADA · Portão 4/4 · Restam %d s.", "FINISH · Gate 4/4 · %d s left.") % ceili(RACE_TIME_LIMIT - _race_elapsed)
			return _tr("Portão %d/4 · Restam %d s · Siga as setas pela faixa externa.", "Gate %d/4 · %d s left · Follow the outer-lane arrows.") % [_checkpoint + 1, ceili(RACE_TIME_LIMIT - _race_elapsed)]
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
		"cobra_race": return _tr("Às 21h, Ferrugem fecha a praça para uma prova. O motorista que viu teu irmão quer saber se você dirige bem. Espere o trânsito sair e leve um carro à largada de Ashbend. Complete os quatro portões em 100 segundos. Pode cancelar ou tentar novamente sem pagar.", "At 9 pm, Ferrugem closes the square for a trial. The driver who saw your brother wants to know if you can drive. Let traffic leave, then bring a car to the Ashbend start. Complete four gates within 100 seconds. Cancelling or retrying costs nothing.")
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
	if active_id == "cobra_race":
		_draw_race_route()
		return
	if active_id.is_empty() or active_id == "cobra_contact":
		return
	var point := to_local(objective_position)
	draw_arc(point, 28, 0, TAU, 32, Color("e5b85c"), 3, true)
	draw_line(point+Vector2(-12,0),point+Vector2(12,0),Color("e5b85c"),2)

func _draw_race_route() -> void:
	var gold := Color("e5b85c")
	if _race_route.size() > 1:
		var local_route := PackedVector2Array()
		for point in _race_route:
			local_route.append(to_local(point))
		draw_polyline(local_route, Color(0.90, 0.72, 0.36, 0.42), 4.0, true)
	# These are navigation markings, not new physical obstructions. Arrows
	# indicate the same clockwise circuit as the forward lane in the road graph.
	for index in 12:
		var angle := PI + float(index) * TAU / 12.0 + 0.16
		var radial := Vector2(cos(angle), sin(angle))
		var tangent := Vector2(-radial.y, radial.x)
		var point := to_local(CENTER + radial * RACE_LANE_RADIUS)
		draw_polyline(PackedVector2Array([point - tangent * 9.0 + radial * 7.0, point + tangent * 5.0, point - tangent * 9.0 - radial * 7.0]), gold, 3.0, true)
	var font := ThemeDB.fallback_font
	for index in 4:
		var angle := PI + float(index + 1) * PI * 0.5
		var radial := Vector2(cos(angle), sin(angle))
		var point := to_local(CENTER + radial * RACE_LANE_RADIUS)
		var color := Color("73af8c") if _race_started and index < _checkpoint else gold
		draw_line(point - radial * 38.0, point + radial * 38.0, color, 5.0, true)
		draw_string(font, point + radial * 53.0 + Vector2(-6, 5), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, color)
	var start := to_local(RACE_START) + Vector2(-80, -48)
	var label := _tr("LARGADA [R]", "START [R]")
	if _race_started:
		label = str(ceili(_countdown)) if _countdown > 0.0 else (_tr("JÁ!", "GO!") if _race_elapsed < 1.0 else _tr("CHEGADA", "FINISH"))
	draw_string(font, start, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, gold)
