extends Node3D
## Own visit budget: six protected crew and 28 ordinary guests. Ambient traffic
## cannot consume their slots. One admission per tick; every body leaves with its owner.
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const MEMBER := preload("res://runtime/desert/drag_meet/DragMeetMember.gd")
const GUEST := preload("res://runtime/desert/drag_meet/DragMeetGuest.gd")
const ROSTER := preload("res://runtime/desert/drag_meet/DragMeetRoster.gd")
const AMBIENCE := preload("res://runtime/desert/drag_meet/DragMeetAmbience.gd")
const CREW_OFFSETS := ROSTER.CREW_OFFSETS
const VISITOR_POINTS := ROSTER.VISITOR_POINTS
const MAX_RESIDENTS := 34
const ADMIT_RADIUS := 88.0
const RELEASE_RADIUS := 112.0
var session
var gameplay: Node
var guest_specs: Array[Dictionary] = ROSTER.guests()
var members: Dictionary = {}
var retired: Dictionary = {}
var ambience: Node3D
var active := false
var _clock := 0.0
var _elapsed := 0.0
var _last_alert_ms := -1000
var _last_alert_radius := 0.0

func configure(owner_session) -> void:
	session = owner_session
	name = "DragMeetLife"
	gameplay = session.world.gameplay
	gameplay.weapon_fired.connect(_weapon_fired)
	gameplay.npc_gunfire.connect(_npc_gunfire)
	gameplay.explosion_occurred.connect(_explosion)

func _process(delta: float) -> void:
	_elapsed += delta
	_clock += delta
	if _clock<.18: return
	_clock = 0.0
	reconcile()

func reconcile() -> void:
	if session==null or not session.ready_for_play:
		_clear(); return
	var point: Vector3 = session.world.player.global_position
	var outdoors: bool = session.state.region_id=="desert" and session.state.place_id.is_empty()
	var radius := RELEASE_RADIUS if active else ADMIT_RADIUS
	if not outdoors or point.distance_to(LAYOUT.drag_meet_center())>radius:
		_clear(); return
	active = true
	var suppressed: bool = session.modal or session.world.gameplay.health<=0 or session.is_transition_blocked()
	if is_instance_valid(session.desert) and session.desert.busy(): suppressed=true
	if not is_instance_valid(ambience):
		ambience = AMBIENCE.new()
		add_child(ambience)
	var workshop_active := false
	if is_instance_valid(session.desert.digo_routine) and is_instance_valid(session.desert.digo_routine.actor):
		var worker: Node3D = session.desert.digo_routine.actor
		workshop_active = worker.state in ["repair","tools"] and not worker.talking and not worker.suspended and worker.audio_enabled
	ambience.update(point,suppressed,_elapsed,workshop_active)
	var admitted := false
	for slot in MAX_RESIDENTS:
		var candidate = members.get(slot)
		var actor: Node3D = candidate if is_instance_valid(candidate) else null
		if is_instance_valid(actor):
			_update_actor(slot,actor,point,suppressed)
			continue
		if members.has(slot):
			members.erase(slot)
			if slot>=CREW_OFFSETS.size(): retired[slot]=true
		if admitted or retired.has(slot): continue
		var anchor := _point(slot)
		if point.distance_to(anchor)>ADMIT_RADIUS: continue
		if not session.controller.region.is_streaming_idle(): continue
		session.controller.region.prepare_collision_at(anchor)
		var placement := _floor_anchor(anchor)
		if placement.is_empty(): continue
		if slot<CREW_OFFSETS.size():
			actor = MEMBER.new()
			actor.slot = slot
		else:
			actor = GUEST.new()
			actor.identity = 9800+slot
			actor.specification = guest_specs[slot-CREW_OFFSETS.size()]
			actor.host = self
			actor.set_meta("region_id","desert")
		actor.position = placement.position
		add_child(actor)
		actor.add_to_group("desert_drag_meet_resident")
		members[slot] = actor
		_update_actor(slot,actor,point,suppressed)
		admitted = true

func _point(slot: int) -> Vector3:
	if slot<CREW_OFFSETS.size(): return LAYOUT.drag_vicente_point()+CREW_OFFSETS[slot]
	return guest_specs[slot-CREW_OFFSETS.size()].point

func _floor_anchor(point: Vector3) -> Dictionary:
	if not session.position_clear(point+Vector3.UP*.08): return {}
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.3,point-Vector3.UP*.4,1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or absf(float(hit.position.y)-point.y)>.12 or float(hit.normal.y)<.95: return {}
	return {"position":hit.position+Vector3.UP*.025}

func _update_actor(slot: int,actor: Node3D,listener: Vector3,suppressed: bool) -> void:
	var near := listener.distance_squared_to(actor.global_position)<70.0*70.0
	var speaking := int(floor(_elapsed/3.8))%2==slot%2 and not suppressed
	var target: Vector3
	if slot<2: target=LAYOUT.drag_vicente_point()+Vector3(0,0,3.5)
	else: target=_point(slot+1 if slot%2==0 else slot-1)
	if slot<CREW_OFFSETS.size():
		actor.converse(target,speaking and slot>=2,near)
		return
	if actor.dead:
		retired[slot] = true
		if Time.get_ticks_msec()-int(actor.get_meta("drag_meet_dead_since",Time.get_ticks_msec()))>12000 and not actor.get_meta("drag_meet_fading",false):
			actor.set_meta("drag_meet_fading",true)
			preload("res://gameplay/DestroyedFade3D.gd").fade(actor)
		return
	actor.social_paused = session.modal or session.is_transition_blocked()
	actor.person.set_process(near)

func retreat_clear(actor: CharacterBody3D, point: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = .32
	shape.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 7
	query.exclude = [actor.get_rid()]
	for step in 4:
		var sample := actor.global_position.lerp(point,float(step+1)/4.0)
		query.transform.origin = sample+Vector3.UP*.9
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	return true

func alert_crowd(origin: Vector3, radius: float) -> void:
	if not active: return
	var now := Time.get_ticks_msec()
	if now-_last_alert_ms<300 and radius<=_last_alert_radius: return
	_last_alert_ms=now
	_last_alert_radius=radius
	for actor in members.values():
		if is_instance_valid(actor) and actor.has_method("alert") and actor.global_position.distance_to(origin)<radius:
			actor.alert(origin)

func _weapon_fired(_id: String, origin: Vector3) -> void: alert_crowd(origin,52.0)
func _npc_gunfire(origin: Vector3, _direction: Vector3, _shooter: Node3D) -> void: alert_crowd(origin,52.0)
func _explosion(origin: Vector3, radius: float, _source: Node) -> void: alert_crowd(origin,maxf(65.0,radius*3.0))

func _clear() -> void:
	for actor in members.values():
		if not is_instance_valid(actor): continue
		actor.hide()
		actor.collision_layer = 0
		actor.collision_mask = 0
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.queue_free()
	members.clear()
	retired.clear()
	if is_instance_valid(ambience):
		ambience.stop()
		ambience.queue_free()
	ambience = null
	active = false

func _exit_tree() -> void:
	if is_instance_valid(gameplay):
		if gameplay.weapon_fired.is_connected(_weapon_fired): gameplay.weapon_fired.disconnect(_weapon_fired)
		if gameplay.npc_gunfire.is_connected(_npc_gunfire): gameplay.npc_gunfire.disconnect(_npc_gunfire)
		if gameplay.explosion_occurred.is_connected(_explosion): gameplay.explosion_occurred.disconnect(_explosion)
	_clear()

func diagnostics() -> Dictionary:
	var count := 0
	var crew := 0
	var voices := 0
	var teams: Dictionary = {}
	for slot in members:
		if is_instance_valid(members[slot]):
			count+=1
			if slot<CREW_OFFSETS.size(): crew+=1
			else:
				var team: String = guest_specs[slot-CREW_OFFSETS.size()].team
				teams[team] = int(teams.get(team,0))+1
	if is_instance_valid(ambience):
		for voice in ambience.voices:
			if voice.playing: voices+=1
	return {"active":active,"residents":count,"crew":crew,"visitors":count-crew,"voices":voices,"retired":retired.size(),"teams":teams,"budget":MAX_RESIDENTS}
