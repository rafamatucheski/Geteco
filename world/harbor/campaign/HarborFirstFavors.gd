extends RefCounted
## Versioned checkpoints keep deliveries accepted in older saves unchanged.
var mission: Node
var _dialogue_owned := false

func configure(owner_mission: Node) -> void:
	mission = owner_mission

func text(pt: String, en: String) -> String:
	return en if TranslationServer.get_locale().begins_with("en") else pt

func active() -> bool:
	return mission._flag("harbor_first_favors_v3") and not mission._flag("harbor_delivery_complete")

func begin() -> void:
	mission.campaign.set_campaign_flag(&"harbor_first_favors_v3", true)
	_story([
		["MACIOTA", "A Helena, do North Pier, liberou o pagamento de uma peça. Busca o comprovante no banco e leva ao porto. A encomenda está no ponto marcado.", "Helena at North Pier cleared payment for a part. Collect the receipt at the bank and take it to the port. The parcel is at the marked point."],
		["DANTE", "E isso me aproxima do Vicente?", "And this gets me closer to Vicente?"],
		["MACIOTA", "A peça é para Ferrugem. Teu irmão fazia serviço com ele. Faz essa entrega direito que eu te apresento. E trata bem a Helena: ela segurou as contas da oficina quando ninguém ajudou.", "The part is for Ferrugem. Your brother worked with him. Do this properly and I'll introduce you. Be kind to Helena: she kept the workshop afloat when nobody else helped."],
		["MACIOTA", "Já está tudo pago. Você não precisa gastar nem roubar nada. Banco, encomenda, depois volta falar comigo. Os 150 são pelo teu trabalho.", "It's already paid. You don't need to spend or steal anything. Bank, parcel, then come back to me. The 150 is for your work."],
	], resume)

func resume() -> void:
	if not active(): return
	if mission._flag("harbor_delivery_picked_up"):
		mission._set_phase("delivery_return", text("Volte à garagem e fale com Maciota para entregar a peça.", "Return to the garage and speak to Maciota to deliver the part."), mission.entrance.global_position)
	elif mission._flag("harbor_delivery_receipt"):
		mission._set_phase("delivery_pickup", text("Vá ao porto. A pé, use a interação junto à encomenda para retirar a peça paga.", "Go to the port. On foot, interact beside the parcel to collect the paid part."), mission._pickup_position())
	else:
		var door := bank_door()
		mission._set_phase("delivery_bank", text("Vá ao Banco North Pier. Guarde a arma e fale com Helena para retirar o comprovante.", "Go to North Pier Bank. Holster your weapon and speak to Helena to collect the receipt."), door.global_position if door else Vector2.ZERO)

func bank_room() -> Node2D:
	return mission.world.get_node_or_null("Interiors/InteriorSpaces/BankInterior") as Node2D

func bank_door() -> Node2D:
	return mission.world.get_node_or_null("District/NorthFrontage0/RobberyEntrance") as Node2D

func bank_unavailable() -> bool:
	var room := bank_room()
	if not room: return true
	if room.alarm_started or (is_instance_valid(room.aftermath) and room.aftermath.closed): return true
	return room.civilians.is_empty() or not is_instance_valid(room.civilians[0]) or room.civilians[0].get("is_dead") == true

func bank_interaction_position() -> Vector2:
	var room := bank_room()
	if room and not bank_unavailable(): return room.civilians[0].global_position
	var door := bank_door()
	return door.global_position if door else Vector2.ZERO

func interact() -> bool:
	if not active() or mission.player.get("is_dead") == true or mission.player.get("is_arrested") == true or mission.player.get("is_control_disabled") == true or not mission.player.visible: return false
	if mission.phase != "delivery_bank": return false
	var room := bank_room()
	var door := bank_door()
	if not room or not door: return false
	if bank_unavailable():
		if room.actor_inside() or mission.player.global_position.distance_to(door.global_position) > 105: return false
		if mission.get_node("/root/WantedManager").current_stars > 0:
			mission.player._show_weapon_notice(text("Despiste a polícia antes de ligar para Maciota.", "Lose the police before calling Maciota."))
			return true
		_story([
			["DANTE", "Maciota, o banco ficou sem atendimento depois da confusão. Não consigo pegar o comprovante.", "Maciota, the bank stopped serving customers after the incident. I can't collect the receipt."],
			["MACIOTA", "Sai daí. A transferência já foi feita; vou mandar a segunda via ao pessoal do porto. Retira a peça no ponto marcado e volta. Isso ainda não acabou bem para quem trabalha aí.", "Get out of there. The transfer went through; I'll send a duplicate to the port staff. Collect the part at the marked point and come back. The people working there are still dealing with the aftermath."],
		], _receipt_received)
		return true
	if not room.actor_inside() or mission.player.global_position.distance_to(bank_interaction_position()) > 82: return false
	if room.armed():
		mission.player._show_weapon_notice(text("Guarde a arma para falar com Helena.", "Holster your weapon to speak to Helena."))
		return true
	_story([
		["HELENA", "Você é o Dante? Maciota avisou. Aqui está o comprovante da peça. O porto só libera com ele.", "Are you Dante? Maciota called ahead. Here's the receipt for the part. The port needs it to release the parcel."],
		["DANTE", "Você conhece meu irmão, Vicente?", "Do you know my brother, Vicente?"],
		["HELENA", "Conheço o nome nas transferências da oficina. Ferrugem sabe mais. Só toma cuidado: tem gente cobrando duas vezes de quem já pagou uma.", "I know the name from the workshop's transfers. Ferrugem knows more. Just be careful: some people collect twice from those who already paid once."],
		["DANTE", "Vou entregar a peça. Obrigado, Helena.", "I'll deliver the part. Thank you, Helena."],
	], _receipt_received)
	return true

func _receipt_received() -> void:
	mission.campaign.set_campaign_flag(&"harbor_delivery_receipt", true)
	resume()

func finish_dialogue(done: Callable) -> void:
	_story([
		["MACIOTA", "Peça e comprovante. Tudo certo. Aqui estão os 150. Você cumpriu o combinado.", "Part and receipt. All good. Here's your 150. You kept your word."],
		["DANTE", "A Helena falou de cobrança em dobro. É o pessoal do Ferrugem?", "Helena mentioned people collecting twice. Is that Ferrugem's crew?"],
		["MACIOTA", "É o bairro dos Cobras. Ferrugem cuida dos carros; outros cuidam de cobrar. Vou avisar que você vai. No quadro está o endereço. Leva a peça e pergunta pelo Vicente.", "It's Cobra territory. Ferrugem handles cars; others handle collections. I'll tell him you're coming. His address is on the board. Take the part and ask about Vicente."],
	], done)

func _story(lines: Array, done: Callable) -> void:
	_dialogue_owned = true
	mission.story_arrival.story(lines, func():
		_dialogue_owned = false
		done.call())

func tick() -> void:
	if not active(): return
	if _dialogue_owned and (mission.player.get("is_dead") == true or mission.player.get("is_arrested") == true):
		_dialogue_owned = false
		mission._dialog.hide()
		mission._phone_audio.stop()
		mission._unlock_player()
		resume()
	if mission.phase == "delivery_bank" and bank_unavailable():
		mission.objective = text("Banco sem atendimento: saia e use a interação junto à fachada para ligar a Maciota. Despiste a polícia primeiro.", "Bank service unavailable: leave and interact by the facade to call Maciota. Lose the police first.")
