extends Node3D
## One inhabited storey at its true facade elevation. Floor transfer owns the
## session token; ground-floor admission remains a continuous walking passage.
signal floor_changed(index: int, rooftop: bool)
const NATIVE = preload("res://world/places/NativePlace.gd")
const CONTENT = preload("res://world/places/harbor_buildings/HarborBuildingContent.gd")
const OCCUPANTS = preload("res://world/places/harbor_buildings/HarborBuildingOccupants.gd")
const SECRETS = preload("res://world/places/harbor_buildings/HarborBuildingSecrets.gd")
const ROOFTOP = preload("res://world/places/harbor_buildings/HarborBuildingRooftop.gd")
const CAMERA = preload("res://world/places/harbor_buildings/HarborBuildingCamera.gd")
var definition: Dictionary
var session
var floor_index := 0
var floor_room: Node3D
var occupants: Node3D
var secrets: Node3D
var interaction_points := {"service":Vector3.INF}
var reward_points: Array = []
var active := true
var spawn_position: Vector3:
	get:
		var point: Vector3 = definition.spawn if floor_index == 0 else _landing(floor_index)
		return to_global(point)
var exit_position: Vector3:
	get: return to_global(definition.exit if floor_index == 0 else stair_point())
var camera_target: Vector3:
	get: return to_global(Vector3(0,.65+floor_height(floor_index),0))
var camera_size: float:
	get: return clampf(maxf(definition.size.x,definition.size.y)*1.7,36.0,56.0) if is_rooftop() else float(definition.camera_size)

func prepare_session(owner_session, new_entry: bool) -> void:
	session = owner_session
	if not new_entry and not session.ready_for_play:
		floor_index = clampi(int(session.state.world_state.get("harbor_building_floors",{}).get(definition.id,0)),0,int(definition.floor_count))

func floor_height(index: int) -> float:
	return float(definition.get("roof_height",6.0)) if index == int(definition.floor_count) else index*float(definition.get("storey_height",3.0))

func is_rooftop() -> bool:
	return floor_index == int(definition.floor_count)

func stair_point() -> Vector3:
	return Vector3(-definition.size.x*.5+1.45,floor_height(floor_index),1.45)

func _landing(index: int) -> Vector3:
	return Vector3(-definition.size.x*.5+2.80,floor_height(index),1.45)

func _ready() -> void:
	name = definition.id
	floor_room = _make_floor(floor_index)
	add_child(floor_room)
	_mark_walkable_floor(floor_room)
	secrets = SECRETS.populate(floor_room,definition,floor_index,session)
	_sync_floor_contract()
	set_process(false)
	set_physics_process(false)

func _make_floor(index: int) -> Node3D:
	var next: Node3D = ROOFTOP.new() if index == int(definition.floor_count) else NATIVE.new()
	next.definition = definition.duplicate(true)
	next.definition["building_floor_index"] = index
	next.definition["npcs"] = []
	next.definition["npc_model"] = ""
	next.definition["rewards"] = CONTENT.floor_rewards(definition,index)
	next.definition["reward"] = {}
	next.position.y = floor_height(index)
	return next

func _sync_floor_contract() -> void:
	reward_points = floor_room.reward_points
	interaction_points["service"] = Vector3.INF

func _mark_walkable_floor(next: Node3D) -> void:
	# The raised finish clears exterior paving. Only its authored floor may
	# be stepped onto; furniture keeps the shared actor's strict prohibition.
	for body in next.solid_bodies:
		if str(body.name) != "Floor": continue
		body.set_meta("pedestrian_step",true)
		body.set_meta("pedestrian_step_top",-.02)

func on_session_entered(owner_session) -> void:
	session = owner_session
	if is_instance_valid(secrets):
		secrets.session = session
		secrets.reconcile()
	_install_occupants()
	_reconcile_rewards()
	_remember_floor()
	floor_changed.emit(floor_index,is_rooftop())

func _install_occupants() -> void:
	if is_instance_valid(occupants): return
	occupants = OCCUPANTS.populate(floor_room,definition,floor_index)

func _reconcile_rewards() -> void:
	if session == null: return
	for point in reward_points:
		var reward: Dictionary = point.get("reward",{})
		if not reward.is_empty(): set_reward_available(not session.state.world_state.rewards.has(reward.id),str(reward.id))

func _remember_floor() -> void:
	if session == null: return
	var floors: Dictionary = session.state.world_state.get("harbor_building_floors",{}).duplicate()
	floors[definition.id] = floor_index
	session.state.world_state.harbor_building_floors = floors

func nearest_action() -> Dictionary:
	if session == null or session.modal or session.is_transition_blocked() or session.world.gameplay.health <= 0: return {}
	if is_instance_valid(secrets):
		var secret_action: Dictionary = secrets.nearest_action()
		if not secret_action.is_empty(): return secret_action
	if session.world.player.global_position.distance_to(to_global(stair_point())) > 1.55: return {}
	var label := "Descer da cobertura" if is_rooftop() else ("Subir à cobertura" if int(definition.floor_count)==1 else "Usar escada")
	return {"id":"building_stairs","provider":self,"label":label}

func use_stairs() -> bool:
	if nearest_action().get("id","") != "building_stairs": return false
	if floor_index == 0: return await change_floor(1)
	if is_rooftop(): return await change_floor(floor_index-1)
	session._menu("Escada · %dº andar"%floor_index)
	var upper := floor_index+1
	var lower := floor_index-1
	session._button("Subir à cobertura" if upper == int(definition.floor_count) else "Subir ao %dº andar"%upper,func():
		session.close_menu()
		change_floor(upper))
	session._button("Descer ao térreo" if lower == 0 else "Descer ao %dº andar"%lower,func():
		session.close_menu()
		change_floor(lower))
	session._button("Voltar",session.close_menu)
	return true

func change_floor(next_index: int) -> bool:
	if nearest_action().get("id","") != "building_stairs" or next_index < 0 or next_index > int(definition.floor_count) or absi(next_index-floor_index) != 1: return false
	var token: int = session._begin_transition("building_stairs")
	if token < 0: return false
	var actor = session.world.player
	var was_locked: bool = actor.input_locked
	actor.input_locked = true
	await session.door_transition.fade_to(1.0,.20)
	if not _owns_floor_transition(token):
		await _abort_stairs(token,was_locked)
		return false
	var next := _make_floor(next_index)
	next.hide()
	add_child(next)
	_mark_walkable_floor(next)
	var next_secrets: Node3D = SECRETS.populate(next,definition,next_index,session)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not _owns_floor_transition(token):
		next.queue_free()
		await _abort_stairs(token,was_locked)
		return false
	var destination := to_global(_landing(next_index))+Vector3.UP*.04
	if not session.position_clear(destination):
		next.queue_free()
		await _abort_stairs(token,was_locked)
		session.show_message("Passagem ocupada. Aguarde.")
		return false
	var old := floor_room
	floor_room = next
	# Shared traffic/physics caches can still hold resident references until
	# the frame ends; keep their transforms in-tree until deferred disposal.
	old.set_active(false)
	old.queue_free()
	occupants = null
	secrets = next_secrets
	floor_index = next_index
	next.show()
	actor.teleport(destination)
	_sync_floor_contract()
	_install_occupants()
	_reconcile_rewards()
	_remember_floor()
	_update_camera()
	floor_changed.emit(floor_index,is_rooftop())
	await get_tree().physics_frame
	if not _owns_floor_transition(token):
		await _abort_stairs(token,was_locked)
		return false
	await session.door_transition.fade_to(0.0,.20)
	session._restore_transition_player_lock(was_locked,token)
	session._finish_transition(token)
	session.save_game()
	return true

func _update_camera() -> void:
	if session == null: return
	session.anchor.global_position = camera_target
	session.world.camera.target = session.anchor
	session.world.camera.offset = CAMERA.offset(definition,floor_index)
	session.world.camera.heading = 0.0
	session.world.camera.target_size = camera_size
	session.world.camera.size = camera_size
	session.world.camera.locked = true
	session.world.camera.initialized = false
	session.world.camera._process(1.0)

func _owns_floor_transition(token: int) -> bool:
	return is_instance_valid(session) and session._owns_transition(token) and session.room == self and session.world.gameplay.health > 0

func _abort_stairs(token: int,was_locked: bool) -> void:
	# A rescue that took the token also owns its curtain and actor lock.
	if not is_instance_valid(session) or not session._owns_transition(token): return
	await session.door_transition.fade_to(0.0,.20)
	session._restore_transition_player_lock(was_locked,token)
	session._finish_transition(token)

func is_floor_clear(point: Vector3,radius := .32) -> bool:
	var local_point := point-Vector3.UP*floor_height(floor_index)
	return floor_room.is_floor_clear(local_point,radius)

func set_reward_available(available: bool,id: String = "",animate := false) -> void:
	floor_room.set_reward_available(available,id,animate)

func set_active(value: bool) -> void:
	if is_instance_valid(secrets): secrets.set_active(value)
	active = value
	visible = value
	process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	floor_room.set_active(value)
