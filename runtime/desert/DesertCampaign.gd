extends Node3D
const STATE := preload("res://runtime/desert/DesertStoryState.gd")
const CONTACT := preload("res://runtime/desert/DesertCharacter.gd")
const DIGO := preload("res://systems/campaign/DigoProgress.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const ROSTER := preload("res://runtime/desert/drag_meet/DragMeetRoster.gd")
const REUNION := preload("res://runtime/desert/act2/VicenteReunion.gd")
const LOCATIONS := {
	"vicente":LAYOUT.DRAG_VICENTE+Vector3(0,.05,0),
	"livia":ROSTER.LEADERS.livia+Vector3(0,.05,0),
	"raul":ROSTER.LEADERS.raul+Vector3(0,.05,0),
	"jessica":ROSTER.LEADERS.jessica+Vector3(0,.05,0),
	"nadir":ROSTER.LEADERS.nadir+Vector3(0,.05,0),
	"rauhz":Vector3(-947,.05,-1244),
	"bia":Vector3(-151,.05,-943),
}
const MANIFEST := Vector3(266,.05,-758)
var session
var actors: Dictionary = {}
var retired: Dictionary = {}
var _clock := 0.0
var _elapsed := 0.0
var _talking_to := ""
var _manifest_visual: Node3D
## Ato 2, A2-01 "Oito anos" (encontro, Motel Oásis, Capela) e A2-02 "Respeita a pista" (Bia, Digo,
## Arquibancada): runtime/desert/act2.
var reunion: Node3D
func configure(owner_session) -> void:
	session = owner_session
	name = "DesertCampaign"
	session.world.gameplay.player_died.connect(_reset_visit)
	reunion = REUNION.new()
	add_child(reunion)
	reunion.configure(session)

func _reset_visit() -> void:
	for actor in actors.values():
		if is_instance_valid(actor):
			actor.hide()
			actor.collision_layer = 0
			actor.queue_free()
	actors.clear()
	retired.clear()
func _process(delta: float) -> void:
	_elapsed += delta
	_clock += delta
	if _clock < .35 or session == null or not session.ready_for_play: return
	_clock = 0.0
	var active: bool = session.state.region_id == "desert" and session.state.place_id.is_empty() and session.world.gameplay.health>0
	if active and not STATE.data(session.state.world_state).arrived:
		STATE.mark(session.state.world_state,"arrived")
		session.show_message("Maciota: deixei um quarto no Horizonte. Vicente está com a turma dele no encontro da arrancada.")
		session.save_game()
	for id in LOCATIONS:
		var nearby: bool = active and session.world.player.global_position.distance_to(LOCATIONS[id]) < 85.0
		if not nearby: retired.erase(id)
		if is_instance_valid(session.desert.drag) and session.desert.drag.active and session.desert.drag.rival_id==id: nearby=false
		# Durante o reencontro, Vicente espera no motel ou na capela, não no encontro.
		if id=="vicente" and reunion.away_from_meet(): nearby=false
		if actors.has(id) and is_instance_valid(actors[id]):
			if not nearby:
				actors[id].queue_free()
				actors.erase(id)
			else:
				var actor: Node3D = actors[id]
				if actor.dead:
					retired[id] = true
					continue
				var talking: bool = session.modal and _talking_to==id
				actor.set_talking(talking or (not session.modal and fposmod(_elapsed+float(LOCATIONS.keys().find(id))*2.2,12.0)<3.5))
				if talking:
					var offset: Vector3 = session.world.player.global_position-actor.global_position
					actor.visual.rotation.y = atan2(offset.x,offset.z)
				elif id=="vicente": actor.visual.rotation.y=0.0
				elif ROSTER.TEAM_POINTS.has(id):
					var offset: Vector3 = ROSTER.TEAM_POINTS[id][0]-actor.global_position
					actor.visual.rotation.y = atan2(offset.x,offset.z)
		elif nearby and not retired.has(id) and session.position_clear(LOCATIONS[id]+Vector3.UP*.08):
			var actor := CONTACT.new()
			actor.identity_id = id
			actor.position = LOCATIONS[id]
			add_child(actor)
			actors[id] = actor
	if active and session.world.player.global_position.distance_to(MANIFEST)<90:
		if not is_instance_valid(_manifest_visual): _build_manifest()
	elif is_instance_valid(_manifest_visual):
		_manifest_visual.queue_free()
		_manifest_visual = null
func _build_manifest() -> void:
	_manifest_visual = Node3D.new()
	_manifest_visual.position = MANIFEST
	add_child(_manifest_visual)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_manifest_visual.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.8,.75,.65)
	shape.shape = box
	shape.position.y = .375
	body.add_child(shape)
	for row in [[Vector3(0,.375,0),box.size,Color("79634b")],[Vector3(0,.755,0),Vector3(.38,.025,.28),Color("d5c5a1")]]:
		var mesh := MeshInstance3D.new()
		var geometry := BoxMesh.new()
		geometry.size = row[1]
		mesh.mesh = geometry
		mesh.position = row[0]
		var material := StandardMaterial3D.new()
		material.albedo_color = row[2]
		material.roughness = .95
		mesh.material_override = material
		_manifest_visual.add_child(mesh)
func _available() -> bool:
	return session != null and session.ready_for_play and session.state.region_id == "desert" and not session.modal and not session.world.driving.occupied and session.world.gameplay.health>0 and not session.is_transition_blocked()
func nearest_action() -> Dictionary:
	if not _available(): return {}
	var point: Vector3 = session.world.player.global_position
	var data := STATE.data(session.state.world_state)
	if session.state.place_id == "desert_bank" and is_instance_valid(session.room):
		var service: Vector3 = session.room.to_global(Vector3(-1.5,0,-1.35))
		if point.distance_to(service)<1.8: return {"id":"desert_story","target":"irene","label":"Conversar com Irene"}
		return {}
	if not session.state.place_id.is_empty(): return {}
	var reunion_action: Dictionary = reunion.nearest_action()
	if not reunion_action.is_empty(): return reunion_action
	# O caixote do Miragem virou etapa de A2-03 "Peso morto" (ação da missão, acima).
	for id in actors:
		if is_instance_valid(actors[id]) and not actors[id].dead and point.distance_to(actors[id].global_position)<1.7:
			return {"id":"desert_story","target":id,"label":"Conversar com "+str(CONTACT.LOOKS[id].name)}
	return {}
func perform(target: String, offer_jobs := true) -> bool:
	if nearest_action().get("target","") != target: return false
	_talking_to = target
	if target == "vicente_reunion" or target.begins_with("act2:"): return reunion.perform(target)
	if offer_jobs and session.desert.contracts.open_contact(target): return true
	var data := STATE.data(session.state.world_state)
	match target:
		"vicente":
			# A conversa única de antes de 20/10 virou a primeira etapa da missão "Oito anos".
			if not data.met_vicente: return reunion.meet()
			elif data.bank_proof and data.jessica_met and not data.delivered:
				_say([["Dante","O manifesto e o registro do Cobre têm a mesma autorização. A carga foi trocada antes da operação."],["Vicente","Você me algemou, Dante. Eu lembro de cada minuto."],["Dante","Eu sei. Aqui está a prova. A operação foi armada."],["Vicente","E o que eu faço com os oito anos que perdi?"]],"delivered")
			else: _say([["Vicente","Os caminhões param no Miragem. Se ainda quer respostas, comece pela carga."]])
		"irene":
			# A conferência do manifesto virou A2-04 "A ordem alterada".
			if reunion.irene(): return true
			_say([["Irene","Guarde os comprovantes das corridas. Aqui, uma assinatura errada custa caro."]])
		"livia": _say([["Lívia","Tem largada de manhã, de tarde e de noite. Chegue com o carro inteiro e respeite a pista."],["Dante","E o Vicente?"],["Lívia","Ali com a turma dele. Cuida das apostas e dos contatos. Primeiro, mostre que sabe trocar uma marcha."]])
		"raul":
			# A2-03 "Peso morto" começa e termina na conversa do Raul.
			if reunion.raul(): return true
			_say([["Raul","Meu carro tem mais idade que metade dos pilotos. Não precisa de peça cara para largar direito."],["Raul","Deixei um manifesto no caixote do posto Miragem. Veio junto de uma carga estranha. Confere os números."]])
		"jessica":
			if data.jessica_met: _say([["Jessica","Agora você conhece essa reta. E aquela conversa com seu irmão ainda está te esperando."]])
			else: _say([["Jessica","Olha quem saiu de Harbor. Meu carro está pronto, Dante."],["Dante","Você também corre por aqui?"],["Jessica","Com essa turma desde antes de você chegar. Sobe na tabela e a gente se encontra na largada."]])
		"nadir": _say([["Nadir","Na minha prova, uma troca ruim custa a corrida inteira. Prepare o carro com o Digo."]])
		"rauhz": _say([["Rauhz","Passou pelo Nadir? Então falta nós dois. Meu Focus já está pronto."],["Dante","O preto?"],["Rauhz","MK1, 2002. Na última largada, cada troca conta."]])
		"bia":
			# A2-02 começa pela conversa da Bia.
			if reunion.bia(): return true
			_say([["Bia","Relação curta sai forte e acaba cedo. Turbo grande pede giro. Escolha a preparação para a pista."],["Bia","Digo atende lá dentro. Depois de correr com ele, a oficina fica à sua disposição."]])
		_: return false
	return true
func _say(rows: Array, flag := "") -> void:
	var lines: Array = []
	for row in rows: lines.append({"speaker":row[0],"message":row[1]})
	session.show_dialogue(lines,func():
		if session.world.gameplay.health<=0 or session.state.region_id!="desert": return
		if not flag.is_empty(): STATE.mark(session.state.world_state,flag)
		session.save_game())
func race_finished(result: Dictionary) -> void:
	if not result.get("finished",false): return
	if result.rival_id == "digo": DIGO.complete_desert_race(session.state.world_state,DIGO.DESERT_RACE_ID,true)
	if result.rival_id == "jessica":
		STATE.mark(session.state.world_state,"jessica_met")
		_say([["Jessica","Você melhorou. Ainda lembra daquele serviço em Harbor?"],["Dante","Lembro. Agora tenho o que vim buscar."],["Jessica","Então termina essa conversa com seu irmão."]])
func objective() -> String:
	if session.state.region_id != "desert": return ""
	return objective_for(session.state.world_state)

## Mesmo texto do objetivo, sem depender da região (diário, JournalArcs).
static func objective_for(world_state: Dictionary) -> String:
	var data := STATE.data(world_state)
	if not data.met_vicente:
		var reunion_step := REUNION.objective_for(world_state)
		return reunion_step if not reunion_step.is_empty() else "Encontre Vicente no encontro da arrancada."
	var track_step := REUNION.objective_for(world_state)
	if not track_step.is_empty(): return track_step
	if not DIGO.workshop_unlocked(world_state): return "Corra contra Digo na reta."
	if not data.cargo_found: return "Confira a carga dos Cobras no posto Miragem."
	if not data.bank_proof: return "Leve o manifesto a Irene no Cobre."
	if not data.jessica_met: return "Avance nas provas de arrancada e enfrente Jessica."
	if not data.delivered: return "Mostre a prova da armação a Vicente."
	return "Explore o deserto e complete o campeonato de arrancada."

## Ato 2 terminado: o diário para de listar o deserto como história em andamento.
static func act_complete(world_state: Dictionary) -> bool:
	return bool(STATE.data(world_state).delivered)
func target_position() -> Vector3:
	var data := STATE.data(session.state.world_state)
	var mission_point: Vector3 = reunion.target_position()
	if mission_point != Vector3.INF: return mission_point
	var world: Dictionary = session.state.world_state
	match REUNION.STATE.track_stage(world) if data.met_vicente else "-":
		"": return LOCATIONS.bia
		"race": return LAYOUT.drag_staging_point()
	if REUNION.STATE.chain_ready(world, "cargo") and REUNION.STATE.chain_stage(world, "cargo") in ["", "raul"]: return LOCATIONS.raul
	if not data.met_vicente or (data.bank_proof and data.jessica_met and not data.delivered): return LOCATIONS.vicente
	if not DIGO.workshop_unlocked(session.state.world_state): return LAYOUT.drag_staging_point()
	if not data.cargo_found: return MANIFEST
	if not data.bank_proof:
		if session.state.place_id == "desert_bank" and is_instance_valid(session.room): return session.room.to_global(Vector3(-1.5,0,-1.35))
		return PLACES.get_definition("desert_bank").entry_position
	return LAYOUT.drag_staging_point()
