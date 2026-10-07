extends Node3D
## One streamed worker; the static shop belongs to DesertRegion's chunk.
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const WORKER := preload("res://runtime/desert/DesertDigoWorker.gd")
var session
var actor: CharacterBody3D
var _poll := 0.0
var _conversation := false
var _saw_modal := false
var _conversation_grace := 0.0

static func workshop_point() -> Vector3: return LAYOUT.drag_workshop_point()
static func parking_point() -> Vector3: return workshop_point()+Vector3(6,.08,-5.8)

func configure(owner_session) -> void:
	session=owner_session
	name="DesertDigoRoutine"

func _process(delta: float) -> void:
	if session==null: return
	_poll+=delta
	if _poll>=.30:
		_poll=0.0
		reconcile()
	if not is_instance_valid(actor): return
	var modal: bool=session.modal
	if _conversation:
		_conversation_grace=maxf(0,_conversation_grace-delta)
		_saw_modal=_saw_modal or modal
		if not modal and (_saw_modal or _conversation_grace<=0): end_conversation()
	# A talking worker may gesture; unrelated menus freeze the whole routine.
	actor.set_suspended(modal and not _conversation)

func reconcile() -> void:
	var active: bool=session.ready_for_play and session.state.region_id=="desert" and session.state.place_id.is_empty() and not session.is_transition_blocked()
	var nearby: bool=active and session.world.player.global_position.distance_squared_to(workshop_point())<75.0*75.0
	# An active drag owns its rival; avoid a second Digo at the workshop.
	if nearby and session.get("desert")!=null and session.desert.busy(): nearby=false
	if not nearby:
		if is_instance_valid(actor): actor.queue_free()
		actor=null
		_conversation=false
		return
	if is_instance_valid(actor):
		actor.audio_enabled=session.world.player.global_position.distance_squared_to(actor.global_position)<28.0*28.0
		return
	var at := workshop_point()+WORKER.REPAIR_POINT
	if not session.position_clear(at+Vector3.UP*.08): return
	actor=WORKER.new()
	actor.workshop_origin=workshop_point()
	actor.position=at
	add_child(actor)

func nearest_action() -> Dictionary:
	if session==null or not session.ready_for_play or not is_instance_valid(actor): return {}
	if session.modal or session.state.region_id!="desert" or not session.state.place_id.is_empty(): return {}
	if session.world.driving.occupied or session.world.gameplay.health<=0 or session.is_transition_blocked(): return {}
	if session.world.player.global_position.distance_to(actor.global_position)>1.8: return {}
	return {"id":"desert","target":"digo_workshop","label":"Conversar com Digo"}

func begin_conversation() -> bool:
	if nearest_action().is_empty(): return false
	_conversation=true
	_saw_modal=false
	_conversation_grace=.25
	actor.set_talking(true,session.world.player.global_position)
	return true

func end_conversation() -> void:
	_conversation=false
	_saw_modal=false
	if is_instance_valid(actor): actor.set_talking(false)

func diagnostics() -> Dictionary:
	return {"present":is_instance_valid(actor),"talking":_conversation,
		"state":actor.state if is_instance_valid(actor) else "absent",
		"remaining":actor.remaining if is_instance_valid(actor) else 0.0}
