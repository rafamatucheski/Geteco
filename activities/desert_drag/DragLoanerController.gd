extends Node
## One physical workshop car per visit. Saved progress returns the driver to the
## lending point and preserves the original car; a loan never becomes property.
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const FLEET := preload("res://runtime/FleetState.gd")
const GARAGE := preload("res://runtime/desert/DesertGarageState.gd")
const ADAPTER := preload("res://gameplay/desert_cars/DesertCarAdapter.gd")
const MODELS := ["desert_faisca","desert_siroco","desert_mirage"]
const PADS := [Vector3(-910,.1,-1298),Vector3(-900,.1,-1298),Vector3(-900,.1,-1306)]
var race: Node3D
var session
var car: CharacterBody3D
var previous_car: CharacterBody3D
var return_point := Vector3.ZERO
var previous_vehicles: Array = []
var previous_region := "desert"
var _clock := 0.0
var _requesting := false
var _previous_had_pin := false
var _previous_pin: Variant

func configure(owner_race: Node3D) -> void:
	race=owner_race
	session=race.session
	set_process(false)

func _blocked(identity: String = "") -> String:
	if _requesting: return "Aguarde a entrega do carro."
	if not session.ready_for_play or session.is_transition_blocked() or session.controller.save_invalid: return "Aguarde o fim da atividade."
	if race.active or not race.open_meet.pending.is_empty(): return "Encerre a prova ou saia da fila antes de trocar de carro."
	if session.state.region_id!="desert" or not session.state.place_id.is_empty() or session.world.player.global_position.distance_to(race.staging_point)>25.0: return "Retire ou devolva o carro junto ao quadro."
	if session.world.gameplay.health<=0 or session.world.gameplay.stars>0: return "Volte à oficina em segurança."
	if session.world.driving.occupied or session.world.driving.is_body_transition_active(): return "Desembarque para retirar ou devolver o carro."
	var night: Dictionary=preload("res://activities/desert_drag/DragNightProgress.gd").current(session.state.world_state)
	# A checkpoint returns the loan, but a saved series can recover its exact
	# workshop model and installed setup on the next visit.
	if not night.is_empty() and (identity.is_empty() or night.vehicle_id!="drag_loaner_"+identity): return "Retire o mesmo carro da noite em andamento ou encerre a série no quadro."
	return ""

func open() -> bool:
	if race.active or session.modal or not session.ready_for_play: return false
	session._menu("Carro da oficina")
	var label := Label.new()
	label.text="Empréstimo gratuito. Ao carregar, você volta ao pátio com seu carro preservado."
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size=Vector2(520,52)
	session.column.add_child(label)
	if not is_instance_valid(car):
		for identity in MODELS:
			session._button("Retirar "+str(CARS.spec(identity).label),func(): _choose(identity))
	if is_instance_valid(car): session._button("Devolver carro da oficina",_return_action)
	session._button("Voltar ao quadro",func(): session.close_menu(); race.board_controller.open_board())
	return true

func _choose(identity: String) -> void:
	session.close_menu()
	var reason := _blocked(identity)
	if not reason.is_empty(): session.show_message(reason); return
	if await request(identity): session.show_message("Carro da oficina disponível junto ao quadro. Entre pela porta do motorista.")
	else: session.show_message("Libere uma vaga junto ao quadro e tente novamente.")

func request(identity: String = "desert_faisca") -> bool:
	if identity not in MODELS or not _blocked(identity).is_empty(): return false
	if is_instance_valid(car): return false
	_requesting=true
	var created: CharacterBody3D
	for point in PADS:
		if not session.controller.region.prepare_collision_at(point): continue
		created=session.world.production.spawn_vehicle(identity,point,-PI*.5)
		if not is_instance_valid(created): continue
		await get_tree().physics_frame
		if not is_instance_valid(created): continue
		if not created.get_meta("awaiting_ground",false) and session.controller.vehicle_position_clear(created,point,-PI*.5): break
		created.queue_free()
		created=null
	_requesting=false
	if not is_instance_valid(created): return false
	if not _blocked(identity).is_empty():
		created.queue_free()
		return false
	previous_car=session.world.driving.car
	session.controller.capture_player_vehicle()
	previous_vehicles=session.state.world_state.get("vehicles",[]).duplicate(true)
	previous_region=session.state.region_id
	if is_instance_valid(previous_car):
		_previous_had_pin=previous_car.has_meta("race_owned")
		_previous_pin=previous_car.get_meta("race_owned",false)
		previous_car.set_meta("race_owned",true)
	return_point=session.world.player.global_position
	car=created
	car.vehicle_id="drag_loaner_"+identity
	car.set_meta("race_owned",true)
	car.set_meta("drag_loaner",true)
	var record := GARAGE.vehicle(session.state.world_state,car.vehicle_id,car.archetype)
	ADAPTER.attach(car,record.parts)
	set_process(true)
	return true

func _return_action() -> void:
	session.close_menu()
	var reason := _blocked()
	if not reason.is_empty(): session.show_message(reason); return
	if return_car():
		session.save_game()
		session.show_message("Carro devolvido. Suas peças conquistadas continuam disponíveis nos desafios.")

func return_car() -> bool:
	if not is_instance_valid(car) or race.active or not race.open_meet.pending.is_empty(): return false
	if session.world.driving.occupied and session.world.driving.car==car: return false
	if session.world.driving.is_body_transition_active(): return false
	prepare_save()
	if session.world.driving.car==car:
		session.world.driving.car=previous_car if is_instance_valid(previous_car) else null
		if is_instance_valid(previous_car): session.world.driving._watch_car(previous_car)
	car.queue_free()
	car=null
	_release_original_pin()
	previous_car=null
	previous_vehicles.clear()
	set_process(false)
	return true

func _release_original_pin() -> void:
	if is_instance_valid(previous_car):
		if _previous_had_pin: previous_car.set_meta("race_owned",_previous_pin)
		else: previous_car.remove_meta("race_owned")
	_previous_had_pin=false
	_previous_pin=null

func prepare_save() -> void:
	if not is_instance_valid(car) or session.world.driving.car!=car: return
	# World capture normally stores the selected car. Substitute only the loan,
	# never the reward ledger, cash, owned parts, or campaign state.
	var saved := previous_vehicles.duplicate(true)
	if is_instance_valid(previous_car) and not previous_car.get_meta("garage_reward",false) and not previous_car.get_meta("residence_vehicle",false) and previous_car.vehicle_id not in ["story_tow_vehicle","neco_tow_truck","jessica_jetta_gli"]:
		var record := FLEET.capture(previous_car,previous_region)
		record.was_driven=false
		saved=[record]
	for record in saved: record.was_driven=false
	session.state.world_state.vehicles=saved
	if session.state.region_id=="desert" and session.state.place_id.is_empty():
		session.state.world_state.pedestrian={"region":"desert","position":[return_point.x,return_point.y,return_point.z]}

func save_block_reason() -> String:
	if _requesting: return "Aguarde a entrega do carro da oficina para salvar."
	if is_instance_valid(car) and session.world.driving.car==car and session.world.driving.occupied and session.state.region_id!="desert":
		return "Desembarque do carro da oficina para salvar fora do deserto."
	return ""

func _process(delta: float) -> void:
	_clock+=delta
	if _clock<.5: return
	_clock=0.0
	if not is_instance_valid(car):
		if not is_instance_valid(session.world.driving.car) and is_instance_valid(previous_car):
			session.world.driving.car=previous_car
			session.world.driving._watch_car(previous_car)
		_release_original_pin()
		previous_car=null
		previous_vehicles.clear()
		set_process(false)
		return
	if race.active or not race.open_meet.pending.is_empty(): return
	if session.world.driving.occupied and session.world.driving.car==car: return
	if session.state.region_id!="desert" or session.world.player.global_position.distance_to(car.global_position)>180.0:
		return_car()

func _exit_tree() -> void:
	_release_original_pin()
