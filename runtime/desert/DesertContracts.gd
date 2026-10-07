extends Node3D
## Uses existing residents and physical relics; no extra population or frame loop.
const STATE := preload("res://runtime/desert/DesertContractState.gd")
const CONTACTS := preload("res://runtime/desert/DesertCampaign.gd").LOCATIONS
const RELICS := preload("res://world/desert/expansion/DesertRelics.gd")
const TITLES := {"parts":"Peças na estrada","rail":"O último ramal"}
var session

func configure(owner_session) -> void:
	session=owner_session
	name="DesertContracts"

func _available() -> bool:
	return session!=null and session.ready_for_play and session.state.region_id=="desert" and session.state.place_id.is_empty() and not session.modal and not get_tree().paused and not session.is_transition_blocked() and not session.desert.busy() and not session.world.driving.occupied and not session.world.driving.is_body_transition_active() and session.world.gameplay.health>0 and not session.world.player.dead and not session.world.player.input_locked and session.world.player.is_on_floor()

func step_definition(id: String, step: int) -> Dictionary:
	if id=="parts":
		match step:
			0: return {"contact":"bia","label":"Aceitar entrega de peças · R$ 1.200","objective":"Retire as peças com Bia, na oficina do Digo."}
			1: return {"contact":"raul","label":"Entregar peças a Raul","objective":"Leve as peças a Raul no encontro da arrancada."}
			2: return {"contact":"bia","label":"Entregar recibo e receber R$ 1.200","objective":"Volte à Bia com o recibo de Raul."}
	if id=="rail":
		match step:
			0: return {"contact":"raul","label":"Aceitar investigação da ferrovia · R$ 2.200","objective":"Converse com Raul no encontro da arrancada."}
			1: return {"site":0,"label":"Conferir livro de despachos","objective":"Procure o livro de despachos na antiga estação."}
			2: return {"site":2,"label":"Comparar lacre da carga","objective":"Compare o registro com a carga do vagão descarrilado."}
			3: return {"contact":"raul","label":"Entregar investigação e receber R$ 2.200","objective":"Leve a identificação da carga de volta a Raul."}
	return {}

func _near(definition: Dictionary) -> bool:
	var point: Vector3=session.world.player.global_position
	if definition.has("contact"):
		return session.desert.story.nearest_action().get("target","")==definition.contact
	if not definition.has("site"): return false
	var site: Dictionary=RELICS.secrets()[int(definition.site)]
	return point.distance_to(site.position)<1.7 and session.desert.discoveries._line_clear(point,site.target)

func nearest_action() -> Dictionary:
	if not _available(): return {}
	var state:=STATE.data(session.state.world_state)
	for id in TITLES:
		var definition:=step_definition(id,int(state[id]))
		if definition.has("site") and _near(definition):
			return {"id":"desert","target":"contract:"+id,"label":definition.label}
	return {}

func perform(action: Dictionary) -> bool:
	if action.is_empty() or nearest_action()!=action: return false
	var id:=str(action.target).trim_prefix("contract:")
	return _advance(id,int(STATE.data(session.state.world_state)[id]))

func open_contact(contact: String) -> bool:
	if contact not in ["bia","raul"] or not _available(): return false
	var state:=STATE.data(session.state.world_state)
	session._menu("Bia" if contact=="bia" else "Raul")
	session._button("Conversar",func():
		session.close_menu()
		session.desert.story.perform(contact,false))
	for id in TITLES:
		var step:=int(state[id])
		var definition:=step_definition(id,step)
		if definition.get("contact","")==contact:
			session._button(str(definition.label),_choose.bind(id,step))
		elif step>0 and step<int(STATE.LAST[id]) and state.active!=id:
			session._button("Acompanhar: "+str(TITLES[id]),_track.bind(id))
	if not str(state.active).is_empty(): session._button("Acompanhar história principal",_track.bind(""))
	if is_instance_valid(session.desert.extras): session.desert.extras.append_tracking_buttons()
	session._button("Voltar",session.close_menu)
	return true

func _track(id: String) -> void:
	session.close_menu()
	if not _available(): return
	if is_instance_valid(session.desert.extras): session.desert.extras.stop_tracking()
	STATE.track(session.state.world_state,id)
	session.save_game()

func _choose(id: String, expected: int) -> void:
	session.close_menu()
	_advance(id,expected)

func _advance(id: String, expected: int) -> bool:
	if not _available() or not _near(step_definition(id,expected)): return false
	var result:=STATE.advance(session.state.world_state,session.state.economy,id,expected)
	if not result.get("ok",false):
		session.show_message("Não foi possível concluir agora. Libere espaço na carteira e tente novamente.")
		return false
	if is_instance_valid(session.desert.extras): session.desert.extras.stop_tracking()
	session.save_game()
	var lines: Array=[]
	if id=="parts":
		match expected:
			0: lines=[{"speaker":"Bia","message":"Raul está no encontro da arrancada esperando estas juntas e correias. Leva para ele? Traga o recibo e te pago mil e duzentos."}]
			1: lines=[{"speaker":"Raul","message":"Era o que faltava para tirar o caminhão do pátio. Aqui está o recibo. Diz à Bia que chegou tudo certo."}]
			2: lines=[{"speaker":"Bia","message":"Recibo conferido. Seus mil e duzentos, como combinado. Valeu, Dante."}]
	else:
		match expected:
			0: lines=[{"speaker":"Raul","message":"Sumiu uma carga antes de a ferrovia fechar. Confira o livro de despachos na estação e os lacres do vagão que ficou no deserto. Pago dois mil e duzentos se conseguir identificar de quem era."}]
			1: lines=[{"speaker":"Dante","message":"O registro tem uma emenda: lote 47, peças de irrigação. Vou comparar com os lacres do vagão."}]
			2: lines=[{"speaker":"Dante","message":"Lote 47. O lacre foi cortado, mas as peças ficaram aqui. Raul vai saber a quem devolver. Não é a carga do Vicente."}]
			3: lines=[{"speaker":"Raul","message":"Esse lote era da cooperativa. Vou organizar a retirada. Você resolveu uma dívida antiga; aqui estão os dois mil e duzentos."}]
	session.show_dialogue(lines)
	return true

func objective() -> String:
	var state:=STATE.data(session.state.world_state)
	var id:=str(state.active)
	return "" if id.is_empty() else str(TITLES[id])+": "+str(step_definition(id,int(state[id])).get("objective",""))

func target_position() -> Vector3:
	var state:=STATE.data(session.state.world_state)
	var id:=str(state.active)
	if id.is_empty(): return Vector3.ZERO
	var definition:=step_definition(id,int(state[id]))
	if definition.has("contact"): return CONTACTS[definition.contact]
	return RELICS.secrets()[int(definition.site)].position
