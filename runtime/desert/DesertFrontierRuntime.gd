extends Node3D
## Descobertas ao ar livre e o conteúdo persistente delas. A região é dona das ruínas;
## este coordenador só cuida do tempo de vida dos encontros e das regras de interação física.
const SITE := preload("res://world/desert/DesertAbandonedSite.gd")
const SECRET := preload("res://runtime/desert/DesertSecretState.gd")
const BANDITS := preload("res://runtime/desert/DesertBanditEncounter.gd")
const WILDS := preload("res://runtime/desert/wilds/DesertWilds.gd")
const ROADSIDE := preload("res://runtime/desert/roadside/DesertRoadside.gd")
const INTERACTION_DISTANCE := 1.25
var session
var bandits: Node3D
## Casinhas, foras-da-lei e cavernas espalhados no meio do nada (DesertWilds).
var wilds: Node3D
## Posto, torre, ferro-velho, lanche da reta e os eventos de estrada (DesertRoadside).
var roadside: Node3D
var _clock := 0.0
var _definitions: Array[Dictionary] = SITE.definitions()
var _observed_site: Node3D
var _physics_ready_frame := 0
var _last_visual_site: Node3D
var _last_visual_mask := -1

func configure(owner_session) -> void:
	session=owner_session
	name="DesertFrontierRuntime"
	if not session.state.world_state.has(SECRET.KEY):
		session.state.world_state[SECRET.KEY]=SECRET.defaults()
	if not is_instance_valid(bandits):
		bandits=BANDITS.new()
		add_child(bandits)
		bandits.configure(session)
		bandits.cleared.connect(_bandits_cleared)
	if not is_instance_valid(wilds):
		wilds=WILDS.new()
		add_child(wilds)
		wilds.configure(session)
	if not is_instance_valid(roadside):
		roadside=ROADSIDE.new()
		add_child(roadside)
		roadside.configure(session)
	_refresh_visuals()

func _process(delta: float) -> void:
	_clock+=delta
	if _clock<.35: return
	_clock=0.0
	if not is_instance_valid(session) or not session.ready_for_play: return
	_refresh_visuals()

func nearest_action() -> Dictionary:
	# A beira de estrada também atende quem está ao volante (conserto no posto), então vem
	# antes da checagem de "a pé" dos achados.
	if is_instance_valid(roadside):
		var roadside_action: Dictionary=roadside.nearest_action()
		if not roadside_action.is_empty(): return roadside_action
	if is_instance_valid(wilds):
		var wilds_action: Dictionary=wilds.nearest_action()
		if not wilds_action.is_empty(): return wilds_action
	if not _available() or not is_instance_valid(_site()): return {}
	var player: CharacterBody3D=session.world.player
	var state := SECRET.data(session.state.world_state)
	var nearest: Dictionary={}
	var best_distance := INTERACTION_DISTANCE
	for definition in _definitions:
		var id := str(definition.id)
		if bool(state.get(id,false)): continue
		var distance := player.global_position.distance_to(Vector3(definition.interaction))
		if distance>best_distance: continue
		best_distance=distance
		nearest={"id":"desert","target":"secret:"+id,"label":"Recolher pista" if id==SECRET.HOUSE_ID else "Recolher dinheiro"}
	return nearest

func perform(action: Dictionary) -> bool:
	if action.get("id","")!="desert": return false
	var target := str(action.get("target",""))
	if not target.begins_with("secret:") or nearest_action().get("target","")!=target:
		return false
	var id := target.trim_prefix("secret:")
	var result := SECRET.claim(session.state.world_state,session.state.economy,id,session.world.gameplay.health>0 and not session.world.player.dead)
	if not bool(result.get("ok",false)):
		session.show_message("Não foi possível recolher agora. Libere espaço na carteira.")
		return true
	_refresh_visuals()
	# Captura o recibo persistente e a flag antes de abrir um diálogo. A admissão
	# comum de save ainda decide se grava agora ou enfileira o checkpoint.
	session.save_game()
	if bool(result.get("reward_changed",false)):
		session.show_message(String(TranslationServer.translate("R$ %d recolhidos."))%int(result.get("amount",0)))
	var clue := str(result.get("clue",""))
	if not clue.is_empty(): session.show_dialogue([{"speaker":"Anotação","message":clue}])
	return true

func save_block_reason() -> String:
	var reason := str(bandits.save_block_reason()) if is_instance_valid(bandits) else ""
	if reason.is_empty() and is_instance_valid(wilds): reason=wilds.save_block_reason()
	if reason.is_empty() and is_instance_valid(roadside): reason=roadside.save_block_reason()
	return reason

func cancel_attempt() -> void:
	if is_instance_valid(bandits): bandits.cancel_attempt()
	if is_instance_valid(wilds): wilds.release_all()
	if is_instance_valid(roadside): roadside.cancel_attempt()
	_observed_site=null
	_last_visual_site=null
	_last_visual_mask=-1

func _available() -> bool:
	if not is_instance_valid(session) or not session.ready_for_play: return false
	if session.state.region_id!="desert" or not session.state.place_id.is_empty(): return false
	if session.modal or session.has_position_transition() or session.desert.busy(): return false
	var world=session.world
	if world.gameplay.health<=0 or world.driving.occupied or world.driving.is_body_transition_active(): return false
	var player: CharacterBody3D=world.player
	return not player.dead and not player.input_locked and player.is_on_floor()

func _site() -> Node3D:
	if not is_instance_valid(session): return null
	# Streaming may leave a freed reference; validate before any typed assignment.
	var region: Variant=session.controller.regions.get("desert")
	if not is_instance_valid(region): return null
	var site: Variant=region.get("abandoned_site")
	if not is_instance_valid(site) or not site.is_inside_tree() or site.is_queued_for_deletion():
		_observed_site=null
		return null
	if not is_instance_valid(_observed_site) or _observed_site!=site:
		_observed_site=site
		_physics_ready_frame=Engine.get_physics_frames()+1
	# Um nó recém-carregado existe antes de as formas dele sincronizarem com a física.
	return site if Engine.get_physics_frames()>=_physics_ready_frame else null

func _refresh_visuals() -> void:
	var site := _site()
	if not is_instance_valid(site):
		_last_visual_site=null
		_last_visual_mask=-1
		return
	var state := SECRET.data(session.state.world_state)
	var mask := (1 if bool(state.get(SECRET.HOUSE_ID,false)) else 0) | (2 if bool(state.get(SECRET.CABIN_ID,false)) else 0)
	if is_instance_valid(_last_visual_site) and _last_visual_site==site and _last_visual_mask==mask: return
	for id in SECRET.IDS: SITE.set_collected(site,id,bool(state.get(id,false)))
	_last_visual_site=site
	_last_visual_mask=mask

func _bandits_cleared() -> void:
	if is_instance_valid(session) and session.ready_for_play: session.save_game()

func _exit_tree() -> void:
	cancel_attempt()
