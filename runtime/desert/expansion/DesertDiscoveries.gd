extends Node3D
## Outdoor discoveries use the existing contextual action and durable economy.
const SITES := preload("res://world/desert/expansion/DesertRelics.gd")
const STATE := preload("res://runtime/desert/expansion/DesertDiscoveryState.gd")
const PREFIX := "discovery:"
var session
var _tick := 0.0
var _sites: Array[Dictionary] = []

func configure(owner_session) -> void:
	session=owner_session
	name="DesertDiscoveries"
	_sites=SITES.secrets()

func _process(delta: float) -> void:
	_tick+=delta
	if _tick<.4 or session==null or not session.ready_for_play: return
	_tick=0.0
	if session.state.region_id!="desert" or not session.state.place_id.is_empty(): return
	for contents in get_tree().get_nodes_in_group("desert_discovery_contents"):
		if is_instance_valid(contents):
			contents.visible=not STATE.collected(session.state.world_state,str(contents.get_meta("discovery_id","")))

func _available() -> bool:
	return session!=null and session.ready_for_play and session.state.region_id=="desert" and session.state.place_id.is_empty() and not session.modal and not get_tree().paused and not session.world.driving.occupied and session.world.gameplay.health>0 and not session.is_transition_blocked() and not session.desert.busy()

func nearest_action() -> Dictionary:
	if not _available(): return {}
	var point: Vector3=session.world.player.global_position
	for site in _sites:
		if STATE.collected(session.state.world_state,str(site.id)): continue
		if point.distance_to(site.position)>1.7: continue
		if not _line_clear(point,site.target): continue
		return {"id":"desert","target":PREFIX+str(site.id),"label":str(site.get("action","Examinar esconderijo"))}
	return {}

func _line_clear(point: Vector3,target: Vector3) -> bool:
	# The query stops short of the target chest; walls between player and cache block use.
	var eye:=point+Vector3.UP*1.1
	var destination:=target+Vector3.UP*.2
	var direction:=destination-eye
	if direction.length()<.5: return true
	var ray:=PhysicsRayQueryParameters3D.create(eye,destination-direction.normalized()*.42,1)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func perform(action: Dictionary) -> bool:
	if action.get("id","")!="desert" or not str(action.get("target","")).begins_with(PREFIX): return false
	if nearest_action()!=action: return false
	var id:=str(action.target).trim_prefix(PREFIX)
	var result: Dictionary=STATE.claim(session.state.world_state,session.state.economy,id,session.world.gameplay.health>0)
	if not bool(result.get("ok",false)):
		session.show_message("Não foi possível recolher agora. Volte depois.")
		return false
	if bool(result.get("changed",false)):
		var clue:=""
		for site in _sites:
			if str(site.id)==id: clue=str(site.get("clue","")); break
		if clue.is_empty(): session.show_message(String(TranslationServer.translate("Encontrou R$ %d."))%int(result.get("amount",0)))
		else: session.show_dialogue([{"speaker":"Dante","message":clue+"  (+R$ %d)"%int(result.get("amount",0))}])
		session.save_game()
		_tick=.4
	return true
