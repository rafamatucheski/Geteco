extends Node3D
## A cena é dona dos sólidos estáticos do acampamento; este runtime cuida de oito defensores finitos.
signal cleared
const STATE := preload("res://runtime/desert/canyon/CanyonState.gd")
const GUARD := preload("res://runtime/desert/canyon/CanyonGuard.gd")
const LAYOUT := preload("res://world/desert/canyon/DesertSmugglerLayout.gd")
const SPAWN_DISTANCE := 95.0
const DESPAWN_DISTANCE := 140.0
var session
var ambience: Node3D
var actors: Dictionary={}
var _loot: Array[Node3D]=[]
var _clock := 0.0
var _admission_wait := 0.0
var _engaged := false
var _paused := false
var _known_mask := 0
var _site: Node3D
var _site_physics_frame := 0
var _state_error_reported := false

func configure(owner_session) -> void:
	session=owner_session
	name="CanyonEncounter"
	if not LAYOUT.enabled():
		set_process(false)
		return
	if not session.state.world_state.has(STATE.KEY): session.state.world_state[STATE.KEY]=STATE.defaults()
	var saved: Variant=session.state.world_state[STATE.KEY]
	if STATE.valid(saved): _known_mask=int(saved.defeated_mask)
	ambience=preload("res://runtime/desert/canyon/CanyonAmbience.gd").new()
	add_child(ambience)
	ambience.configure(session,self)

func operational() -> bool:
	return LAYOUT.enabled() and is_instance_valid(session) and session.ready_for_play and session.state.region_id=="desert" and session.state.place_id.is_empty() and session.world.gameplay.health>0 and not session.world.player.dead and not session.modal and not session.world.player.input_locked and not session.has_position_transition() and not session.desert.busy()

func save_block_reason() -> String:
	return "Afaste-se do cânion ou encerre o confronto antes de salvar." if _engaged and live_count()>0 else ""

func cancel_attempt() -> void:
	_release()
	if is_instance_valid(ambience): ambience.stop()
	_admission_wait=.6
	_site=null

func live_count() -> int:
	var count := 0
	for actor in actors.values():
		if is_instance_valid(actor) and not actor.dead: count+=1
	return count

func snapshot() -> Dictionary:
	return {"alive":live_count(),"resident":actors.size(),"engaged":_engaged,"paused":_paused,"defeated_mask":_known_mask}

func _process(delta: float) -> void:
	_clock+=delta
	if _clock<.25 or not is_instance_valid(session) or not session.ready_for_play: return
	_admission_wait=maxf(0,_admission_wait-_clock)
	_clock=0
	if not session.state.world_state.has(STATE.KEY): session.state.world_state[STATE.KEY]=STATE.defaults()
	var saved: Variant=session.state.world_state[STATE.KEY]
	if not STATE.valid(saved):
		if not _state_error_reported: push_error("Invalid desert_smuggler_canyon state; encounter suspended"); _state_error_reported=true
		_release(); return
	if int(saved.defeated_mask)!=_known_mask:
		_release()
		_known_mask=int(saved.defeated_mask)
		_admission_wait=.6
	var world=session.world
	var distance: float=world.player.global_position.distance_to(LAYOUT.CENTER)
	if session.state.region_id!="desert" or not session.state.place_id.is_empty() or world.gameplay.health<=0 or distance>DESPAWN_DISTANCE:
		_release(); return
	_paused=not operational()
	for actor in actors.values():
		if is_instance_valid(actor): actor.set_physics_process(not _paused and not actor.dead)
	if _paused: return
	var region: Node3D=session.controller.regions.get("desert")
	if not is_instance_valid(region): return
	var site: Variant=region.get("canyon_site")
	if not is_instance_valid(site) or site.is_queued_for_deletion():
		_release(); _site=null; return
	if not is_instance_valid(_site) or _site!=site:
		_release()
		_site=site
		_site_physics_frame=Engine.get_physics_frames()+1
	if Engine.get_physics_frames()<_site_physics_frame: return
	_refresh_caches(int(saved.cache_mask))
	if distance<=SPAWN_DISTANCE and _admission_wait<=0:
		for index in STATE.GUARD_COUNT:
			if (int(saved.defeated_mask)&(1<<index))!=0 or is_instance_valid(actors.get(index)): continue
			_admission_wait=.35
			_admit(index,region)
			break
	var target: Node3D=world.gameplay.pursuit_target()
	if not LAYOUT.CAMP_BOUNDS.grow(15.0).has_point(Vector2(target.global_position.x,target.global_position.z)):
		_engaged=false
	elif not _engaged:
		for actor in actors.values():
			if is_instance_valid(actor) and not actor.dead and actor.global_position.distance_to(target.global_position)<26 and world.gameplay.police_can_see(actor):
				_engaged=true; break
	for actor in actors.values():
		if is_instance_valid(actor) and not actor.dead: actor.engaged=_engaged

func _admit(index: int, region: Node3D) -> void:
	var desired: Vector3=LAYOUT.combat_spawn_points()[index]
	if not region.prepare_collision_at(desired): return
	var space: PhysicsDirectSpaceState3D=session.world.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(desired+Vector3.UP*2,desired-Vector3.UP,1)
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or absf(float(hit.position.y)-desired.y)>.2 or float(hit.normal.y)<.95: return
	var point: Vector3=hit.position+Vector3.UP*.06
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new(); capsule.radius=.31; capsule.height=1.7
	query.shape=capsule; query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.86); query.collision_mask=7
	if not space.intersect_shape(query,1).is_empty(): return
	var actor := GUARD.new()
	actor.encounter=self
	actor.slot=index
	actor.configure(session.world.gameplay,2)
	actor.position=point
	actor.died.connect(_actor_died.bind(index))
	add_child(actor)
	actors[index]=actor

func provoke(source: Node) -> void:
	if not operational(): return
	if source==session.world.player or (session.world.driving.occupied and source==session.world.driving.car): _engaged=true

func _actor_died(index: int) -> void:
	if not STATE.defeat(session.state.world_state,index): return
	_known_mask=int(session.state.world_state[STATE.KEY].defeated_mask)
	if _known_mask==STATE.FULL_MASK:
		_engaged=false
		cleared.emit()
		# Defer until Gameplay has completed its death/loot callbacks.
		session.save_game.call_deferred()

func track_loot(pickup: Node3D) -> void:
	if is_instance_valid(pickup): _loot.append(pickup)

func nearest_action() -> Dictionary:
	if not operational() or not is_instance_valid(_site) or session.world.driving.occupied or not session.world.player.is_on_floor(): return {}
	var saved: Variant=session.state.world_state.get(STATE.KEY,STATE.defaults())
	if not STATE.valid(saved) or int(saved.defeated_mask)!=STATE.FULL_MASK: return {}
	for index in STATE.RECEIPTS.size():
		if (int(saved.cache_mask)&(1<<index))!=0: continue
		var point: Vector3=LAYOUT.ARMORY_POS+Vector3(0,0,index*3)
		if session.world.player.global_position.distance_to(point)<1.8:
			return {"id":"desert","target":"canyon_cache:"+str(index),"label":"Recolher AK-47 / munição" if index==0 else "Recolher granadas"}
	return {}

func perform(action: Dictionary) -> bool:
	var current := nearest_action()
	if current.is_empty() or action.get("id")!="desert" or action.get("target")!=current.target: return false
	var index := int(str(current.target).trim_prefix("canyon_cache:"))
	var result := STATE.claim(session.state.world_state,session.state.economy,index,session.world.gameplay.health>0 and not session.world.player.dead)
	if not result.ok:
		session.show_message("Libere espaço no inventário para recolher o armamento.")
		return true
	_refresh_caches(int(session.state.world_state[STATE.KEY].cache_mask))
	session.save_game()
	preload("res://gameplay/RewardAudio.gd").play(self,"weapon")
	return true

func _refresh_caches(mask: int) -> void:
	if not is_instance_valid(_site) or not _site.has_method("set_cache_collected"): return
	for index in STATE.RECEIPTS.size(): _site.set_cache_collected(index,(mask&(1<<index))!=0)

func _release() -> void:
	_engaged=false; _paused=false
	if actors.is_empty() and _loot.is_empty(): return
	# Um tiro letal pode entrar aqui de forma síncrona pelo laço de tiros do Gameplay via
	# player_died. Adia a remoção até esse laço terminar; usa RIDs capturados para que
	# liberar corpos não invalide a posse durante a limpeza adiada.
	if is_instance_valid(session) and is_instance_valid(session.world):
		var gameplay: Node3D=session.world.gameplay
		var owned_rids: Array[RID]=[]
		for actor in actors.values():
			if is_instance_valid(actor): owned_rids.append(actor.get_rid())
		if is_instance_valid(gameplay) and not owned_rids.is_empty(): _clear_projectiles.call_deferred(weakref(gameplay),owned_rids)
	for pickup in _loot:
		if is_instance_valid(pickup): pickup.queue_free()
	_loot.clear()
	for actor in actors.values():
		if is_instance_valid(actor):
			actor.set_physics_process(false); actor.collision_layer=0; actor.collision_mask=0
			actor.queue_free()
	actors.clear()

func _clear_projectiles(gameplay_ref: WeakRef, owned_rids: Array[RID]) -> void:
	var gameplay: Variant=gameplay_ref.get_ref()
	if not is_instance_valid(gameplay): return
	for index in range(gameplay._police_rounds.size()-1,-1,-1):
		var round_data: Dictionary=gameplay._police_rounds[index]
		if not round_data.rid in owned_rids: continue
		if is_instance_valid(gameplay.effects) and not round_data.visual.is_empty(): gameplay.effects.move_police_tracer(round_data.visual,round_data.point,true)
		gameplay._police_rounds.remove_at(index)

func _exit_tree() -> void: _release()
