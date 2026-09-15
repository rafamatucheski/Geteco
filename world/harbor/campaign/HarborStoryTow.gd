extends RefCounted
## Narrative recovery uses Neco's real flatbed and collision-checked winch.
## No salvage contract, press operation, bonus payment or duplicate vehicle.
const JOBS := preload("res://world/shared/salvage/TowJobs.gd")
var controller: Node2D
var service: Node
var yard: Node2D
var vehicle: Node2D
var _loaded_once := false
var _delivered := false
var _clock := 0.0

func configure(owner_controller: Node2D) -> void:
	controller = owner_controller

func tr_text(pt: String, en: String) -> String:
	return en if TranslationServer.get_locale().begins_with("en") else pt

func start() -> void:
	_clock = 0.0
	_loaded_once = false
	_delivered = false
	yard = controller.get_tree().get_first_node_in_group("chop_shop") as Node2D
	service = yard.tow_service if yard else null
	controller.objective_position = controller.WORKSHOP

func _prepare_recovery() -> bool:
	if not is_instance_valid(service) or not is_instance_valid(service.truck):
		controller._say("Ferrugem", tr_text("O guincho ainda não chegou ao pátio do Neco. Tente falar comigo novamente daqui a pouco.", "Neco's truck hasn't reached the yard yet. Speak to me again in a moment."))
		return false
	if not yard.ledger().data.contract.is_empty() or (is_instance_valid(service.cargo) and not service.cargo.has_meta("story_tow_authorized")):
		controller._say("Ferrugem", tr_text("Termina o serviço de guincho que já está com você e volta aqui. Não vamos misturar os carros.", "Finish your current tow job and come back. We can't mix up the cars."))
		return false
	# A save restores the flatbed through its normal service. Reclaim that exact
	# narrative cargo on retry rather than generating another copy.
	if is_instance_valid(service.cargo) and service.cargo.has_meta("story_tow_authorized"):
		vehicle = service.cargo
		_loaded_once = true
	else:
		for candidate in controller.get_tree().get_nodes_in_group("vehicle"):
			if candidate.has_meta("story_tow_authorized") and candidate.get("health") > 0:
				vehicle = candidate
				break
		if not is_instance_valid(vehicle): vehicle = service.choose_target(JOBS.JOBS[0])
	if not is_instance_valid(vehicle):
		controller._say("Ferrugem", tr_text("O carro foi removido da rua. Volte ao quadro e aceite o serviço de novo para eu confirmar outro ponto de coleta.", "The car was moved off the street. Return to the board and accept the job again so I can confirm another collection point."))
		controller.fail_mission(tr_text("Carro de recuperação indisponível. O serviço pode ser tentado novamente.", "Recovery car unavailable. You can retry the job."))
		return false
	vehicle.set_meta("story_tow_authorized", true)
	vehicle.add_to_group("mission_vehicle")
	service.set_meta("story_recovery_active", true)
	vehicle.has_theft_alarm = false # Ferrugem, the customer, authorized recovery.
	if service.truck.health <= 0 and not is_instance_valid(service.cargo): service.recover_truck()
	return true

func interact() -> bool:
	if controller.active_id != "cobra_contact": return false
	var player: Node2D = controller.player
	if player.get("is_dead") == true or player.get("is_arrested") == true or player.get("is_control_disabled") == true: return false
	if controller.stage == 0:
		if controller._subject().global_position.distance_to(controller.WORKSHOP) > controller.INTERACT_DISTANCE: return false
		if controller._subject() != player:
			controller._say("Dante", tr_text("Preciso descer do carro para falar com Ferrugem.", "I need to get out to speak to Ferrugem."))
			return true
		if not _prepare_recovery(): return true
		controller._set_stage(2 if _loaded_once else 1)
		_update_destination()
		controller._say("Ferrugem", tr_text("Maciota mandou a peça? É do carro de uma cliente, parado no ponto que marquei. O motor está ruim: leva no guincho amarelo do Neco até a baia dele. Não vende nem manda para a prensa. Quando descarregar, fala com Neco e volta aqui. A ordem de serviço foi aberta pelo teu irmão.", "Maciota sent the part? It's for a customer's car, stopped at the marked point. The engine's bad: use Neco's yellow flatbed to take it to his bay. Don't sell or crush it. After unloading, speak to Neco and come back. Your brother opened the work order."))
		return true
	if controller.stage in [1, 2]:
		# The real TowService owns E while driving, including swept clearance,
		# stopped vehicle checks and unloading. Never consume that input here.
		return false
	if controller.stage == 3:
		if controller._subject() != player or player.global_position.distance_to(yard.npc.global_position) > 82: return false
		if not is_instance_valid(vehicle) or vehicle.has_meta("tow_carried") or vehicle.global_position.distance_to(yard.to_global(yard.dock)) > 65: return false
		if controller.get_node("/root/WantedManager").current_stars > 0:
			controller._say("Neco", tr_text("Some com a polícia primeiro. Não vou receber carro com viatura no portão.", "Lose the police first. I won't take delivery with a patrol at my gate."))
			return true
		_delivered = true
		service.receive_customer_repair(vehicle)
		controller._set_stage(4)
		_update_destination()
		controller._say("Neco", tr_text("Está recebido. Esse vai para reparo, não para a prensa. A cliente busca depois; pode deixar na baia que eu cuido disso. A ordem 017 tem a assinatura V. Ferraz e um pedido de motoristas para a rota da serra. Leva essa via ao Ferrugem; quero saber por que ele anda tão calado.", "Received. This one's for repair, not the press. The customer will collect it later; leave it in the bay and I'll handle it. Work order 017 has V. Ferraz's signature and a request for drivers on the mountain route. Take this copy to Ferrugem; I want to know why he's been so quiet."))
		return true
	if controller.stage == 4:
		if controller._subject() != player or player.global_position.distance_to(controller.WORKSHOP) > controller.INTERACT_DISTANCE: return false
		controller._say("Ferrugem", tr_text("É a assinatura dele. Vicente procurava gente para dirigir fora de Harbor. O último motorista não fala com desconhecido. Hoje à noite tem a prova de rua: vence seguindo os portões marcados, e eu te dou acesso à turma. Obrigado por trazer o carro inteiro.", "That's his signature. Vicente was looking for drivers outside Harbor. His last driver won't talk to strangers. Tonight is the street trial: win by following the marked gates, and I'll introduce you to the crew. Thanks for bringing the car back in one piece."))
		controller._finish()
		return true
	return false

func tick(delta: float) -> void:
	_clock += delta
	if _clock < .2 or controller.stage == 0: return
	_clock = 0.0
	if controller.stage >= 4: return
	if not is_instance_valid(vehicle) or vehicle.get("health") <= 0:
		controller.fail_mission(tr_text("O carro da cliente foi destruído. Volte ao quadro para reorganizar a recuperação.", "The customer's car was destroyed. Return to the board to arrange another recovery."))
		return
	if not is_instance_valid(service) or not is_instance_valid(service.truck) or service.truck.health <= 0:
		controller.fail_mission(tr_text("O guincho foi destruído. Neco pode recuperá-lo; depois aceite o serviço novamente.", "The tow truck was destroyed. Neco can recover it; then accept the job again."))
		return
	if vehicle == service.cargo:
		_loaded_once = true
		if controller.stage != 2: controller._set_stage(2)
	elif _loaded_once and not vehicle.has_meta("tow_carried") and vehicle.global_position.distance_to(yard.to_global(yard.dock)) <= 65 and vehicle.velocity.length() <= 8:
		if controller.stage != 3: controller._set_stage(3)
	elif controller.stage != 1:
		controller._set_stage(1)
	_update_destination()

func _update_destination() -> void:
	var point: Vector2 = controller.WORKSHOP
	match controller.stage:
		1: point = vehicle.global_position if service.truck.is_driven_by_player else service.truck.global_position
		2: point = yard.to_global(yard.dock) if service.truck.is_driven_by_player else service.truck.global_position
		3: point = yard.npc.global_position
	if point.distance_squared_to(controller.objective_position) > 1:
		controller.objective_position = point
		controller.changed.emit()
		controller.queue_redraw()

func objective_text() -> String:
	match controller.stage:
		0: return tr_text("A pé, fale com Ferrugem na oficina sobre a peça e Vicente.", "On foot, speak to Ferrugem at the workshop about the part and Vicente.")
		1:
			if is_instance_valid(service) and is_instance_valid(service.truck) and service.truck.is_driven_by_player:
				return tr_text("Recupere o carro marcado: pare com a traseira do guincho junto dele e use a interação para carregar.", "Recover the marked car: stop with the flatbed's rear beside it and interact to load.")
			return tr_text("Entre no guincho amarelo do Neco marcado no GPS. Se estiver com outra carga, descarregue-a em local livre.", "Enter Neco's yellow tow truck marked on GPS. If it carries another car, unload it in a clear space.")
		2:
			if is_instance_valid(service) and is_instance_valid(service.truck) and not service.truck.is_driven_by_player:
				return tr_text("Volte ao guincho carregado marcado no GPS. O carro da cliente continua na plataforma.", "Return to the loaded flatbed marked on GPS. The customer's car is still on its platform.")
			return tr_text("Leve o carro à baia do Neco. Pare, alinhe a traseira com a marca e use a interação para descarregar. Não use a prensa.", "Take the car to Neco's bay. Stop, align the rear with the marker and interact to unload. Do not use the press.")
		3: return tr_text("Carro descarregado. Saia do guincho e fale com Neco para receber a ordem de serviço.", "Car unloaded. Exit the truck and speak to Neco to receive the work order.")
		4: return tr_text("Volte à oficina e fale com Ferrugem sobre a ordem 017 assinada por V. Ferraz.", "Return to the workshop and speak to Ferrugem about work order 017 signed by V. Ferraz.")
	return ""

func cleanup() -> void:
	# Only release this mission's reservation. A user's unrelated tow job and
	# cargo are never discarded. Successful delivery stays protected from sale.
	if is_instance_valid(service): service.remove_meta("story_recovery_active")
	if is_instance_valid(vehicle) and _delivered:
		vehicle.remove_meta("story_tow_authorized")
	elif is_instance_valid(vehicle):
		if is_instance_valid(service) and service.cargo == vehicle:
			if not service.unload(): service._discard_cargo()
		if is_instance_valid(vehicle):
			vehicle.remove_meta("story_tow_authorized")
			vehicle.remove_from_group("mission_vehicle")
	vehicle = null
	service = null
	yard = null
