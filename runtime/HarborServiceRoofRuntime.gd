extends Node
## Adds a roof stair to existing owners without replacing their services,
## residents, admission gates, inventories or save identities.
const CATALOG = preload("res://world/places/harbor_buildings/HarborServiceRoofCatalog.gd")
const ROOF = preload("res://world/places/harbor_buildings/HarborBuildingRooftop.gd")
const MATERIALS = preload("res://world/places/ShopInteriorMaterials.gd")
var session
var roof: Node3D
var owner_room: Node3D
var definition: Dictionary = {}
var access_definition: Dictionary = {}
var access_point := Vector3.INF
var access_frame := Basis.IDENTITY
var access_route: Array[Vector3] = []
var access_visual: Node3D
var access_owner: Node3D
var return_position := Vector3.ZERO
var busy := false
var falling := false
var fall_peak := 0.0
var _scan := 0.0
var _saved_camera: Dictionary = {}
var _saved_shelter := false
var _transition_epoch := 0

func is_active() -> bool:
	return is_instance_valid(roof) and not definition.is_empty()

func update(delta: float) -> void:
	if session==null or not session.ready_for_play or get_tree().paused: return
	if is_active():
		if session.world.gameplay.health<=0 or session.rescue_pending or session.arrest_pending or session.state.region_id!="harbor":
			clear(true)
			return
		if falling:
			_tick_fall()
			return
		if not str(definition.place).is_empty() and (not is_instance_valid(owner_room) or session.room!=owner_room or session.state.place_id!=definition.place):
			clear(true)
			return
		var point: Vector3 = roof.to_local(session.world.player.global_position)
		session.world.player.air_movement.roof = roof
		if absf(point.x)>definition.size.x*.5+.12 or absf(point.z)>definition.size.y*.5+.12: _begin_fall()
		return
	if busy: return
	_scan -= delta
	if _scan>0: return
	_scan = .35
	_update_ground_access()

func _blocked() -> bool:
	return busy or session.modal or session.is_transition_blocked() or session.world.driving.occupied or session.world.player.input_locked or session.world.gameplay.health<=0

func _update_ground_access() -> void:
	if session.state.region_id!="harbor" or session.world.driving.occupied:
		_release_access()
		return
	var wanted := CATALOG.find(str(session.state.place_id))
	var room_owner: Node3D = session.room
	var building_owner: Node3D = room_owner
	var origin := Vector3.INF
	var frame := Basis.IDENTITY
	if not wanted.is_empty() and is_instance_valid(room_owner):
		origin = room_owner.interior_spawn if wanted.id=="maciota" else room_owner.spawn_position
		frame = room_owner.global_basis.orthonormalized()
	else:
		if not session.state.place_id.is_empty():
			_release_access()
			return
		var physical := _physical_owner()
		if physical.is_empty():
			_release_access()
			return
		wanted = physical.definition
		building_owner = physical.owner
		origin = physical.point
		frame = physical.frame
	if is_instance_valid(access_visual) and access_definition.get("id","")==wanted.id and access_owner==building_owner: return
	_release_access()
	var model: Node3D = room_owner.get("model") if is_instance_valid(room_owner) else null
	var authored_point: Variant = model.get("roof_access_point") if is_instance_valid(model) else null
	if authored_point is Vector3 and authored_point.is_finite():
		# Architecture owns the placement. Never fall back around the spawn if
		# furniture or an actor temporarily blocks the authored wall access.
		var point: Vector3 = model.to_global(authored_point)+Vector3.UP*.04
		var yaw: Variant = model.get("roof_access_yaw")
		var ladder_frame := model.global_basis.orthonormalized()*Basis(Vector3.UP,float(yaw) if yaw!=null else PI)
		var route: Array[Vector3] = []
		var authored_route: Variant = model.get("roof_access_route")
		if authored_route is Array:
			for waypoint: Vector3 in authored_route: route.append(model.to_global(waypoint)+Vector3.UP*.04)
		if route.is_empty() or not route[-1].is_equal_approx(point): route.append(point)
		var reachable := true
		var previous := origin+Vector3.UP*.04
		for waypoint: Vector3 in route:
			if not session.position_clear(waypoint) or not _sweep_clear(previous,waypoint):
				reachable = false
				break
			previous = waypoint
		if reachable and _ladder_fits(point,ladder_frame):
			access_definition = wanted
			access_owner = building_owner
			access_point = point
			access_frame = ladder_frame
			access_route = route
			_make_ladder()
		return
	var offsets: Array = [Vector3(2,0,-.5),Vector3(-2,0,-.5),Vector3(2.8,0,-1.4),Vector3(-2.8,0,-1.4),Vector3(1.4,0,-2.1),Vector3(-1.4,0,-2.1)] if wanted.owner=="service" else [Vector3.ZERO,Vector3(.65,0,0),Vector3(-.65,0,0)]
	for offset: Vector3 in offsets:
		var point := origin+frame*offset
		point.y += .04
		if not session.position_clear(point): continue
		var reach_origin := origin+Vector3.UP*.04
		if not _sweep_clear(reach_origin,point): continue
		var normal := (offset if offset.length_squared()>.1 else Vector3.BACK).normalized()
		var ladder_frame := frame*Basis(Vector3.UP,atan2(normal.x,normal.z))
		if not _ladder_fits(point,ladder_frame): continue
		access_definition = wanted
		access_owner = building_owner
		access_point = point
		access_frame = ladder_frame
		_make_ladder()
		return

func _physical_owner() -> Dictionary:
	var urban = session.urban_operations
	if urban==null: return {}
	var actor_position: Vector3 = session.world.player.global_position
	if is_instance_valid(urban.village) and is_instance_valid(urban.village.homes):
		var homes = urban.village.homes
		var index: int = homes.house_at(actor_position)
		if index>=0:
			var home_root: Node3D = homes.homes[index].root
			return {"definition":CATALOG.find("truckers_home_%d"%(index+1)),"owner":home_root,"point":home_root.to_global(Vector3(1.95,0,3.05)),"frame":home_root.global_basis}
		var tire := CATALOG.find("truckers_tire_shop")
		var tire_delta: Vector3 = actor_position-tire.exterior_position
		if absf(tire_delta.x)<7.1 and absf(tire_delta.z)<4.6 and absf(tire_delta.y)<2.2:
			return {"definition":tire,"owner":urban.village,"point":tire.exterior_position+Vector3(6.3,0,-1.6),"frame":Basis(Vector3.UP,PI*.5)}
	if is_instance_valid(urban.cargo_handling) and is_instance_valid(urban.cargo_handling.depot):
		var depot = urban.cargo_handling.depot
		if depot.inside(actor_position) and actor_position.y<2.2:
			return {"definition":CATALOG.find("vertice_roof"),"owner":depot,"point":depot.to_global(Vector3(29.05,0,28.3)),"frame":Basis(Vector3.UP,-PI*.5)}
	var northgate := CATALOG.find("northgate_auto_roof")
	var local: Vector3 = actor_position-northgate.exterior_position
	if absf(local.x)<northgate.size.x*.5-.5 and absf(local.z)<northgate.size.y*.5-.4 and absf(local.y)<2.2:
		return {"definition":northgate,"owner":session.controller.region,"point":northgate.exterior_position+Vector3(-2.45,0,northgate.size.y*.5-2.0),"frame":Basis(Vector3.UP,-PI*.5)}
	return {}

func _sweep_clear(from: Vector3, to: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = .32
	capsule.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.transform.origin = from+Vector3.UP*.89
	query.motion = to-from
	var result: PackedFloat32Array = session.world.get_world_3d().direct_space_state.cast_motion(query)
	return result[0]>.995

func _ladder_fits(point: Vector3, frame: Basis) -> bool:
	var box := BoxShape3D.new()
	box.size = Vector3(.9,2.35,.18)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = 1
	query.transform = Transform3D(frame,point+frame*Vector3(0,1.22,.74))
	return session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _make_ladder() -> void:
	access_visual = Node3D.new()
	access_visual.name = "RoofStair_"+str(access_definition.id)
	access_visual.transform = Transform3D(access_frame,access_point)
	session.world.add_child(access_visual)
	var material := MATERIALS.material("metal",Color("65736a"))
	for x in [-.40,.40]: _ladder_part(Vector3(x,1.22,.74),Vector3(.065,2.44,.075),material)
	for rung in 8: _ladder_part(Vector3(0,.20+rung*.29,.74),Vector3(.84,.06,.09),material)
	_ladder_part(Vector3(0,2.50,.74),Vector3(1.0,.14,.34),MATERIALS.material("stone",Color("99998b")))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.9,2.55,.20)
	collision.shape = shape
	collision.position = Vector3(0,1.275,.74)
	body.add_child(collision)
	access_visual.add_child(body)

func _ladder_part(at: Vector3, size: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = material
	access_visual.add_child(mesh)

func _release_access() -> void:
	if is_instance_valid(access_visual): access_visual.queue_free()
	access_visual = null
	access_owner = null
	access_definition = {}
	access_point = Vector3.INF
	access_route.clear()

func nearest_action() -> Dictionary:
	if session==null or _blocked(): return {}
	var player_position: Vector3 = session.world.player.global_position
	if is_active():
		if falling: return {}
		if player_position.distance_to(roof.to_global(roof.stair_point()))<1.55: return {"id":"service_roof_stairs","provider":self,"label":"Descer da cobertura"}
		return {}
	if is_instance_valid(access_visual) and player_position.distance_to(access_point)<1.55:
		return {"id":"service_roof_stairs","provider":self,"label":"Subir à cobertura"}
	return {}

func use_stairs() -> bool:
	if nearest_action().get("id","")!="service_roof_stairs": return false
	if is_active(): return await _descend()
	return await _ascend(access_definition,session.world.player.global_position,true)

func _source_context() -> Dictionary:
	return {"region":session.state.region_id,"place":session.state.place_id,"room":session.room,"epoch":_transition_epoch}

func _source_valid(token: int, context: Dictionary) -> bool:
	return session._owns_transition(token) and context.epoch==_transition_epoch and session.world.gameplay.health>0 and not session.rescue_pending and not session.arrest_pending and session.state.region_id==context.region and session.state.place_id==context.place and session.room==context.room

func _abort_transition(token: int, was_locked: bool, context: Dictionary) -> void:
	if session._owns_transition(token):
		await session.door_transition.fade_to(0.0,.2)
		if session._owns_transition(token):
			session._restore_transition_player_lock(was_locked,token)
			session._finish_transition(token)
	if context.epoch==_transition_epoch: busy = false

func _ascend(target: Dictionary, back: Vector3, autosave: bool) -> bool:
	if target.is_empty() or busy: return false
	var token: int = session._begin_transition("service_roof_stairs")
	if token<0: return false
	busy = true
	_transition_epoch += 1
	var context := _source_context()
	var actor = session.world.player
	var was_locked: bool = actor.input_locked
	actor.input_locked = true
	await session.door_transition.fade_to(1.0,.22)
	if not _source_valid(token,context):
		await _abort_transition(token,was_locked,context)
		return false
	var next: Node3D = ROOF.new()
	next.definition = target.duplicate(true)
	next.position = target.exterior_position+Vector3.UP*float(target.roof_height)
	next.rotation.y = float(target.exterior_rotation)
	session.world.add_child(next)
	session.controller.region.set_focus(target.exterior_position)
	for frame in 4:
		await get_tree().physics_frame
		if not _source_valid(token,context):
			next.queue_free()
			await _abort_transition(token,was_locked,context)
			return false
	_add_roof_obstacles(next,target)
	await get_tree().physics_frame
	if not _source_valid(token,context):
		next.queue_free()
		await _abort_transition(token,was_locked,context)
		return false
	var destination: Vector3 = next.to_global(next.stair_point()+Vector3.RIGHT*1.35+Vector3.UP*.04)
	if not session.position_clear(destination):
		next.queue_free()
		await _abort_transition(token,was_locked,context)
		return false
	owner_room = session.room
	definition = target
	return_position = back
	roof = next
	_saved_shelter = bool(actor.get_meta("mountain_shelter",false))
	if target.owner=="village_home": _saved_shelter = session.urban_operations.village.homes._previous_shelter
	elif target.owner=="vertice": _saved_shelter = session.urban_operations.cargo_handling.depot._previous_shelter
	_saved_camera = {"target":session.world.camera.target,"size":session.world.camera.target_size,"offset":session.world.camera.offset,"heading":session.world.camera.heading,"locked":session.world.camera.locked}
	_hide_owner_room(true)
	if target.owner=="village_home": session.urban_operations.village.homes._set_inside(-1)
	if target.owner=="vertice": session.urban_operations.cargo_handling.depot._set_inside(false)
	actor.set_meta("harbor_service_rooftop",true)
	actor.set_meta("mountain_shelter",false)
	actor.teleport(destination)
	_configure_camera()
	session.state.world_state.harbor_service_roof = {"id":str(target.id),"place":str(target.place),"return":[back.x,back.y,back.z]}
	session._sync_location_presentation()
	await session.door_transition.fade_to(0.0,.24)
	if not _source_valid(token,context):
		await _abort_transition(token,was_locked,context)
		return false
	session._restore_transition_player_lock(was_locked,token)
	session._finish_transition(token)
	busy = false
	if autosave: session.save_game()
	return true

func _add_roof_obstacles(destination: Node3D, target: Dictionary) -> void:
	var source: Node3D
	if target.id=="maciota": source = session.world.maciota_place.facade
	elif target.owner=="village_home": source = session.urban_operations.village.homes.homes[int(target.index)].root
	elif target.owner=="tire_shop": source = session.urban_operations.village
	elif target.owner=="vertice": source = session.urban_operations.cargo_handling.depot.building
	else:
		for candidate in get_tree().get_nodes_in_group("v2_walkin_facade"):
			if str(candidate.get_meta("place_id",""))==str(target.id):
				source = candidate.get_parent() if candidate.name=="WalkupDoor" else candidate
				break
	if source==null and target.owner=="northgate":
		for candidate in session.controller.region.find_children("*","Node3D",true,false):
			if candidate is UrbanBuildingBase and candidate.building_id=="MotorWorkshop":
				source = candidate
				break
	if source==null: return
	if target.owner=="vertice":
		var relative: Transform3D = destination.global_transform.affine_inverse()*source.global_transform
		var obstacle_index := 0
		for original: AABB in source.rooftop_obstacle_bounds:
			var bounds: AABB = relative*original
			if bounds.end.y<.12: continue
			bounds.size.y = bounds.end.y
			bounds.position.y = 0
			destination._box_solid("DepotRoofObject%d"%obstacle_index,bounds)
			obstacle_index += 1
		return
	var roots: Array[Node] = [source]
	for sibling in source.get_parent().get_children():
		var label := str(sibling.name)
		if label.begins_with("CityLook_") or label.begins_with("RoofNeon_") or label.begins_with("Billboard_"):
			roots.append(sibling)
	var serial := 0
	for root_node in roots:
		var visuals: Array[Node] = root_node.find_children("*","GeometryInstance3D",true,false)
		if root_node is GeometryInstance3D: visuals.append(root_node)
		for visual in visuals:
			if visual.is_queued_for_deletion(): continue
			var relative: Transform3D = destination.global_transform.affine_inverse()*visual.global_transform
			var volumes: Array[AABB] = []
			if visual is MeshInstance3D and visual.mesh!=null and visual.skin==null:
				volumes.append(relative*visual.mesh.get_aabb())
			elif visual is MultiMeshInstance3D and visual.multimesh!=null and visual.multimesh.mesh!=null:
				var batch: MultiMesh = visual.multimesh
				for index in batch.instance_count:
					volumes.append(relative*batch.get_instance_transform(index)*batch.mesh.get_aabb())
			for bounds: AABB in volumes:
				if bounds.end.y<.12 or bounds.size.y<.08 or bounds.size.x<.10 or bounds.size.z<.10: continue
				if bounds.size.x>target.size.x*.75 or bounds.size.z>target.size.y*.75: continue
				if bounds.position.x>target.size.x*.5 or bounds.end.x<-target.size.x*.5 or bounds.position.z>target.size.y*.5 or bounds.end.z<-target.size.y*.5: continue
				# Sibling batches also contain street furniture. Only roof-mounted
				# instances in this parcel become rooftop obstacles.
				if root_node!=source and bounds.position.y<-.45: continue
				bounds.size.y = bounds.end.y
				bounds.position.y = 0
				destination._box_solid("ExistingRoofDetail%d"%serial,bounds)
				serial += 1

func _hide_owner_room(hidden: bool) -> void:
	if not is_instance_valid(owner_room): return
	if definition.get("id","")=="maciota": owner_room.set_interior_active(not hidden)
	elif owner_room.has_method("set_active"): owner_room.set_active(not hidden)
	else: owner_room.visible = not hidden

func _configure_camera() -> void:
	var camera = session.world.camera
	camera.target = session.world.player
	camera.offset = camera.EXTERIOR_OFFSET
	camera.heading = session.saved_heading
	camera.target_size = definition.camera_size
	camera.size = definition.camera_size
	camera.locked = false
	camera.initialized = false
	camera.make_current()
	session.world.player.camera = camera
	camera._process(1.0)

func _descend() -> bool:
	if not is_active() or falling: return false
	var token: int = session._begin_transition("service_roof_return")
	if token<0: return false
	busy = true
	_transition_epoch += 1
	var context := _source_context()
	var actor = session.world.player
	var was_locked: bool = actor.input_locked
	actor.input_locked = true
	await session.door_transition.fade_to(1.0,.22)
	if not _source_valid(token,context):
		await _abort_transition(token,was_locked,context)
		return false
	_hide_owner_room(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not _source_valid(token,context):
		await _abort_transition(token,was_locked,context)
		return false
	var destination := return_position
	if not session.position_clear(destination):
		destination = owner_room.interior_spawn if definition.id=="maciota" and is_instance_valid(owner_room) else owner_room.spawn_position if is_instance_valid(owner_room) else access_point
	if not destination.is_finite() or not session.position_clear(destination):
		_hide_owner_room(true)
		await _abort_transition(token,was_locked,context)
		return false
	actor.teleport(destination)
	clear(false)
	await session.door_transition.fade_to(0.0,.22)
	if not session._owns_transition(token): return false
	session._restore_transition_player_lock(was_locked,token)
	session._finish_transition(token)
	busy = false
	session.save_game()
	return true

func restore_saved() -> bool:
	var saved: Dictionary = session.state.world_state.get("harbor_service_roof",{})
	if saved.is_empty(): return true
	if not CATALOG.valid_snapshot(saved): return false
	var target := CATALOG.find(str(saved.id))
	if str(session.state.place_id)!=str(target.place): return false
	var coordinates: Array = saved["return"]
	return await _ascend(target,Vector3(coordinates[0],coordinates[1],coordinates[2]),false)

func _begin_fall() -> void:
	if falling: return
	falling = true
	fall_peak = session.world.player.global_position.y
	session.world.player.set_meta("harbor_service_rooftop",false)
	if is_instance_valid(owner_room):
		if definition.id=="maciota": owner_room.set_interior_active(false)
		else: owner_room.queue_free()
	session._clear_service_npcs()
	session.room = null
	owner_room = null
	session.state.set_location("harbor")
	session.state.world_state.erase("harbor_service_roof")
	session.world.camera.target = session.world.player
	session.world.camera.offset = session.world.camera.EXTERIOR_OFFSET
	session.world.camera.target_size = session.saved_size
	session.world.camera.locked = false
	session._sync_location_presentation()
	session._refresh_routine_context()
	session.sync_dispatch_location()

func _tick_fall() -> void:
	var actor = session.world.player
	fall_peak = maxf(fall_peak,actor.global_position.y)
	if not actor.is_on_floor() or fall_peak-actor.global_position.y<.2: return
	var drop: float = fall_peak-actor.global_position.y
	clear(true)
	if session.world.gameplay.health>0: session.save_game()

func clear(interrupted := true) -> void:
	_transition_epoch += 1
	busy = false
	if interrupted: _release_access()
	if not is_active(): return
	_hide_owner_room(false)
	if is_instance_valid(roof): roof.queue_free()
	roof = null
	session.state.world_state.erase("harbor_service_roof")
	session.world.player.set_meta("harbor_service_rooftop",false)
	if not interrupted:
		session.world.player.set_meta("mountain_shelter",_saved_shelter)
		var camera = session.world.camera
		if is_instance_valid(_saved_camera.get("target")): camera.target = _saved_camera.target
		camera.offset = _saved_camera.get("offset",camera.EXTERIOR_OFFSET)
		camera.heading = float(_saved_camera.get("heading",0.0))
		camera.target_size = float(_saved_camera.get("size",24.0))
		camera.size = camera.target_size
		camera.locked = bool(_saved_camera.get("locked",false))
		camera.initialized = false
		if is_instance_valid(owner_room): session.anchor.position = owner_room.camera_target
		camera._process(1.0)
	definition = {}
	owner_room = null
	falling = false
	_scan = 0.0
	session._sync_location_presentation()
