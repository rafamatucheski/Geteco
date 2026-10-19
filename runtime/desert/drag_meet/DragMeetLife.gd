extends Node3D
## Own visit budget: six crew and 28 ordinary guests. Ambient traffic
## cannot consume their slots. One admission per tick; every body leaves with its owner.
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const MEMBER := preload("res://runtime/desert/drag_meet/DragMeetMember.gd")
const GUEST := preload("res://runtime/desert/drag_meet/DragMeetGuest.gd")
const ROSTER := preload("res://runtime/desert/drag_meet/DragMeetRoster.gd")
const AMBIENCE := preload("res://runtime/desert/drag_meet/DragMeetAmbience.gd")
const SCORE := preload("res://runtime/desert/drag_meet/DragMeetScore.gd")
const CREW_OFFSETS := ROSTER.CREW_OFFSETS
const VISITOR_POINTS := ROSTER.VISITOR_POINTS
const MAX_RESIDENTS := 34
const ADMIT_RADIUS := 88.0
const RELEASE_RADIUS := 220.0 # Beyond every sound island's reach; no cutoff beside the start.
var session
var gameplay: Node
var guest_specs: Array[Dictionary] = ROSTER.guests()
var members: Dictionary = {}
var retired: Dictionary = {}
var ambience: Node3D
var score: Node
var active := false
var _clock := 0.0
var _elapsed := 0.0
var _last_alert_ms := -1000
var _last_alert_radius := 0.0
var barks := preload("res://runtime/desert/drag_meet/DragMeetBarks.gd").new()

func configure(owner_session) -> void:
	session = owner_session
	name = "DragMeetLife"
	gameplay = session.world.gameplay
	gameplay.weapon_fired.connect(_weapon_fired)
	gameplay.npc_gunfire.connect(_npc_gunfire)
	gameplay.explosion_occurred.connect(_explosion)
	gameplay.player_died.connect(_clear)
	score=SCORE.new()
	add_child(score)

func _process(delta: float) -> void:
	_elapsed += delta
	_clock += delta
	if _clock<.18: return
	_clock = 0.0
	_update_score()
	reconcile()

func _update_score() -> void:
	if not is_instance_valid(score): return
	if session==null or not session.ready_for_play:
		score.stop()
		return
	var phase := "idle"
	var drag = session.desert.drag if is_instance_valid(session.desert) else null
	if is_instance_valid(drag):
		if drag.active: phase=str(drag.phase)
		elif is_instance_valid(drag.board_controller) and is_instance_valid(drag.board_controller.results_layer) and drag.board_controller.results_layer.visible:
			phase="results"
	var blocked: bool = session.world.gameplay.health<=0 or session.state.region_id!="desert" or not session.state.place_id.is_empty() or session.is_transition_blocked()
	var radio_active := false
	if is_instance_valid(session.controller.world_audio):
		var radio = session.controller.world_audio.radio
		radio_active=is_instance_valid(radio) and radio.playing
	var speaking: bool = session.dialogue_open or barks.is_speaking()
	score.update_context(session.world.player.global_position,phase,blocked,speaking,radio_active,_elapsed)

func reconcile() -> void:
	if session==null or not session.ready_for_play or session.world.gameplay.health<=0:
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
	var heat_phase := "idle"
	if is_instance_valid(session.desert.drag):
		if session.desert.drag.active: heat_phase=str(session.desert.drag.phase)
		elif is_instance_valid(session.desert.drag.open_meet): heat_phase=session.desert.drag.open_meet.phase
	barks.update(session,point,suppressed or session.world.gameplay.stars>0,_elapsed)
	# Activity ownership freezes people but is not a dialogue/music mute. Keep
	# local spectator sound around the start while the score follows the race.
	var audio_suppressed: bool = session.modal or session.dialogue_open or session.world.gameplay.health<=0 or session.is_transition_blocked()
	ambience.update(point,audio_suppressed,_elapsed,workshop_active,heat_phase,barks.is_speaking())
	var admitted := false
	for slot in MAX_RESIDENTS:
		var candidate = members.get(slot)
		var actor: Node3D = candidate if is_instance_valid(candidate) else null
		if is_instance_valid(actor):
			_update_actor(slot,actor,point,suppressed)
			continue
		if members.has(slot):
			members.erase(slot)
			retired[slot]=true
		if admitted or retired.has(slot): continue
		var anchor := _point(slot)
		if point.distance_to(anchor)>ADMIT_RADIUS: continue
		if not session.controller.region.prepare_collision_at(anchor): continue
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
	if actor.dead:
		retired[slot] = true
		return
	var near := listener.distance_squared_to(actor.global_position)<70.0*70.0
	var speaking := int(floor(_elapsed/3.8))%2==slot%2 and not suppressed
	var target: Vector3
	if slot<2: target=LAYOUT.drag_vicente_point()+Vector3(0,0,3.5)
	else: target=_point(slot+1 if slot%2==0 else slot-1)
	if slot<CREW_OFFSETS.size():
		actor.converse(target,speaking and slot>=2,near)
		return
	actor.social_paused = session.modal or session.is_transition_blocked()
	preload("res://runtime/desert/drag_meet/DragMeetAppearance.gd").set_animation_active(actor.person,near or actor._panic>0.0)
	actor.set_physics_process(near or actor._panic>0.0)

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
	if is_instance_valid(score) and (not is_instance_valid(gameplay) or gameplay.health<=0): score.stop()
	barks.stop()
	# Streaming the crowd out during a pass is still the same visit. Do not
	# replay everyone's greeting after each of the night's four returns.
	var same_visit: bool = is_instance_valid(score) and score.mode in ["staging","racing","braking","results"]
	if not same_visit:
		barks.heard.clear()
		barks.next_at=_elapsed+8.0
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
	if is_instance_valid(score): score.stop()
	if is_instance_valid(gameplay):
		if gameplay.player_died.is_connected(_clear): gameplay.player_died.disconnect(_clear)
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
