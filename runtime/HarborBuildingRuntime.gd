extends Node
## Prepares one nearby building in the street's actual world, then admits a
## walking player across its threshold without a door action or scene jump.
const CATALOG := preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
var session
var staged: Node3D
var facade: Node3D
var definitions: Array[Dictionary] = []
var preparing := false
var crossing := false
var cooldown := 0.0
var search_clock := 0.0
var selected_id := ""
var walking_admission := false
var walking_departure := false
var falling := false
var fall_peak := 0.0
var fall_room: Node3D
var sightline: Node3D

func _ready() -> void:
	sightline = preload("res://world/places/harbor_buildings/HarborBuildingSightline.gd").new()
	add_child(sightline)

func handles_place(id: String) -> bool:
	return not id.is_empty() and CATALOG.is_building(id)

func in_building() -> bool:
	return session != null and handles_place(session.state.place_id) and is_instance_valid(session.room)

func on_rooftop() -> bool:
	return in_building() and session.room.floor_index == int(session.room.definition.floor_count)

func _blocked() -> bool:
	return session.modal or session.is_transition_blocked() or session.world.player.input_locked or session.world.gameplay.health <= 0 or session.world.driving.occupied

func _find_facade(id: String) -> Node3D:
	for candidate in get_tree().get_nodes_in_group("harbor_building_facade"):
		if is_instance_valid(candidate) and candidate.is_inside_tree() and str(candidate.get_meta("place_id", "")) == id:
			return candidate
	return null

func prepare_room(id: String, new_entry: bool) -> Node3D:
	if is_instance_valid(staged) and not staged.is_queued_for_deletion() and staged.definition.id == id: return staged
	if preparing: return null
	preparing = true
	var generation: int = session.transition_generation
	var region: String = session.state.region_id
	_release_staged()
	var definition: Dictionary = PLACES.get_definition(id)
	if definition.is_empty():
		preparing = false
		return null
	session.controller.region.set_focus(definition.entry_position)
	for frame in 240:
		if not _preparation_owned(generation,region): return _abort_preparation()
		facade = _find_facade(id)
		if is_instance_valid(facade): break
		await get_tree().physics_frame
	if not is_instance_valid(facade):
		preparing = false
		return null
	facade.set_open_amount(1.0)
	for frame in 4:
		await get_tree().physics_frame
		if not _preparation_owned(generation,region) or not is_instance_valid(facade): return _abort_preparation()
	if not facade.access_ready:
		preparing = false
		return null
	staged = PLACES.create_place(id)
	staged.prepare_session(session, new_entry)
	staged.position = definition.exterior_position
	staged.rotation.y = float(definition.get("exterior_rotation", 0.0))
	session.world.add_child(staged)
	staged.floor_changed.connect(_floor_changed)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not _preparation_owned(generation,region): return _abort_preparation()
	preparing = false
	return staged

func _preparation_owned(generation: int, region: String) -> bool:
	return is_instance_valid(session) and session.is_inside_tree() and session.transition_generation == generation and session.state.region_id == region and session.world.gameplay.health > 0 and not session.rescue_pending and not session.arrest_pending

func _abort_preparation() -> Node3D:
	_release_staged()
	preparing = false
	return null

func reset() -> void:
	_release_staged()
	if is_instance_valid(fall_room): fall_room.queue_free()
	fall_room = null
	falling = false
	walking_admission = false
	walking_departure = false
	cooldown = .6

func _release_staged() -> void:
	_clear_approach()
	if is_instance_valid(sightline): sightline.clear()
	if is_instance_valid(staged) and staged != session.room: staged.queue_free()
	staged = null
	if is_instance_valid(facade): facade.restore_exterior()
	facade = null

func update(delta: float) -> void:
	if session == null or not session.ready_for_play or get_tree().paused: return
	if falling:
		_update_fall()
		return
	cooldown = maxf(0.0, cooldown - delta)
	if in_building():
		if on_rooftop():
			var roof_local: Vector3 = session.room.to_local(session.world.player.global_position)
			var half: Vector2 = session.room.definition.size * .5
			if (absf(roof_local.x) > half.x + .35 or absf(roof_local.z) > half.y + .35) and roof_local.y < session.room.floor_height(session.room.floor_index) + .1:
				_begin_fall()
				return
		if is_instance_valid(facade) and not preparing:
			facade.set_open_amount(1.0)
		if session.room.floor_index == 0 and not crossing and not _blocked():
			var player_local: Vector3 = session.room.to_local(session.world.player.global_position)
			var player_local_velocity: Vector3 = session.room.global_basis.inverse() * session.world.player.velocity
			if absf(player_local.x-session.room.definition.entrance_local.x) < 1.05 and player_local.z >= session.room.definition.size.y * .5 + .6 and player_local_velocity.z > .2:
				_depart()
		return
	if not session.state.place_id.is_empty() or session.world.driving.occupied:
		if not preparing and is_instance_valid(staged): _release_staged()
		return
	if preparing or crossing or _blocked(): return
	if not is_instance_valid(staged) and is_instance_valid(facade): _release_staged()
	search_clock += delta
	if search_clock >= .15:
		search_clock = 0.0
		if definitions.is_empty(): definitions = CATALOG.definitions()
		var nearest := ""
		var best := 64.0
		for definition in definitions:
			if definition.region != session.state.region_id: continue
			var distance: float = session.world.player.global_position.distance_squared_to(definition.entry_position)
			if distance < best:
				nearest = definition.id
				best = distance
		selected_id = nearest
		if nearest in ["harbor_building_garden_flats","harbor_building_service_lodge"] and best<36.0:
			session.world.camera.set_meta("harbor_building_approach",true)
		else:
			_clear_approach()
		if nearest.is_empty():
			if is_instance_valid(staged) and session.world.player.global_position.distance_to(staged.definition.entry_position) > 15.0: _release_staged()
		elif not is_instance_valid(staged) or staged.definition.id != nearest:
			prepare_room(nearest, true)
			return
	if not is_instance_valid(staged) or selected_id != staged.definition.id or cooldown > 0.0: return
	var local: Vector3 = staged.to_local(session.world.player.global_position)
	var velocity: Vector3 = staged.global_basis.inverse() * session.world.player.velocity
	var threshold: float = staged.definition.size.y * .5
	if absf(local.x-staged.definition.entrance_local.x) <= 1.04 and local.z < threshold - .10 and local.z > threshold - 2.2 and velocity.z < -.2:
		_admit(staged.definition.id)

func _admit(id: String) -> void:
	crossing = true
	walking_admission = true
	await session.enter_place(id, true, id)
	walking_admission = false
	crossing = false
	cooldown = .35

func _depart() -> void:
	crossing = true
	walking_departure = true
	await session.leave_place()
	walking_departure = false
	crossing = false
	cooldown = .45

func entered() -> void:
	staged = session.room
	_floor_changed(staged.floor_index, on_rooftop())

func departed(leaving: Node3D) -> void:
	if leaving != staged: return
	if is_instance_valid(sightline): sightline.clear()
	staged = null
	if is_instance_valid(facade):
		facade.restore_exterior()
	facade = null
	cooldown = .6

func _floor_changed(index: int, rooftop: bool) -> void:
	if not in_building(): return
	_clear_approach()
	session.world.camera._building_approach_blend = 0.0
	if is_instance_valid(facade): facade.set_floor_view(index, float(session.room.definition.get("storey_height", 3.1)), rooftop)
	var camera = session.world.camera
	if rooftop:
		camera.target = session.world.player
		camera.offset = camera.EXTERIOR_OFFSET
		camera.locked = false
		camera.heading = session.saved_heading
	else:
		session.anchor.position = session.room.camera_target
		camera.target = session.anchor
		camera.offset = preload("res://world/places/harbor_buildings/HarborBuildingCamera.gd").offset(session.room.definition,index)
		camera.locked = true
		camera.heading = float(session.room.definition.get("exterior_rotation", 0.0))
	camera.target_size = session.room.camera_size
	camera.size = session.room.camera_size
	camera.initialized = false
	camera._process(0.0)
	sightline.configure(session.room.definition,index,rooftop)
	session._update_reward()
	session._sync_location_presentation()

func _clear_approach() -> void:
	if is_instance_valid(session) and is_instance_valid(session.world.camera):
		if session.world.camera.has_meta("harbor_building_approach"): session.world.camera.remove_meta("harbor_building_approach")

func nearest_action() -> Dictionary:
	if not on_rooftop() or _blocked() or crossing: return {}
	var roof = session.room.floor_room
	if not roof.has_method("jump_access"): return {}
	var access: Dictionary = roof.jump_access()
	if session.world.player.global_position.distance_to(roof.to_global(access.point)) > 1.05: return {}
	return {"id":"building_rooftop_jump","provider":self,"label":"Saltar da cobertura"}

func jump_from_roof() -> bool:
	if nearest_action().is_empty(): return false
	var token: int = session._begin_transition("building_rooftop_jump")
	if token < 0: return false
	var actor = session.world.player
	var roof = session.room.floor_room
	var access: Dictionary = roof.jump_access()
	var automatic: bool = actor.controlled_automatically
	var previous_direction: Vector3 = actor.automatic_direction
	var previous_speed: float = actor.speed
	crossing = true
	roof.set_jump_gate(true)
	actor.controlled_automatically = true
	actor.automatic_direction = roof.global_basis * access.outward
	actor.speed = 5.0
	var end := Time.get_ticks_msec() + 2200
	while not falling and Time.get_ticks_msec() < end and session._owns_transition(token) and session.world.gameplay.health > 0:
		await get_tree().physics_frame
	if session._owns_transition(token):
		actor.controlled_automatically = automatic
		actor.automatic_direction = previous_direction
		actor.speed = previous_speed
	if not falling and is_instance_valid(roof): roof.set_jump_gate(false)
	crossing = false
	session._finish_transition(token)
	return falling

func _begin_fall() -> void:
	if is_instance_valid(sightline): sightline.clear()
	falling = true
	fall_room = session.room
	fall_peak = session.world.player.global_position.y
	# Keep the real roof in place until the actor has landed. The actor is now
	# outdoors, so rescue, dispatch and camera use the falling world position.
	session._clear_service_npcs()
	session.room = null
	session.state.set_location(session.state.region_id)
	session.world.camera.target = session.world.player
	session.world.camera.locked = false
	session.world.camera.offset = session.world.camera.EXTERIOR_OFFSET
	session.world.camera.target_size = session.saved_size
	session._sync_location_presentation()
	session.sync_dispatch_location()
	session._refresh_routine_context()

func _update_fall() -> void:
	var actor = session.world.player
	fall_peak = maxf(fall_peak,actor.global_position.y)
	var interrupted: bool = session.world.gameplay.health <= 0 or session.rescue_pending or session.arrest_pending
	if not interrupted and (not actor.is_on_floor() or fall_peak-actor.global_position.y < .2): return
	var drop: float = fall_peak-actor.global_position.y
	falling = false
	if is_instance_valid(fall_room): fall_room.queue_free()
	fall_room = null
	staged = null
	if is_instance_valid(facade): facade.restore_exterior()
	facade = null
	cooldown = 1.0
	if not interrupted:
		if drop > 3.0: session.world.gameplay.damage_environment((drop-3.0)*11.0)
		if session.world.gameplay.health > 0: session.save_game()
