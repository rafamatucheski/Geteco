extends Node3D
const STATE := preload("res://runtime/desert/community/DesertCommunityState.gd")
const SITE := preload("res://world/desert/community/DesertCommunitySite.gd")
const RELICS := preload("res://world/desert/expansion/DesertRelics.gd")
var session
var _clock:=0.0

func configure(owner_session) -> void:
	session=owner_session
	name="DesertCommunity"
	refresh_visuals()

func _process(delta: float) -> void:
	_clock+=delta
	if _clock<.4: return
	_clock=0.0
	if is_instance_valid(session) and session.ready_for_play: refresh_visuals()

func refresh_visuals() -> void:
	if not is_inside_tree() or not is_instance_valid(session): return
	var step:=int(STATE.data(session.state.world_state).step)
	for site in get_tree().get_nodes_in_group(SITE.GROUP):
		if not site.is_queued_for_deletion(): SITE.set_step(site,step)

func _available() -> bool:
	if not is_instance_valid(session) or not session.ready_for_play: return false
	if session.state.region_id!="desert" or not session.state.place_id.is_empty(): return false
	if session.modal or get_tree().paused or session.is_transition_blocked() or session.desert.busy(): return false
	var world=session.world
	if world.driving.occupied or world.driving.is_body_transition_active() or world.gameplay.health<=0: return false
	return not world.player.dead and not world.player.input_locked and world.player.is_on_floor()

func step_definition(step: int) -> Dictionary:
	match step:
		0: return {"point":SITE.RADIO,"target":SITE.ORIGIN+Vector3(.29,.97,.18),"label":"Rádio da cooperativa · Santa Lua","objective":"Fale com Joana pelo rádio junto à torre de Santa Lua."}
		1: return {"point":RELICS.secrets()[2].position,"target":RELICS.secrets()[2].target,"label":"Recolher conjunto de irrigação","objective":"Recupere o conjunto de irrigação na carga do vagão."}
		2: return {"point":SITE.PUMP,"target":SITE.ORIGIN+Vector3(.82,.7,0),"label":"Instalar conjunto de irrigação","objective":"Instale o conjunto na bomba junto à torre de Santa Lua."}
		3: return {"point":SITE.VALVE,"target":SITE.ORIGIN+Vector3(-2.65,1.12,0),"label":"Abrir válvula de abastecimento","objective":"Abra a válvula ao lado da bomba para abastecer os canteiros."}
		4: return {"point":SITE.RADIO,"target":SITE.ORIGIN+Vector3(.29,.97,.18),"label":"Confirmar abastecimento · R$ 1.800","objective":"Avise Joana pelo rádio e receba R$ 1.800."}
	return {}

func nearest_action() -> Dictionary:
	if not _available(): return {}
	var step:=int(STATE.data(session.state.world_state).step)
	var definition:=step_definition(step)
	if definition.is_empty(): return {}
	var point: Vector3=session.world.player.global_position
	if point.distance_to(definition.point)>1.35: return {}
	if not session.desert.discoveries._line_clear(point,definition.target): return {}
	return {"id":"desert","target":"community:"+str(step),"label":definition.label}

func perform(action: Dictionary) -> bool:
	if action.is_empty() or nearest_action()!=action: return false
	var step:=int(STATE.data(session.state.world_state).step)
	if step==0 and not STATE.unlocked(session.state.world_state):
		session.show_dialogue([{"speaker":"Joana · rádio","message":"A bomba parou, e as peças da cooperativa ficaram num vagão perdido. Raul, no encontro da arrancada, está procurando alguém para descobrir o que houve com essa carga."}])
		return true
	var result:=STATE.advance(session.state.world_state,session.state.economy,step)
	if not result.get("ok",false):
		session.show_message("Não foi possível receber agora. Libere espaço na carteira e tente novamente.")
		return true
	preload("res://runtime/desert/DesertContractState.gd").track(session.state.world_state,"")
	preload("res://gameplay/mining/jobs/MiningYardJobState.gd").pause(session.state.world_state)
	refresh_visuals()
	session.save_game()
	var lines: Array=[]
	match step:
		0: lines=[{"speaker":"Joana · rádio","message":"Raul contou que você identificou nosso lote. Sou Joana, da cooperativa de Santa Lua. A retirada pesada já está encaminhada; falta o conjunto pequeno de acoplamento que ficou na caixa aberta. Traga do vagão, instale na bomba e abra a válvula. Reservamos mil e oitocentos pelo serviço."}]
		1: lines=[{"speaker":"Dante","message":"Acoplamento, juntas e regulador. O conjunto está completo. Vou levar para a bomba de Santa Lua."}]
		2: lines=[{"speaker":"Dante","message":"Conjunto instalado e conexões apertadas. Falta abrir a válvula ao lado da bomba."}]
		3: lines=[{"speaker":"Dante","message":"A água voltou aos canteiros. Vou avisar a Joana pelo rádio."}]
		4: lines=[{"speaker":"Joana · rádio","message":"Já estou vendo a pressão subir! Agora a cooperativa pode cuidar dos canteiros outra vez. Os mil e oitocentos são seus, Dante. Obrigada por não deixar nossa carga esquecida lá."}]
	session.show_dialogue(lines)
	return true

func objective() -> String:
	var state:=STATE.data(session.state.world_state)
	return STATE.TITLE+": "+str(step_definition(int(state.step)).get("objective","")) if state.active else ""

func target_position() -> Vector3:
	var state:=STATE.data(session.state.world_state)
	return step_definition(int(state.step)).get("point",Vector3.ZERO) if state.active else Vector3.ZERO

func cancel_attempt() -> void:
	# Durable cargo and installed parts survive death, streaming and fast travel.
	_clock=.4

func save_block_reason() -> String:
	return ""
