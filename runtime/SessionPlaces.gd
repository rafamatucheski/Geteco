extends RefCounted
## Lugares da FullSession: retomar o local salvo (restore_location e o motorista salvo na rua), entrar e
## sair de salas (enter_place, leave_place, bueiros), a volta do Umbra para a calçada e o ponto de
## retorno livre. Separado em 01/11 (Onda 2 de docs/plano-divisao-arquivos-grandes-20261101.md).
## O estado (room, return_point, access_id, sewer_hatch, saved_heading...) continua na sessão; cada
## função antiga virou delegação de uma linha (as corrotinas com await), então quem chama por nome não
## muda. position_clear fica na sessão: TestSession o sobrescreve.
## `g` fica como Node, e não como o script da FullSession, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: testes sobrescrevem position_clear,
## show_message, save_game e close_menu numa subclasse da sessão e o despacho tem de continuar igual.

const PLACES := preload("res://world/places/PlaceCatalog.gd")
const SEWER_DESCENT := preload("res://gameplay/SewerHatchDescent.gd")
const SEWER_NETWORK := preload("res://world/places/sewers/SewerNetwork.gd")
const STORY_PAY := preload("res://systems/campaign/StoryPay.gd")

var g: Node

func _init(host: Node) -> void:
	g = host

func restore_location() -> void:
	var restore_blocked := false
	var place: String = g.state.place_id
	g.state.place_id = ""
	var definition := PLACES.get_definition(place)
	var previous_roof: Dictionary = g.state.world_state.get("harbor_service_roof",{})
	if not previous_roof.is_empty() and preload("res://world/editing/WorldServiceBuildings.gd").is_deleted(str(previous_roof.get("id",""))):
		definition = PLACES.get_definition(str(previous_roof.id))
	var removed_place: bool = bool(definition.get("editor_deleted",false))
	if removed_place: g.state.world_state.erase("harbor_service_roof")
	var place_matches_region: bool = place == "maciota" and g.state.region_id == "harbor"
	if not definition.is_empty(): place_matches_region = definition.get("region","") == g.state.region_id and not removed_place
	if place_matches_region:
		if not await g.enter_place(place,false): restore_blocked = true
	else:
		# Só o local se perde: Dante volta pelo ponto de retorno e o resto do save continua
		# gravável (antes isto desligava o salvamento pelo resto da sessão).
		if not place.is_empty():
			g.show_message("Local salvo incompatível com a região; retomada pelo ponto de retorno.")
		var point: Vector3 = g.world.maciota_place.exterior_return if g.state.region_id == "harbor" else g.controller.region.spawn_position
		for entry in g.controller.region.entries:
			if entry.id == g.state.checkpoint_id: point = entry.return_position
		if removed_place and definition.get("region","") == g.state.region_id: point = definition.return_position
		var fallback: Vector3 = point
		var pedestrian: Dictionary = g.state.world_state.get("pedestrian",{})
		if not removed_place and pedestrian.get("region","") == g.state.region_id:
			var coordinates: Array = pedestrian.position
			point = Vector3(coordinates[0],coordinates[1],coordinates[2])-Vector3.UP*.08
			if g.state.region_id == "harbor":
				point = preload("res://world/railway/RailwayNetwork.gd").restore_harbor_pedestrian(point+Vector3.UP*.08)-Vector3.UP*.08
		var saved_roof: Dictionary = g.state.world_state.get("harbor_service_roof",{})
		if not removed_place and not saved_roof.is_empty() and str(saved_roof.get("place","")) == "":
			var roof_return: Array = saved_roof["return"]
			point = Vector3(roof_return[0],roof_return[1],roof_return[2])-Vector3.UP*.08
		var seated: Dictionary = g._saved_garage_driver()
		if not seated.is_empty():
			var size: Array = preload("res://runtime/FleetCatalog.gd").spec(seated.archetype).bounds_size
			var parked := Vector3(seated.position[0],seated.position[1],seated.position[2])
			point = parked+Basis(Vector3.UP,float(seated.yaw))*Vector3(maxf(.65,float(size[0]))*.5+.65,0,.15)
		if g.state.region_id=="desert": point=preload("res://world/desert/north_pass/DesertNorthPassLayout.gd").restore_point(point,g.state.world_state)
		g.controller.region.set_focus(point)
		if g.cold != null: g.cold.prepare_collision_at(point)
		for i in 3: await g.get_tree().physics_frame
		if g.position_clear(point+Vector3.UP*.08): g.world.player.teleport(point+Vector3.UP*.08)
		else:
			g.controller.region.set_focus(fallback)
			if g.cold != null: g.cold.prepare_collision_at(fallback)
			for i in 3: await g.get_tree().physics_frame
			if g.position_clear(fallback+Vector3.UP*.08):
				g.world.player.teleport(fallback+Vector3.UP*.08)
				g.show_message("Local salvo ocupado. Retomada pelo ponto de retorno.")
			else: restore_blocked = true
	if not g.state.combat_state.is_empty(): g.world.gameplay.restore_state(g.state.combat_state)
	if g.state.world_state.has("mission_world"):
		if not g.mission_world.restore_snapshot(g.state.world_state.mission_world):
			g.controller.block_saving("guincho não restaurou")
			g.show_message("Não foi possível restaurar o guincho; save preservado.")
	elif g.state.campaign.active_id == "cobra_contact":
		g.mission_world.begin_tow_job({"story":true,"kind":"local"})
	await g._restore_outdoor_driver()
	if g.desert != null and g.desert.get("workshop_drive") != null:
		if not await g.desert.workshop_drive.restore_saved_driver():
			g.controller.block_saving("carro da oficina do Digo não restaurou")
			g.show_message("Não foi possível restaurar o carro da oficina; save preservado.")
	if g.service_roofs != null and not await g.service_roofs.restore_saved(): restore_blocked = true
	g.ready_for_play = true
	if g.personal_car != null: g.personal_car.refresh()
	if g.activities != null: g.activities.refresh_achievements()
	g.garage_rewards.on_location_changed()
	g.apply_outfit()
	g.refresh_routine_context()
	# O menu acabou de recuperar este slot (SessionLaunch._publish_recovery): diga o que voltou ao padrão.
	var launch: Node = g.get_node_or_null("/root/V2Launch")
	var load_notices: Array[String] = []
	var recovery_text: Variant = launch.get("recovery_notice") if launch != null else null
	if recovery_text is String and not recovery_text.is_empty():
		load_notices.append(recovery_text)
		launch.recovery_notice = ""
	# Save de antes do bônus de missão (EconomyBalance.STORY_BONUS): paga uma vez o que faltou.
	var back_pay: int = STORY_PAY.settle(g.state.campaign.snapshot(), g.state.economy)
	if back_pay > 0:
		load_notices.append(String(TranslationServer.translate("Bônus das missões já concluídas: + R$ %d")) % back_pay)
		g.world.gameplay.changed.emit()
	if not load_notices.is_empty(): g.show_message(" · ".join(load_notices))
	if g.world.gameplay.health <= 0 or restore_blocked: g.on_death()

func _saved_garage_driver() -> Dictionary:
	if g.garage_rewards == null or not g.state.place_id.is_empty(): return {}
	for record in g.garage_rewards.data.get("vehicles",{}).values():
		if record.get("was_driven",false) and record.region_id == g.state.region_id and record.place_id.is_empty(): return record
	return {}

func _restore_outdoor_driver() -> void:
	# Um save sentado retoma no carro salvo, não num checkpoint de pedestre distante.
	if not g.state.place_id.is_empty() or g.world.gameplay.health <= 0: return
	var saved: Dictionary = g.controller.starting_vehicle()
	if saved.is_empty() or not saved.get("was_driven",false) or saved.region != g.state.region_id: return
	var car: CharacterBody3D = g.world.driving.car
	var destination := Vector3(saved.position[0],saved.position[1],saved.position[2])
	var checkpoint: Vector3 = g.world.player.position
	g.controller.region.set_focus(destination)
	if g.cold != null: g.cold.prepare_collision_at(destination)
	for i in 3: await g.get_tree().physics_frame
	if not g.controller.vehicle_position_clear(car,destination,float(saved.yaw)):
		if g._restore_saved_driver_on_foot(saved): return
		g.controller.region.set_focus(checkpoint)
		return
	car.place(destination,float(saved.yaw))
	car.remove_meta("awaiting_ground")
	car.set_physics_process(true)
	for side in [-1,1]:
		var door := car.to_global(Vector3(side*(car.half_width+.65),.05,.15))
		if car.boarding_class() in ["truck", "bus"]:
			door = car.driver_door_anchor(side) + car.global_basis.x * float(side) * .11 + Vector3.UP * .01
		if not g.position_clear(door): continue
		g.world.player.teleport(door)
		# O motorista salvo é admitido antes de ready_for_play. Mantém a entrada normal
		# travada, mas deixa a animação de corpo que ele já tem terminar sob a cortina.
		g._restoring_saved_driver = true
		var restored: bool = await g.restore_garage_driver(car)
		g._restoring_saved_driver = false
		if restored: return
	if g._restore_saved_driver_on_foot(saved): return
	g.world.player.teleport(checkpoint)
	g.controller.region.set_focus(checkpoint)

func _restore_saved_driver_on_foot(saved: Dictionary) -> bool:
	# Um casco/porta bloqueado não pode mandar um save sentado para um checkpoint distante.
	# Sonda a cápsula real e o chão em volta da pose salva, incluindo saves antigos
	# sem registro de pedestre. Mantém intacta a admissão normal de embarque.
	var size: Array = preload("res://runtime/FleetCatalog.gd").spec(saved.archetype).bounds_size
	var half_width := maxf(.65,float(size[0]))*.5
	var half_length := maxf(1.0,float(size[2]))*.5
	var origin := Vector3(saved.position[0],saved.position[1],saved.position[2])
	var basis := Basis(Vector3.UP,float(saved.yaw))
	for side in [-1,1]:
		for longitudinal in [0.0,half_length+.6,-half_length-.6]:
			var point: Vector3 = origin+basis*Vector3(side*(half_width+.85),.08,longitudinal)
			if not g.position_clear(point): continue
			g.world.player.teleport(point)
			g.controller.region.set_focus(point)
			g.world.camera.initialized = false
			g.show_message("Veículo salvo bloqueado. Retomada a pé nas proximidades.")
			return true
	return false

func enter_place(id: String, autosave := true, requested_access_id := "") -> bool:
	if not _place_admission_allowed(id, autosave): return false
	var token: int = g.begin_transition("enter_place")
	if token < 0: return false
	var origin_region: String = g.state.region_id
	var origin_room: Node3D = g.room
	var was_player_locked: bool = g.world.player.input_locked
	var local_access_id: String = requested_access_id
	g.world.player.input_locked = true
	var destination: Vector3
	var candidate_room: Node3D
	var owns_candidate := false
	var candidate_return := Vector3.ZERO
	if SEWER_NETWORK.is_manhole(id):
		g.sewer_hatch = g.find_sewer_hatch(id)
		g.sewer_entry_origin = g.world.player.global_position
	if id == "maciota":
		candidate_room = g.world.maciota_place
		candidate_return = candidate_room.exterior_return
		destination = candidate_room.interior_spawn
		candidate_room.set_interior_active(true)
	else:
		var embedded_building: bool = g.building_entrance != null and g.building_entrance.handles_place(id)
		candidate_room = await g.building_entrance.prepare_room(id,autosave) if embedded_building else PLACES.create_place(id)
		if candidate_room == null:
			if SEWER_NETWORK.is_manhole(id) and g.sewer_entry_origin.is_finite():
				g.world.player.teleport(g.sewer_entry_origin)
				g._close_sewer_hatch_for_transition(token)
				g.sewer_entry_origin = Vector3.ZERO
			g.restore_transition_player_lock(was_player_locked,token)
			g.finish_transition(token)
			return false
		owns_candidate = true
		if not embedded_building:
			if candidate_room.has_method("prepare_session"): candidate_room.prepare_session(g,autosave)
			candidate_room.position = Vector3(0,0,-2400)
			g.world.add_child(candidate_room)
		candidate_return = candidate_room.definition.return_position
		for entry in g.controller.region.entries:
			if entry.id == local_access_id: candidate_return = entry.return_position
		destination = candidate_room.spawn_position
		if embedded_building and g.building_entrance.walking_admission:
			destination = g.world.player.global_position-Vector3.UP*.04
	load("res://world/editing/WorldInteriorEdits.gd").apply_saved(candidate_room,id)
	g.controller.region.set_focus(candidate_return)
	for i in 2:
		await g.get_tree().physics_frame
		if not g.owns_transition(token) or g.state.region_id != origin_region or not g.state.place_id.is_empty() or g.room != origin_room or g.world.driving.occupied or g.world.gameplay.health <= 0 or not is_instance_valid(candidate_room) or not preload("res://runtime/ShopSafety.gd").admission_allowed(id, g.world.gameplay.stars):
			g._discard_place_candidate(candidate_room,owns_candidate)
			g.controller.region.set_focus(g.world.player.global_position)
			if SEWER_NETWORK.is_manhole(id) and g.sewer_entry_origin.is_finite():
				g.world.player.teleport(g.sewer_entry_origin)
				g._close_sewer_hatch_for_transition(token)
				g.sewer_entry_origin = Vector3.ZERO
			g.restore_transition_player_lock(was_player_locked,token)
			g.finish_transition(token)
			return false
	destination = g._garage_restore_spawn(id,destination,candidate_room)
	if not destination.is_finite() or not g.position_clear(destination+Vector3.UP*.04):
		g._discard_place_candidate(candidate_room,owns_candidate)
		g.controller.region.set_focus(g.world.player.global_position)
		if SEWER_NETWORK.is_manhole(id) and g.sewer_entry_origin.is_finite():
			g.world.player.teleport(g.sewer_entry_origin)
			g._close_sewer_hatch_for_transition(token)
		g.restore_transition_player_lock(was_player_locked,token)
		g.finish_transition(token)
		g.show_message("Entrada bloqueada.")
		return false
	# Bueiro: Dante anda até a borda, a tampa desliza e ele desce a escada antes do véu cobrir a troca.
	# Loading a saved interior admits Dante directly; it is not a street approach.
	if not await _descend_into_sewer(id, token, candidate_room, owns_candidate, was_player_locked): return false
	# Lojas com acesso a pé têm a própria câmera; nas demais portas a sala já foi
	# admitida e o véu cobre só a troca, entre a aproximação e a revelação.
	var animated: bool = autosave and not g._uses_walkup_access(id)
	if animated:
		var door_focus: Vector3 = g.world.player.global_position + Vector3.UP * 1.2
		g.world.camera.focus_on_transition(door_focus, maxf(8.0, g.world.camera.size * 0.78), g.world.camera.STORE_FOCUS_OFFSET, 0.42)
		await g.get_tree().create_timer(0.12).timeout
		await g.door_transition.fade_to(1.0, 0.30)
		if not g.owns_transition(token) or g.state.region_id != origin_region or not g.state.place_id.is_empty() or g.room != origin_room or g.world.driving.occupied or g.world.gameplay.health <= 0 or not is_instance_valid(candidate_room) or not preload("res://runtime/ShopSafety.gd").admission_allowed(id, g.world.gameplay.stars):
			g._discard_place_candidate(candidate_room,owns_candidate)
			g.controller.region.set_focus(g.world.player.global_position)
			g.world.camera.clear_store_focus()
			g.world.camera._process(0.0)
			if SEWER_NETWORK.is_manhole(id) and g.sewer_entry_origin.is_finite():
				g.world.player.teleport(g.sewer_entry_origin)
				g._close_sewer_hatch_for_transition(token)
				g.sewer_entry_origin = Vector3.ZERO
			await g.door_transition.fade_to(0.0, 0.22)
			g.restore_transition_player_lock(was_player_locked,token)
			g.finish_transition(token)
			return false
	_admit_into_place(id, token, candidate_room, candidate_return, local_access_id, destination)
	# Recibos antes de a tela clarear: depois do fade, a arma e o dinheiro já coletados apareciam na sala
	# por 0,34 s e só então sumiam (reentrada no esconderijo do Vértice, test_vertice_hideout).
	if id != "maciota": g._update_reward()
	if animated: await g.door_transition.fade_to(0.0, 0.34)
	g.restore_transition_player_lock(was_player_locked,token)
	if id != "maciota":
		g._install_service_npc()
		g._update_reward()
	if g.room.has_method("on_session_entered"): g.room.on_session_entered(g)
	if g.building_entrance != null and g.building_entrance.handles_place(id): g.building_entrance.entered()
	g.finish_transition(token)
	g.arrival.on_location_changed()
	g.garage_rewards.on_location_changed()
	g.refresh_routine_context()
	g.sync_dispatch_location()
	if autosave: g.save_game()
	if g.upside_world != null: g.upside_world.arm_entry(id, not autosave)
	return true

## Guardas de enter_place antes de abrir a transição: cada recusa avisa o motivo, como antes.
func _place_admission_allowed(id: String, autosave: bool) -> bool:
	if g.is_transition_blocked() or g.world.driving.occupied or not g.state.place_id.is_empty() or is_instance_valid(g.room) or g.world.player.input_locked: return false
	if g.world.player.get_meta("player_air_busy",false): return false
	if not preload("res://runtime/ShopSafety.gd").admission_allowed(id, g.world.gameplay.stars):
		g.show_message("Perca a polícia antes de entrar.")
		return false
	var definition := PLACES.get_definition(id)
	if definition.get("editor_deleted",false): return false
	if id == "maciota":
		if g.state.region_id != "harbor": return false
	elif definition.is_empty() or (definition.get("region","") != g.state.region_id and not definition.get("any_region",false)):
		g.show_message("Este acesso não pertence à região atual.")
		return false
	if autosave and g.garage_rewards != null and not g.garage_rewards.can_enter(id):
		g.show_message("A garagem abre entre 1h e 5h.")
		return false
	if id == "harbor_bank" and not g.robberies.can_enter_bank():
		g.show_message("O banco está fechado para investigação.")
		return false
	if id == "cobra_leader_house" and not g.state.campaign.has_progress("cobra_finale") and not (g.state.campaign.active_id == "cobra_finale" and g.state.campaign.step>=6):
		g.show_message("Takeshi ainda não liberou o acesso à casa.")
		return false
	if g.activities != null and not g.activities.can_enter_home(id):
		g.show_message("Esta casa ainda não é sua.")
		return false
	return true

## Desce o bueiro andando (a tampa desliza e Dante desce a escada) antes do véu; false se a descida
## foi interrompida, já com a sala candidata descartada e a transição devolvida.
func _descend_into_sewer(id: String, token: int, candidate_room: Node3D, owns_candidate: bool, was_player_locked: bool) -> bool:
	if g.ready_for_play and SEWER_NETWORK.is_manhole(id) and is_instance_valid(g.sewer_hatch):
		var descent: Node = SEWER_DESCENT.new()
		descent.setup(g.world.player, g.sewer_hatch, func() -> bool: return g.owns_transition(token) and g.world.gameplay.health > 0)
		if descent.can_run():
			g.add_child(descent)
			var descended: bool = await descent.descend()
			descent.queue_free()
			if not descended:
				g._discard_place_candidate(candidate_room,owns_candidate)
				g.controller.region.set_focus(g.world.player.global_position)
				if g.sewer_entry_origin.is_finite():
					g.world.player.teleport(g.sewer_entry_origin)
					g._close_sewer_hatch_for_transition(token)
					g.sewer_entry_origin = Vector3.ZERO
				g.restore_transition_player_lock(was_player_locked,token)
				g.finish_transition(token)
				return false
		else:
			descent.free()
	return true

## A troca em si, sob o véu: a sala vira a atual, o local e o checkpoint são gravados, Dante é posto
## no ponto de entrada e a câmera passa a enquadrar a sala; o bueiro de entrada fecha.
func _admit_into_place(id: String, token: int, candidate_room: Node3D, candidate_return: Vector3, local_access_id: String, destination: Vector3) -> void:
	g.saved_heading = g.world.camera.heading
	g.saved_size = g.world.camera.target_size
	g.room = candidate_room
	g.return_point = candidate_return
	g.access_id = local_access_id
	g.state.set_location(g.state.region_id,id)
	if id == "cobra_leader_house" and g.state.campaign.active_id == "cobra_finale" and g.state.campaign.step == 6:
		g.mission_world._event("leader_house_entered","cobra_leader_house")
	g.state.checkpoint_id = local_access_id if not local_access_id.is_empty() else id
	g.world.player.teleport(destination+Vector3.UP*.04)
	g.sync_location_presentation()
	g.anchor.position = g.room.camera_target
	g.world.camera.clear_store_focus()
	g.world.camera.target = g.anchor
	g.world.camera.offset = Vector3(0,18,15)
	g.world.camera.heading = 0
	g.world.camera.target_size = g.room.camera_size
	g.world.camera.size = g.room.camera_size
	g.world.camera.locked = true
	g.world.camera.initialized = false
	g.world.camera._process(1)
	if SEWER_NETWORK.is_manhole(id) and is_instance_valid(g.sewer_hatch):
		g._close_sewer_hatch_for_transition(token)
		g.sewer_hatch = null
		g.sewer_entry_origin = Vector3.ZERO

func complete_upside_return(provider: Node, illusion_token: int) -> bool:
	# A ilusão é dona da cortina e da transição; este adaptador cuida da admissão no
	# mundo real e reaproveita a transação comum de saída de sala/NPC/câmera.
	if provider != g.upside_world or not provider.owns(illusion_token) or g.state.place_id != "harbor_haunted_house": return false
	var original_return: Vector3 = g.return_point
	var trace := {"result":"searching","attempts":[]}
	provider.set_meta("return_trace",trace)
	for candidate: Vector3 in provider.return_candidates():
		if not candidate.is_finite() or candidate.distance_to(original_return) < 35.0: continue
		g.return_point = candidate - Vector3.UP * .08
		g.controller.region.set_focus(candidate)
		g.controller.region.prepare_collision_at(candidate)
		await g.get_tree().physics_frame
		await g.get_tree().physics_frame
		if not provider.owns(illusion_token) or g.world.gameplay.health <= 0 or g.rescue_pending or g.arrest_pending: return false
		var attempt: Dictionary = {"point":str(candidate),"clear":g._upside_landing_clear(candidate)}
		trace.attempts.append(attempt)
		if not attempt.clear: continue
		if provider._released:
			if not provider.prepare_departure_retry(illusion_token): return false
		elif not provider.release_for_return(illusion_token):
			trace.result = "room_blocked"
			g.return_point = original_return
			g.controller.region.set_focus(original_return)
			return false
		var departed: bool = await g.leave_place()
		attempt["departed"] = departed
		attempt["place_after"] = g.state.place_id
		attempt["generation"] = g.transition_generation
		if departed:
			if not provider.finish_return(illusion_token):
				trace.result = "completion_interrupted"
				return false
			trace.result = "returned"
			g.close_menu()
			g.save_game()
			return true
		# Um pedestre ou sólido recém-carregado pode ocupar a calçada escolhida
		# durante o fade normal da porta. Mantém a nossa cortina e tenta outro candidato;
		# abortar aqui deixava o visitante vivo preso bêbado dentro do Umbra.
		if not provider.owns(illusion_token) or g.state.place_id != "harbor_haunted_house" or g.world.gameplay.health <= 0 or g.rescue_pending or g.arrest_pending or not g.transition_kind.is_empty(): return false
		g.world.player.input_locked = true
	trace.result = "all_candidates_blocked"
	g.return_point = original_return
	g.controller.region.set_focus(original_return)
	# Uma saída recusada já devolveu o nosso token de transição. Solta só
	# a nossa trava de entrada restante antes que o runtime cancele na sala segura.
	if provider._released and provider.owns(illusion_token) and g.transition_kind.is_empty(): g.close_menu()
	return false

func _upside_landing_clear(point: Vector3) -> bool:
	# Só calçadas públicas escritas, cápsula inteira, superfície de apoio plana
	# e uma margem contra veículos vivos próximos ou se aproximando.
	if not g.position_clear(point): return false
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * .25, point - Vector3.UP * .45, 1)
	var ground: Dictionary = g.world.get_world_3d().direct_space_state.intersect_ray(query)
	if ground.is_empty() or ground.normal.y < .85 or absf(ground.position.y - point.y) > .25: return false
	for vehicle in g.controller.vehicles:
		if not is_instance_valid(vehicle): continue
		var offset: Vector3 = vehicle.global_position - point
		offset.y = 0.0
		var future: Vector3 = vehicle.global_position + vehicle.velocity * .75 - point
		future.y = 0.0
		if offset.length_squared() < 12.25 or future.length_squared() < 12.25: return false
	return true

func leave_place() -> bool:
	if g.is_transition_blocked() or g.state.place_id.is_empty() or not is_instance_valid(g.room): return false
	if g.service_roofs != null and g.service_roofs.is_active(): g.service_roofs.clear(true)
	var token: int = g.begin_transition("leave_place")
	if token < 0: return false
	var leaving_room: Node3D = g.room
	var was_player_locked: bool = g.world.player.input_locked
	var was_sewer_exit: bool = SEWER_NETWORK.is_manhole(g.state.place_id)
	if SEWER_NETWORK.is_manhole(g.state.place_id):
		g.sewer_hatch = g.find_sewer_hatch(g.state.place_id)
		if is_instance_valid(g.sewer_hatch):
			g.world.player.input_locked = true
	var continuous_departure: bool = g.building_entrance != null and g.building_entrance.handles_place(g.state.place_id) and g.building_entrance.walking_departure
	# Reconstrói o apoio exterior antes de admitir um ator vindo de uma sala remota.
	if not continuous_departure:
		g.world.player.input_locked = true
		g.controller.region.prepare_collision_at(g.return_point)
		g.controller.region.set_focus(g.return_point)
		for i in 3: await g.get_tree().physics_frame
		if not g.owns_transition(token) or g.room != leaving_room or g.world.gameplay.health <= 0:
			g.restore_transition_player_lock(was_player_locked,token)
			g.finish_transition(token)
			return false
	var leaving_return: Vector3 = g.world.player.global_position-Vector3.UP*.08 if continuous_departure else g._clear_return_point(g.state.place_id, g.return_point)
	if continuous_departure and not g.position_clear(g.world.player.global_position): leaving_return = Vector3.INF
	g.world.player.input_locked = true
	if not leaving_return.is_finite():
		if is_instance_valid(g.sewer_hatch):
			g.sewer_hatch.set_open_amount(0.0)
			g.sewer_hatch = null
		g.world.player.input_locked = was_player_locked
		g.finish_transition(token)
		g.show_message("Passagem ocupada. Aguarde.")
		return false
	var animated: bool = not g._uses_walkup_access(g.state.place_id)
	if animated:
		var exit_focus: Vector3 = leaving_room.exit_position + Vector3.UP * 0.8
		g.world.camera.focus_on_transition(exit_focus, maxf(6.0, g.world.camera.size * 0.82), g.world.camera.offset, 0.38)
		await g.get_tree().create_timer(0.10).timeout
		await g.door_transition.fade_to(1.0, 0.28)
		leaving_return = g._clear_return_point(g.state.place_id, g.return_point)
		if not g.owns_transition(token) or g.world.gameplay.health <= 0 or g.room != leaving_room or not leaving_return.is_finite():
			g.world.camera.clear_store_focus()
			g.world.camera._process(0.0)
			await g.door_transition.fade_to(0.0, 0.22)
			if is_instance_valid(g.sewer_hatch):
				g.sewer_hatch.set_open_amount(0.0)
				g.sewer_hatch = null
			g.restore_transition_player_lock(was_player_locked,token)
			g.finish_transition(token)
			if not leaving_return.is_finite(): g.show_message("Passagem ocupada. Aguarde.")
			return false
	g.controller.region.set_focus(leaving_return)
	if g.state.place_id=="harbor_bank": g.robberies.bank_departed()
	if g.state.place_id=="remote_coal_mine" and g.mining != null and is_instance_valid(g.mining.raid): g.mining.raid.departed()
	if g.building_entrance != null: g.building_entrance.departed(leaving_room)
	if leaving_room == g.world.maciota_place: leaving_room.set_interior_active(false)
	else: leaving_room.queue_free()
	g._clear_service_npcs()
	g.room = null
	g.state.set_location(g.state.region_id)
	g.world.player.teleport(leaving_return+Vector3.UP*.08)
	g.sync_location_presentation()
	# Saída do bueiro: Dante reaparece no fundo do poço com a tampa aberta e sobe a escada depois do véu abrir.
	var ascent: Node
	if was_sewer_exit and is_instance_valid(g.sewer_hatch):
		ascent = SEWER_DESCENT.new()
		ascent.setup(g.world.player, g.sewer_hatch, func() -> bool: return g.owns_transition(token) and g.world.gameplay.health > 0)
		if ascent.can_run():
			g.add_child(ascent)
			ascent.prepare_exit()
		else:
			ascent.free()
			ascent = null
	if g.state.place_id.is_empty() and is_instance_valid(g.sewer_hatch) and ascent == null:
		g._close_sewer_hatch_after_exit(g.sewer_hatch)
		g.sewer_hatch = null
	g.world.camera.target = g.world.player
	g.world.camera.offset = g.world.camera.EXTERIOR_OFFSET
	g.world.camera.heading = g.saved_heading
	g.world.camera.target_size = g.saved_size
	g.world.camera.locked = false
	g.world.camera.initialized = false
	g.world.camera._process(1)
	if animated:
		g.world.camera.reveal_exterior(g.world.player.global_position, maxf(8.0, g.saved_size * 0.78), g.saved_size, 0.42)
		await g.door_transition.fade_to(0.0, 0.42)
		g.world.camera.clear_store_focus()
	if ascent != null:
		await ascent.ascend(leaving_return)
		ascent.queue_free()
		if is_instance_valid(g.sewer_hatch):
			g._close_sewer_hatch_after_exit(g.sewer_hatch)
			g.sewer_hatch = null
		g.world.player.teleport(leaving_return+Vector3.UP*.08)
	g.world.player.input_locked = was_player_locked
	g.finish_transition(token)
	g.close_menu()
	g.arrival.on_location_changed()
	g.garage_rewards.on_location_changed()
	g.refresh_routine_context()
	g.sync_dispatch_location()
	g.save_game()
	return true

func find_sewer_hatch(place_id := "harbor_sewer") -> Node3D:
	if g.controller == null or g.controller.region == null: return null
	var target := Vector2(1182.0, 2114.0) / 16.0
	if place_id != "harbor_sewer":
		var exterior: Vector3 = PLACES.get_definition(place_id).get("exterior_position", Vector3.ZERO)
		target = Vector2(exterior.x, exterior.z)
	var best: Node3D
	var best_distance := 2.0
	for chunk in g.controller.region.get_children():
		for node in chunk.find_children(place_id, "Node3D", true, false):
			var distance := Vector2(node.global_position.x, node.global_position.z).distance_to(target)
			if distance < best_distance:
				best_distance = distance
				best = node
	return best

func _close_sewer_hatch_for_transition(token: int) -> void:
	if not is_instance_valid(g.sewer_hatch) or not g.sewer_hatch.has_method("set_open_amount"): return
	if g.owns_transition(token): g.sewer_hatch.set_open_amount(0.0)

func _close_sewer_hatch_after_exit(hatch: Node3D) -> void:
	if is_instance_valid(hatch): hatch.set_open_amount(0.0)

func _clear_return_point(place_id: String, desired: Vector3) -> Vector3:
	if g.upside_world != null and g.upside_world.busy() and g.upside_world._released and place_id == "harbor_haunted_house":
		# O retorno pertence a outra fachada. Revalida a calçada escrita exata dela,
		# incluindo veículos vivos, em vez de deslocar a partir do Umbra.
		return desired if g._upside_landing_clear(desired + Vector3.UP * .08) else Vector3.INF
	# Mantém o retorno escrito da V1 primeiro. Um pedestre em streaming ou uma borda de fachada
	# não pode prender o jogador lá dentro para sempre, então testa alguns pontos pequenos mais adiante
	# na mesma aproximação exterior antes de recusar a transição.
	if g.position_clear(desired + Vector3.UP * .08): return desired
	var outward := Vector3.FORWARD
	var definition: Dictionary = {}
	if place_id == "maciota":
		outward = desired - g.world.maciota_place.entry_position
	else:
		definition = PLACES.get_definition(place_id)
		if g.weapon_shop_entrance != null and g.weapon_shop_entrance.handles_place(g.access_id):
			definition = g.weapon_shop_entrance._definition_for(g.access_id)
		if not definition.is_empty(): outward = desired - definition.exterior_position
	outward.y = 0
	if outward.length_squared() < .01: outward = Vector3.FORWARD
	outward = outward.normalized()
	var side := Vector3(-outward.z, 0, outward.x)
	for offset in [outward * .75, outward * 1.5, side * .8 + outward * .75, -side * .8 + outward * .75]:
		var candidate: Vector3 = desired + offset
		if g.position_clear(candidate + Vector3.UP * .08): return candidate
	for offset: Vector3 in definition.get("return_clearance_offsets",[]):
		var candidate: Vector3 = desired + offset
		if g.position_clear(candidate + Vector3.UP * .08): return candidate
	return Vector3.INF

func sync_dispatch_location() -> void:
	if is_instance_valid(g.world.dispatch):
		g.world.dispatch.player_position_override = g.return_point if not g.state.place_id.is_empty() else Vector3.INF
