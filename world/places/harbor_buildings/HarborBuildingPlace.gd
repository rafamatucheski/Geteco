extends Node3D
## One native storey resident at a time; stairs reuse session transition ownership.
const NATIVE = preload("res://world/places/NativePlace.gd")
var definition: Dictionary
var session
var floor_index := 0
var floor_room: Node3D
var interaction_points := {"service":Vector3.INF}
var reward_points: Array = []
var spawn_position: Vector3:
	get: return to_global(definition.spawn)
var exit_position: Vector3:
	get: return to_global(definition.exit if floor_index==0 else stair_point())
var camera_target: Vector3:
	get: return to_global(definition.camera_target)
var camera_size: float:
	get: return definition.camera_size

func prepare_session(owner_session, new_entry: bool) -> void:
	session=owner_session
	if not new_entry and not session.ready_for_play:
		floor_index=int(session.state.world_state.get("harbor_building_floors",{}).get(definition.id,0))
		if floor_index>0: definition.spawn=stair_point()+Vector3.RIGHT*1.35

func stair_point() -> Vector3:
	return Vector3(-definition.size.x*.5+1.45,0,1.45)

func _ready() -> void:
	name=definition.id
	floor_room=_make_floor(floor_index)
	add_child(floor_room)

func _make_floor(index: int) -> Node3D:
	var next=NATIVE.new()
	next.definition=definition.duplicate(true)
	next.definition.variant=int(definition.variant)+index
	return next

func on_session_entered(owner_session) -> void:
	session=owner_session
	_remember_floor()

func _remember_floor() -> void:
	var floors: Dictionary=session.state.world_state.get("harbor_building_floors",{}).duplicate()
	floors[definition.id]=floor_index
	session.state.world_state.harbor_building_floors=floors

func nearest_action() -> Dictionary:
	if session==null or session.modal or session.is_transition_blocked() or session.world.gameplay.health<=0: return {}
	if session.world.player.global_position.distance_to(to_global(stair_point()))>1.45: return {}
	return {"id":"building_stairs","provider":self,"label":"Subir ao 1º andar" if floor_index==0 else "Usar escada · %dº andar"%floor_index}

func use_stairs() -> bool:
	if nearest_action().is_empty(): return false
	if floor_index==0: return await change_floor(1)
	if floor_index==int(definition.floor_count)-1: return await change_floor(floor_index-1)
	session._menu("Escada · %dº andar"%floor_index)
	session._button("Subir ao %dº andar"%(floor_index+1),func():
		session.close_menu()
		change_floor(floor_index+1))
	session._button("Descer ao térreo" if floor_index==1 else "Descer ao %dº andar"%(floor_index-1),func():
		session.close_menu()
		change_floor(floor_index-1))
	session._button("Voltar",session.close_menu)
	return true

func change_floor(next_index: int) -> bool:
	if nearest_action().is_empty() or next_index<0 or next_index>=int(definition.floor_count) or absi(next_index-floor_index)!=1: return false
	var token: int=session._begin_transition("building_stairs")
	if token<0: return false
	var actor=session.world.player
	var was_locked: bool=actor.input_locked
	actor.input_locked=true
	await session.door_transition.fade_to(1.0,.20)
	if not session._owns_transition(token) or session.room!=self or session.world.gameplay.health<=0:
		await _abort_stairs(token,was_locked)
		return false
	var next=_make_floor(next_index)
	# Prepare off-stage so current solids never overlap the admitted actor.
	next.position=Vector3(0,0,-80)
	add_child(next)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not session._owns_transition(token) or session.room!=self or session.world.gameplay.health<=0:
		next.queue_free()
		await _abort_stairs(token,was_locked)
		return false
	var landing:=stair_point()+Vector3.RIGHT*1.35+Vector3.UP*.04
	if not session.position_clear(next.to_global(landing)):
		next.queue_free()
		await _abort_stairs(token,was_locked)
		return false
	var old=floor_room
	floor_room=next
	floor_room.position=Vector3.ZERO
	remove_child(old)
	old.queue_free()
	floor_index=next_index
	actor.teleport(to_global(landing))
	_remember_floor()
	await get_tree().physics_frame
	await session.door_transition.fade_to(0.0,.20)
	session._restore_transition_player_lock(was_locked,token)
	session._finish_transition(token)
	session.save_game()
	return true

func _abort_stairs(token: int,was_locked: bool) -> void:
	# A rescue that took the token also owns its curtain and actor lock.
	if not session._owns_transition(token): return
	await session.door_transition.fade_to(0.0,.20)
	session._restore_transition_player_lock(was_locked,token)
	session._finish_transition(token)

func is_floor_clear(point: Vector3,radius:=.32) -> bool:
	return floor_room.is_floor_clear(point,radius)

func set_active(value: bool) -> void:
	visible=value
	process_mode=Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	floor_room.set_active(value)
