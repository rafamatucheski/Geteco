extends Node3D
const UNIT := 1.0/16.0
const CENTER := Vector3(7700,0,1700)*UNIT
const RADIUS := 321.0*UNIT
var session
var actors: Dictionary = {}
var enemies: Array[Node3D] = []
var targets := {"ferrugem":Vector3(8150,0,1760)*UNIT,"ashbend_resident":Vector3(7210,0,1850)*UNIT,"cobra_supply":Vector3(8150,0,2080)*UNIT,"transfer_document":Vector3(8150,0,1760)*UNIT,"harbor_parcel":Vector3(3515,0,1450)*UNIT,"neco":Vector3(-980,0,480)*UNIT,"neco_bay":Vector3(-750,0,850)*UNIT}
var cargo: CharacterBody3D
var truck: CharacterBody3D
var loaded := false
var unloaded_at_bay := false
var tow_job: Dictionary = {}
var encounter_id := ""
var clock := 0.0
var tow_pending_clock := 0.0
var props: Dictionary = {}
var aftermath_open := false
var failure_retry_clock := 0.0

func _ready() -> void:
	targets.neco = Vector3(-750,0,550)*UNIT+Vector3(-6,0,8.7)
	targets.neco_bay = Vector3(-750,0,550)*UNIT+preload("res://world/places/SalvageYardNative.gd").PICKUP
	targets.ashbend_start = CENTER+Vector3.LEFT*RADIUS
	targets.ashbend_finish = targets.ashbend_start
	for index in 4:
		var angle := PI+(index+1)*TAU/4
		targets["ashbend_gate_%d"%index] = CENTER+Vector3(cos(angle),0,sin(angle))*RADIUS
	targets.resident_encounter = targets.ashbend_resident
	targets.supply_encounter = targets.cobra_supply
	targets.boss_encounter = targets.ferrugem

func begin(id: String) -> bool:
	if not session.state.campaign.available_missions().has(id): return false
	# The restart checkpoint precedes acceptance and any mission-owned vehicle.
	if not session.save_game(true): return false
	if id == "cobra_contact":
		if session.state.region_id != "harbor":
			session.show_message("Volte a Harbor para preparar o guincho desta missão.")
			return false
		if not session.activities.snapshot().get("tow_contract",{}).is_empty():
			session.show_message("Conclua o serviço de guincho antes de aceitar esta missão.")
			return false
		if not begin_tow_job({"story":true,"kind":"local"}):
			session.show_message("Guincho indisponível. Recupere o caminhão ou libere a área de retirada.")
			return false
	# No await between preparation and acceptance: neither can publish a partial save.
	if not session.state.campaign.begin(id): return false
	_clear_encounter()
	# Retry replaces only the dead mission contact, never unrelated residents.
	var contact: String = "ferrugem" if id == "cobra_contact" else ("ashbend_resident" if id == "cobra_collection" else "")
	if actors.has(contact) and is_instance_valid(actors[contact]) and actors[contact].dead:
		actors[contact].queue_free()
		actors.erase(contact)
	if id == "primeiro_giro":
		var dialogue = preload("res://systems/campaign/OriginalDialogue.gd").new()
		session.show_dialogue(dialogue.lines("primeiro_giro_begin"))
	return true

func _clear_encounter() -> void:
	for enemy in enemies:
		if not is_instance_valid(enemy): continue
		enemy.set_process(false)
		enemy.set_physics_process(false)
		enemy.collision_layer = 0
		enemy.collision_mask = 0
		enemy.queue_free()
	enemies.clear()
	encounter_id = ""

func cancel_attempt(reason := "cancelled") -> bool:
	_clear_encounter()
	aftermath_open = false
	if session.state.campaign.active_id.is_empty(): return false
	if tow_job.get("story",false) and not cancel_tow_job():
		# Keep ownership and physical cargo until a collision-safe release exists.
		# A suspended attempt cannot advance or pay rewards, including after load.
		session.state.campaign.suspend_attempt(reason)
		return false
	return session.state.campaign.cancel(reason)

func _update_failure() -> bool:
	var campaign = session.state.campaign
	if campaign.is_suspended():
		if failure_retry_clock <= 0:
			failure_retry_clock = 1.0
			if cancel_attempt(str(campaign.snapshot().failure).trim_prefix("pending:")): session.save_game()
		return true
	if campaign.active_id.is_empty(): return false
	var reason := ""
	if session.world.gameplay.health <= 0: reason = "player_death"
	var contact: String = "ferrugem" if campaign.active_id == "cobra_contact" else ("ashbend_resident" if campaign.active_id == "cobra_collection" else "")
	if actors.has(contact) and is_instance_valid(actors[contact]) and actors[contact].dead: reason = "contact_dead"
	if not encounter_id.is_empty() and not _encounter_cleared() and (session.state.region_id != "harbor" or not session.state.place_id.is_empty() or session.world.player.position.distance_to(targets[encounter_id]) > 1500.0*UNIT): reason = "encounter_retreat"
	if reason.is_empty(): return false
	cancel_attempt(reason)
	session.save_game()
	session.show_message("Missão interrompida. Reorganize-se e tente novamente pelo quadro do Maciota.")
	return true

func _update_aftermath() -> void:
	if aftermath_open and not session.dialogue_open: aftermath_open = false
	if aftermath_open or session.modal or session.vehicle_transition_busy or session.world.gameplay.health <= 0: return
	if session.state.region_id != "harbor" or not session.state.place_id.is_empty() or session.world.driving.occupied or session.world.gameplay.stars > 0: return
	if not session.state.campaign.aftermath_pending() or not enemies.is_empty() or not session.state.campaign.active_id.is_empty(): return
	aftermath_open = true
	# Reuse the session's dialogue ownership/close path. No camera, teleport,
	# extra reward or access unlock is manufactured by this local epilogue.
	session.show_dialogue([
		{"speaker":"Maciota · telefone","message":"Uma transferência para fora de Harbor e as iniciais dele. Temos uma rota para investigar, mas ainda precisamos confirmar se ele embarcou. Guarda esse documento, Dante."},
		{"speaker":"Dante","message":"Está feito. Os Cobras não mandam mais aqui."},
		{"speaker":"Maciota","message":"Os Cobras recuaram. O Ironback está na garagem. É seu."},
		{"speaker":"Dante","message":"E os registros? Ainda falta uma peça nessa história."},
		{"speaker":"Maciota","message":"Guarda isso. O acesso à ilha ainda está fechado."}
	],func():
		aftermath_open = false
		if session.state.campaign.complete_aftermath_call(): session.save_game())

func target_position() -> Vector3:
	var id: String = session.state.campaign.target_id()
	if id == "maciota": return session.world.maciota_place.entry_position
	if id == "helena": return preload("res://world/places/PlaceCatalog.gd").get_definition("harbor_bank").entry_position
	if id == "story_tow_vehicle" and is_instance_valid(cargo): return cargo.global_position
	return targets.get(id,session.world.maciota_place.entry_position)

func nearest_action() -> Dictionary:
	var local_position: Vector3 = session.world.player.position
	var berth := Vector3(1930,0,1220)*UNIT if session.state.region_id == "harbor" else preload("res://world/places/PlaceCatalog.gd")._at(Vector2(7500,-1760),"mountain")
	if local_position.distance_to(berth) < 3: return {"id":"mission","target":"travel","label":"Viajar para "+("a serra" if session.state.region_id == "harbor" else "o porto")}
	if session.state.region_id != "harbor": return {}
	if is_instance_valid(truck) and not truck.has_meta("tow_pending") and truck.health <= 0 and local_position.distance_to(truck.position) < 5:
		return {"id":"mission","target":"tow_recover","label":"Recuperar guincho"}
	if not tow_job.is_empty() and is_instance_valid(cargo) and not cargo.has_meta("tow_pending") and cargo.health <= 0 and local_position.distance_to(cargo.position) < 5:
		return {"id":"mission","target":"tow_recover_cargo","label":"Recuperar carro rebocado"}
	var target: String = session.state.campaign.target_id()
	if target == "helena" and session.robberies.bank_unavailable() and session.world.gameplay.stars == 0:
		var bank: Dictionary = preload("res://world/places/PlaceCatalog.gd").get_definition("harbor_bank")
		if local_position.distance_to(bank.entry_position) < 105.0*UNIT: return {"id":"mission","target":"helena","label":"Ligar para pedir segunda via"}
	if targets.has(target) and local_position.distance_to(targets[target]) < 2.2 and not str(target).ends_with("encounter"):
		return {"id":"mission","target":target,"label":"Conversar" if target in ["ferrugem","ashbend_resident","neco"] else "Recolher"}
	if is_instance_valid(truck) and local_position.distance_to(truck.position) < 5:
		return {"id":"mission","target":"tow_toggle","label":"Descarregar" if loaded else "Carregar guincho"}
	return {}
func nearest_vehicle_action() -> Dictionary:
	if _can_start_race(): return {"id":"mission","target":"race_start","label":"Preparar corrida · fique parado"}
	if is_instance_valid(truck) and session.world.driving.car == truck and absf(truck.speed)<.3:
		return {"id":"mission","target":"tow_toggle","label":"Descarregar" if loaded else "Carregar guincho"}
	return {}

func perform(id: String) -> bool:
	if id == "tow_recover": return _recover_tow_truck()
	if id == "tow_recover_cargo": return _recover_tow_cargo()
	if id=="race_start":
		if not _can_start_race(): return false
		var car=session.world.driving.car
		if not _event("race_started","ashbend_start",{"race_vehicle_id":car.vehicle_id,"race_position":Vector2(car.position.x,car.position.z)}): return false
		session.show_message("Fique parado até JÁ! · 3")
		return true
	if id == "travel":
		if session.controller.travel("mountain" if session.state.region_id == "harbor" else "harbor"):
			return true
		return false
	if id == "tow_toggle": return _tow_toggle()
	if session.state.campaign.is_suspended(): return false
	var step: Dictionary = session.state.campaign.current_step()
	if step.is_empty() or id != step.target: return false
	var bank_copy := false
	if id == "helena" and session.state.place_id != "harbor_bank":
		var bank: Dictionary = preload("res://world/places/PlaceCatalog.gd").get_definition("harbor_bank")
		bank_copy = session.state.place_id.is_empty() and session.robberies.bank_unavailable() and session.world.gameplay.stars == 0 and session.world.player.position.distance_to(bank.entry_position)<105.0*UNIT
		if not bank_copy: return false
	if id == "maciota" and session.state.place_id != "maciota": return false
	if targets.has(id) and session.world.player.position.distance_to(targets[id]) > 2.3: return false
	var dialogue = preload("res://systems/campaign/OriginalDialogue.gd").new()
	var dialogue_key := "bank_receipt" if id == "helena" else ("primeiro_giro_finish" if id == "maciota" else str(step.event))
	if bank_copy: dialogue_key = "bank_unavailable"
	var lines: Array = dialogue.lines(dialogue_key)
	if lines.is_empty():
		lines = [{"speaker":id.capitalize(),"message":str(step.objective)}]
	session.show_dialogue(lines,func(): _event(step.event,id))
	return true

func _event(event: String, target: String, extras := {}) -> bool:
	if session.world.gameplay.health <= 0: return false
	if target in ["ferrugem","ashbend_resident"] and (not actors.has(target) or not is_instance_valid(actors[target]) or actors[target].dead): return false
	var payload := {"target_id":target,"on_foot":not session.world.driving.occupied,"in_vehicle":session.world.driving.occupied,"unarmed":session.state.equipped_weapon in ["","fists"],"wanted_level":session.world.gameplay.stars,"encounter_cleared":not enemies.is_empty() and _encounter_cleared(),"story_vehicle_alive":is_instance_valid(cargo) and cargo.health>0,"correct_vehicle":is_instance_valid(cargo) and cargo.vehicle_id == "story_tow_vehicle","elapsed":session.state.campaign.race_elapsed()}
	payload.merge(extras,true)
	if event == "neco_repair_received":
		payload.tow_delivery_ready = tow_job.get("story") == true and can_finish_tow_job()
	var result: Dictionary = session.state.campaign.apply_event(event,payload)
	if not result.ok:
		session.show_message("Objetivo pendente: "+str(result.get("reason","requisitos")))
		return false
	# apply_event checks the same physical precondition; no await or signal occurs
	# between acceptance and release, so progress and ownership are saved together.
	if event == "neco_repair_received": finish_tow_job()
	if str(result.get("completed","")) == "cobra_finale": _clear_encounter()
	for id in session.state.campaign.snapshot().pending_rewards.keys(): session.state.campaign.claim_reward(session.state.economy,id)
	if session.state.campaign.active_id.is_empty(): session.save_game()
	return true

func _process(delta: float) -> void:
	if not session.ready_for_play: return
	failure_retry_clock = maxf(0,failure_retry_clock-delta)
	_tick_race(delta)
	if loaded and is_instance_valid(cargo) and is_instance_valid(truck):
		cargo.global_transform = truck.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,1.05,1.3))
		cargo.visible = session.state.region_id == "harbor" and not truck.has_meta("tow_pending")
	tow_pending_clock -= delta
	if tow_pending_clock <= 0:
		tow_pending_clock = 1.0
		_activate_tow_reservations()
	clock += delta
	if clock < .15: return
	clock = 0
	if _update_failure(): return
	_update_aftermath()
	var actors_active: bool = session.state.region_id == "harbor" and session.state.place_id.is_empty()
	for actor in actors.values()+enemies:
		if not is_instance_valid(actor): continue
		actor.visible = actors_active
		actor.set_physics_process(actors_active and not actor.dead)
		if actor in enemies: actor.set_process(actors_active and not actor.dead)
	if session.state.region_id != "harbor" or not session.state.place_id.is_empty(): return
	_spawn_near_actors()
	var step: Dictionary = session.state.campaign.current_step()
	if step.is_empty(): return
	var subject: Node3D = session.world.driving.car if session.world.driving.occupied else session.world.player
	var destination := target_position()
	if session.state.campaign.active_id!="cobra_race" and step.get("in_vehicle",false) and session.world.driving.occupied and subject.position.distance_to(destination)<3:
		_event(step.event,step.target,{"checkpoint":step.get("checkpoint",-1)})
	elif step.get("encounter",false):
		if encounter_id != step.target and subject.position.distance_to(destination)<20: _start_encounter(step.target,destination)
		if encounter_id == step.target and _encounter_cleared(): _event(step.event,step.target)

func _tick_race(delta: float) -> void:
	if get_tree().paused or session.modal or session.vehicle_transition_busy or session.state.campaign.is_suspended() or session.state.campaign.active_id!="cobra_race" or session.state.campaign.step==0: return
	var driving=session.world.driving
	var valid_car: bool=driving.occupied and is_instance_valid(driving.car)
	var point: Vector3=driving.car.position if valid_car else session.world.player.position
	var same_world: bool=session.state.region_id=="harbor" and session.state.place_id.is_empty()
	if session.state.campaign.step==5 and valid_car and same_world and driving.car.health>0 and driving.car.vehicle_id==session.state.campaign.race_status().get("vehicle_id",""):
		_finish_race()
		return
	var result: Dictionary=session.state.campaign.tick_race(delta,Vector2(point.x,point.z),str(driving.car.vehicle_id) if valid_car and same_world else "",not valid_car or driving.car.health>0)
	if result.is_empty(): return
	var failure: String=result.failure
	if not failure.is_empty():
		var messages := {"race_timeout":"O tempo da prova acabou.","race_offtrack":"Você abandonou o trajeto.","race_shortcut":"Você cortou o trajeto. Volte à pista pelo mesmo lugar.","race_false_start":"Queimou a largada. Espere JÁ! na próxima tentativa.","race_vehicle_broken":"Seu carro não pode continuar.","race_vehicle_left":"Você saiu do carro da prova.","race_interrupted":"Percurso interrompido."}
		session.show_message(str(messages.get(failure,"Prova interrompida."))+" Tente novamente pelo quadro do Maciota.")
		session.save_game()
		return
	if result.countdown_changed:
		var countdown: float=session.state.campaign.race_status().get("countdown",0)
		session.show_message("JÁ!" if countdown==0 else "Fique parado · %d"%ceili(countdown))
		session.save_game()
	if int(result.crossed)>=0:
		var checkpoint: int=int(result.crossed)
		if _event("race_checkpoint","ashbend_gate_%d"%checkpoint,{"checkpoint":checkpoint}) and checkpoint==3:
			_finish_race()

func _finish_race() -> void:
	if _event("race_finished","ashbend_finish"):
		session.show_dialogue([{"speaker":"Ferrugem","message":"Tá. Você dirige bem. O motorista vai atender o Maciota. Teu irmão queria sair de Harbor, mas não parecia estar fugindo."}])

func _can_start_race() -> bool:
	if session.state.campaign.is_suspended() or session.state.campaign.active_id!="cobra_race" or session.state.campaign.step!=0 or session.state.region_id!="harbor" or not session.state.place_id.is_empty(): return false
	var driving=session.world.driving
	if not driving.occupied or not is_instance_valid(driving.car) or driving.car.health<=0: return false
	var car=driving.car
	return car.position.distance_to(targets.ashbend_start)<85.0*UNIT and car.horizontal_velocity.length()<=20.0*UNIT and (-car.global_basis.z).dot(Vector3.FORWARD)>=.65

func _spawn_near_actors() -> void:
	for id in ["ferrugem","ashbend_resident","neco"]:
		if actors.has(id) and not is_instance_valid(actors[id]): actors.erase(id)
		var near: bool = session.world.player.position.distance_to(targets[id])<60
		if near and not actors.has(id):
			if not session.position_clear(targets[id]+Vector3.UP*.04): continue
			var actor = preload("res://scripts/Actor.gd").new()
			actor.controlled_automatically = true
			actor.identity = 7 if id == "ferrugem" else 3
			actor.position = targets[id]+Vector3.UP*.05
			session.world.add_child(actor)
			if id == "neco":
				var previous: Node = actor.visual.get_child(0)
				actor.visual.remove_child(previous)
				previous.queue_free()
				actor.visual.add_child(load("res://world/places/NecoModel.gd").new())
			actors[id] = actor
		elif not near and actors.has(id):
			if is_instance_valid(actors[id]): actors[id].queue_free()
			actors.erase(id)
	for id in ["harbor_parcel","cobra_supply","transfer_document"]:
		if props.has(id) or session.world.player.position.distance_to(targets[id])>60: continue
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(.8,.6,.7)
		box.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("a1814b")
		box.material_override = material
		box.position = targets[id]+Vector3.UP*.3
		add_child(box)
		props[id] = box

func _start_encounter(id: String, center: Vector3) -> void:
	for enemy in enemies: if is_instance_valid(enemy): enemy.queue_free()
	enemies.clear()
	encounter_id = id
	for index in (3 if id == "boss_encounter" else 2):
		var point := center+Vector3((index-1)*3,0,-4)
		if not session.position_clear(point+Vector3.UP*.05): continue
		var enemy = load("res://gameplay/CobraAgent.gd").new()
		enemy.configure(session.world.gameplay,2 if id == "boss_encounter" and index==1 else 0)
		enemy.position = point+Vector3.UP*.05
		add_child(enemy)
		enemies.append(enemy)
	if enemies.is_empty(): session.show_message("Área do encontro ocupada. Afaste-se para liberar a passagem."); encounter_id=""
func _encounter_cleared() -> bool:
	if enemies.is_empty(): return false
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.dead: return false
	return true

func begin_tow_job(job: Dictionary) -> bool:
	var identity := _tow_identity(job)
	if identity.is_empty(): return false
	if job.get("story") != true and session.state.campaign.active_id == "cobra_contact": return false
	if job.get("story") == true and not session.activities.snapshot().get("tow_contract",{}).is_empty(): return false
	if is_instance_valid(truck) and truck.health <= 0: return false
	if not tow_job.is_empty(): return identity == _tow_identity(tow_job) and is_instance_valid(truck) and is_instance_valid(cargo)
	if loaded: return false
	# All pickup coordinates belong to Harbor. Restores may retry from another
	# region, but must wait instead of spawning into that active world.
	if session.state.region_id != "harbor": return false
	unloaded_at_bay = false
	if not is_instance_valid(truck):
		truck = _spawn_tow_vehicle("towmaster",Vector3(-595,0,990)*UNIT+Vector3.UP*.12,PI)
		if truck == null: return false
		truck.vehicle_id = "neco_tow_truck"
	if not is_instance_valid(cargo):
		var kind: String = job.get("kind","local")
		var model: String = {"local":"ranch_single","special":"sport_coupe","rare":"cobra_v8","police":"police_cruiser"}.get(kind,"ranch_single")
		# Original parked slots: HarborSouthPort pickup / CobraNeighborhood workshop.
		var point := Vector3(3480,0,4160)*UNIT if kind == "local" else Vector3(8340,0,1750)*UNIT
		# A cancelled service leaves its car in the world. Reclaim only that
		# service's nearby, matching body; never delete an unrelated obstruction.
		cargo = _reusable_tow_cargo(model,point)
		if cargo == null:
			cargo = _spawn_tow_vehicle(model,point+Vector3.UP*.12,PI*.5 if kind == "local" else PI)
		if cargo == null: return false
		cargo.vehicle_id = "story_tow_vehicle"
		cargo.engine_disabled = true
	tow_job = job.duplicate(true)
	return true

func _reusable_tow_cargo(model: String, point: Vector3) -> CharacterBody3D:
	for car in session.controller.vehicles:
		if not is_instance_valid(car) or car.is_queued_for_deletion(): continue
		if car == session.world.driving.car and session.world.driving.occupied: continue
		if car.controlled or car.archetype != model or car.get_meta("region_id","") != "harbor": continue
		if car.has_meta("awaiting_ground") or car.position.distance_to(point) > 12 or car.horizontal_velocity.length() > .3: continue
		var previous: String = str(car.vehicle_id).trim_prefix("cancelled_")
		var cancelled_service: bool = str(car.vehicle_id).begins_with("cancelled_") and (previous == "story:cobra_contact" or (previous.begins_with("tow_") and previous.trim_prefix("tow_").is_valid_int()))
		if cancelled_service: return car
	return null

func _spawn_tow_vehicle(model: String, point: Vector3, yaw: float) -> CharacterBody3D:
	# Bounded local parking alternatives, checked with the production footprint
	# and ground queries before publishing ownership. Never move an existing car.
	for offset in [Vector3.ZERO,Vector3(6,0,0),Vector3(-6,0,0),Vector3(0,0,8),Vector3(0,0,-8)]:
		var candidate: Vector3 = point+Basis(Vector3.UP,yaw)*offset
		var car = session.controller.spawn_vehicle(model,candidate,yaw)
		if car == null: continue
		if not car.has_meta("awaiting_ground"): return car
		if point.distance_to(session.world.player.position) > 75:
			_reserve_tow_vehicle(car,true)
			return car
		# Only this fresh, unowned candidate is discarded, never the blocking body.
		car.collision_layer = 0
		car.collision_mask = 0
		session.controller.vehicles.erase(car)
		car.queue_free()
	return null

func _reserve_tow_vehicle(car: CharacterBody3D, alternatives: bool) -> void:
	# This is ownership of a future pickup, not an admitted physical vehicle.
	# ProductionWorld must not wake it via its generic awaiting_ground branch.
	car.remove_meta("awaiting_ground")
	car.set_meta("tow_pending",true)
	car.set_meta("tow_pending_alternatives",alternatives)
	car.collision_layer = 0
	car.collision_mask = 0
	car.set_physics_process(false)
	car.hide()

func _activate_tow_reservations() -> void:
	if session.state.region_id != "harbor" or not session.state.place_id.is_empty(): return
	for car in [truck,cargo]:
		if not is_instance_valid(car) or not car.has_meta("tow_pending"): continue
		if car.position.distance_to(session.world.player.position) > 65: continue
		var offsets: Array = [Vector3.ZERO]
		if car.get_meta("tow_pending_alternatives",false):
			offsets.append_array([Vector3(6,0,0),Vector3(-6,0,0),Vector3(0,0,8),Vector3(0,0,-8)])
		for offset in offsets:
			var point: Vector3 = car.position+Basis(Vector3.UP,car.rotation.y)*offset
			if not session.controller.vehicle_position_clear(car,point,car.rotation.y): continue
			car.place(point,car.rotation.y)
			car.remove_meta("tow_pending")
			car.remove_meta("tow_pending_alternatives")
			car.collision_layer = 4
			car.collision_mask = 7
			car.set_physics_process(true)
			car.show()
			break

func _tow_repair_safe(car: CharacterBody3D) -> bool:
	var emergency = session.world.gameplay.emergency
	if not is_instance_valid(emergency): return true
	for fire in emergency.fires:
		if not is_instance_valid(fire) or fire.is_queued_for_deletion() or fire.intensity <= 0: continue
		# Fire's damage sphere is 1.4m; include the complete vehicle footprint.
		var local: Vector3 = car.to_local(fire.global_position)
		if absf(local.x) <= car.half_width+1.4 and absf(local.z) <= car.half_length+1.4 and absf(local.y) < 3:
			session.show_message("Espere o incêndio ser apagado antes de recuperar o veículo.")
			return false
	return true

func _recover_tow_truck() -> bool:
	if session.state.region_id != "harbor" or not session.state.place_id.is_empty(): return false
	if session.world.driving.occupied or session.world.gameplay.stars > 0: return false
	if not is_instance_valid(truck) or truck.health > 0 or truck.controlled: return false
	if truck.has_meta("tow_pending"): return false
	if session.world.player.position.distance_to(truck.position) >= 5 or truck.horizontal_velocity.length() > .3: return false
	if not _tow_repair_safe(truck): return false
	# Reuse the existing body and cargo transform; never move it through obstacles.
	truck.repair()
	truck.engine_disabled = false
	session.save_game()
	session.show_message("Guincho recuperado.")
	return true

func _recover_tow_cargo() -> bool:
	if session.state.region_id != "harbor" or not session.state.place_id.is_empty(): return false
	if tow_job.is_empty() or session.world.driving.occupied or session.world.gameplay.stars > 0: return false
	if not is_instance_valid(cargo) or cargo.health > 0 or cargo.controlled: return false
	if cargo.has_meta("tow_pending"): return false
	if session.world.player.position.distance_to(cargo.position) >= 5: return false
	if loaded:
		if not is_instance_valid(truck) or truck.horizontal_velocity.length() > .3: return false
	elif cargo.horizontal_velocity.length() > .3: return false
	if not _tow_repair_safe(cargo): return false
	cargo.repair()
	cargo.engine_disabled = true
	# No campaign event/reward here: loading, delivery and Neco remain mandatory.
	session.save_game()
	session.show_message("Carro rebocado recuperado. Continue a entrega.")
	return true

func _tow_toggle() -> bool:
	if not is_instance_valid(truck) or not is_instance_valid(cargo) or absf(truck.speed)>.5 or truck.health<=0 or cargo.controlled: return false
	if truck.has_meta("tow_pending") or cargo.has_meta("tow_pending"):
		session.show_message("Libere a área de retirada para preparar o reboque.")
		return false
	if cargo.health <= 0:
		session.show_message("Recupere o carro rebocado antes de carregar ou descarregar.")
		return false
	if not loaded:
		if cargo.global_position.distance_to(truck.to_global(Vector3(0,0,truck.half_length+2)))>4:
			session.show_message("Aproxime a traseira do guincho do carro.")
			return false
		loaded = true
		unloaded_at_bay = false
		cargo.set_physics_process(false)
		cargo.collision_layer = 0
		cargo.collision_mask = 0
		if session.state.campaign.target_id()=="story_tow_vehicle": _event("story_vehicle_loaded","story_tow_vehicle")
	else:
		var point := truck.to_global(Vector3(0,.1,truck.half_length+cargo.half_length+1))
		if not session.controller.vehicle_position_clear(cargo,point,truck.rotation.y): session.show_message("Área de descarga bloqueada."); return false
		cargo.place(point,truck.rotation.y)
		cargo.collision_layer = 4
		cargo.collision_mask = 7
		cargo.set_physics_process(true)
		loaded = false
		unloaded_at_bay = cargo.position.distance_to(targets.neco_bay)<8
		if unloaded_at_bay and session.state.campaign.target_id()=="neco_bay": _event("story_vehicle_unloaded","neco_bay")
	session.save_game()
	return true
func tow_snapshot() -> Dictionary:
	return {"token":_tow_identity(tow_job),"cargo_id":cargo.archetype if is_instance_valid(cargo) else "","loaded":loaded,"unloaded_at_bay":unloaded_at_bay,"alive":is_instance_valid(cargo) and cargo.health>0,"service_position":targets.neco}
func can_finish_tow_job() -> bool:
	return not tow_job.is_empty() and not loaded and unloaded_at_bay and is_instance_valid(cargo) and not cargo.has_meta("tow_pending") and cargo.health > 0 and not cargo.controlled and cargo.position.distance_to(targets.neco_bay) < 8 and cargo.horizontal_velocity.length() < .3

func finish_tow_job() -> bool:
	if not can_finish_tow_job(): return false
	cargo.vehicle_id = "delivered_"+_tow_identity(tow_job)
	cargo.engine_disabled = false
	cargo = null
	tow_job.clear()
	unloaded_at_bay = false
	return true

func cancel_tow_job() -> bool:
	if is_instance_valid(cargo) and cargo.has_meta("tow_pending"):
		# Only an unmaterialized reservation is removed; physical cars remain.
		session.controller.vehicles.erase(cargo)
		cargo.queue_free()
		cargo = null
	if is_instance_valid(cargo):
		if cargo.controlled: return false
		if loaded:
			if not is_instance_valid(truck): return false
			if truck.horizontal_velocity.length() > .3: return false
			var point := truck.to_global(Vector3(0,.1,truck.half_length+cargo.half_length+1))
			if not session.controller.vehicle_position_clear(cargo,point,truck.rotation.y): return false
			cargo.place(point,truck.rotation.y)
		cargo.vehicle_id = "cancelled_"+_tow_identity(tow_job)
		cargo.collision_layer = 4
		cargo.collision_mask = 7
		cargo.engine_disabled = false
		cargo.set_physics_process(not cargo.has_meta("awaiting_ground"))
	cargo = null
	loaded = false
	unloaded_at_bay = false
	tow_job.clear()
	return true

static func _tow_identity(job: Dictionary) -> String:
	if job.get("story") == true: return "story:cobra_contact"
	var token: Variant = job.get("token","")
	if not token is String or not token.begins_with("tow_") or not token.trim_prefix("tow_").is_valid_int(): return ""
	if int(token.trim_prefix("tow_")) < 1: return ""
	var index: Variant = job.get("index")
	if typeof(index) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(index)) or float(index) != floorf(float(index)) or int(index) not in range(5): return ""
	var source: Dictionary = preload("res://data/catalogs/TowJobs.gd").JOBS[int(index)]
	for field in ["kind","reward","duration"]:
		if job.get(field) != source[field]: return ""
	return token

func snapshot() -> Dictionary:
	return {"version":1,"job":tow_job.duplicate(true),"loaded":loaded,"unloaded_at_bay":unloaded_at_bay,"truck":_tow_vehicle_snapshot(truck),"cargo":_tow_vehicle_snapshot(cargo)}

func _tow_vehicle_snapshot(car) -> Dictionary:
	if not is_instance_valid(car): return {}
	var result := {"archetype":car.archetype,"position":[car.position.x,car.position.y,car.position.z],"yaw":car.rotation.y,"health":car.health,"paint":car.paint_color.to_html(true)}
	if car.has_meta("tow_pending"):
		result.pending = true
		result.pending_alternatives = car.get_meta("tow_pending_alternatives",false)
	return result

static func validate_snapshot(data: Dictionary) -> bool:
	if data.get("version") != 1 or not data.get("job") is Dictionary: return false
	if not data.get("loaded") is bool or not data.get("unloaded_at_bay") is bool: return false
	for field in ["truck","cargo"]:
		var car: Variant = data.get(field)
		if not car is Dictionary: return false
		if car.is_empty(): continue
		if not car.get("pending",false) is bool or not car.get("pending_alternatives",false) is bool: return false
		if car.get("pending_alternatives",false) and not car.get("pending",false): return false
		if not car.get("archetype") is String: return false
		var spec: Dictionary = preload("res://runtime/FleetCatalog.gd").spec(car.archetype)
		if spec.is_empty(): return false
		if not car.get("position") is Array or car.position.size()!=3: return false
		for coordinate in car.position:
			if typeof(coordinate) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(coordinate)) or absf(float(coordinate))>10000: return false
		for number in ["health","yaw"]:
			if typeof(car.get(number)) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(car[number])): return false
		if car.health < 0 or car.health > float(spec.get("durability",180)): return false
		if not car.get("paint") is String or not Color.html_is_valid(car.paint): return false
	if not data.truck.is_empty() and data.truck.archetype != "towmaster": return false
	if data.job.is_empty(): return data.cargo.is_empty() and not data.loaded and not data.unloaded_at_bay
	if _tow_identity(data.job).is_empty() or data.cargo.is_empty() or data.truck.is_empty(): return false
	if data.loaded and data.unloaded_at_bay: return false
	if (data.loaded or data.unloaded_at_bay) and data.cargo.get("pending",false): return false
	return true

static func validate_ownership(data: Dictionary, active_mission: String, activity_contract: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	if data.job.is_empty(): return activity_contract.is_empty()
	if data.job.get("story") == true: return active_mission == "cobra_contact" and activity_contract.is_empty()
	return _tow_identity(data.job) == _tow_identity(activity_contract)

func restore_snapshot(data: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	if not tow_job.is_empty() or is_instance_valid(cargo) or is_instance_valid(truck): return snapshot() == data
	var restored_truck = _restore_tow_vehicle(data.truck,"neco_tow_truck",false)
	if not data.truck.is_empty() and restored_truck == null: return false
	var restored_cargo = _restore_tow_vehicle(data.cargo,"story_tow_vehicle",data.loaded)
	if not data.cargo.is_empty() and restored_cargo == null:
		if restored_truck != null:
			session.controller.vehicles.erase(restored_truck)
			restored_truck.queue_free()
		return false
	truck = restored_truck
	cargo = restored_cargo
	tow_job = data.job.duplicate(true)
	loaded = data.loaded
	unloaded_at_bay = data.unloaded_at_bay
	if is_instance_valid(cargo):
		cargo.engine_disabled = true
		if loaded:
			cargo.remove_meta("awaiting_ground")
			cargo.collision_layer = 0
			cargo.collision_mask = 0
			cargo.set_physics_process(false)
			cargo.global_transform = truck.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,1.05,1.3))
	return true

func _restore_tow_vehicle(data: Dictionary, id: String, carried: bool):
	if data.is_empty(): return null
	var point := Vector3(data.position[0],data.position[1],data.position[2])
	var car
	if carried or data.get("pending",false):
		# Cargo on the flatbed deliberately overlaps the truck, without a solid collider.
		car = preload("res://scripts/Vehicle.gd").new()
		car.archetype = data.archetype
		car.position = point
		car.rotation.y = float(data.yaw)
		car.paint_color = Color.html(data.paint)
		session.world.add_child(car)
		car.collision_layer = 0
		car.collision_mask = 0
		car.set_physics_process(false)
		session.controller.vehicles.append(car)
		car.destroyed.connect(func():
			if is_instance_valid(session.world.gameplay):
				session.world.gameplay.explode(car.global_position+Vector3.UP*.4,5.0,35.0,car,false)
				if is_instance_valid(session.world.gameplay.emergency):
					session.world.gameplay.emergency.ignite(car.global_position,car))
	else: car = session.controller.spawn_vehicle(data.archetype,point,float(data.yaw))
	if car == null: return null
	car.vehicle_id = id
	car.set_meta("region_id","harbor")
	if session.state.region_id != "harbor": car.hide(); car.set_physics_process(false)
	car.health = float(data.health)
	car.paint_color = Color.html(data.paint)
	if data.get("pending",false) or car.has_meta("awaiting_ground"):
		# Old saves defer at the exact saved position; only never-materialized
		# reservations may select an alternative pickup slot.
		_reserve_tow_vehicle(car,bool(data.get("pending_alternatives",false)))
	return car
