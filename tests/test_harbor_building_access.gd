extends SceneTree
## Logical/physical coverage; rendered depth and frame time are separate gates.
const CATALOG = preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const ACCESS = preload("res://world/places/harbor_buildings/HarborBuildingExteriorAccess.gd")
const FACTORY = preload("res://world/urban_detail/UrbanBuildingFactory.gd")
const ROOFTOP = preload("res://world/places/harbor_buildings/HarborBuildingRooftop.gd")
var failures: Array[String] = []
var checks := 0
var completed_facades := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var definitions := CATALOG.definitions()
	check(definitions.size()>=57,"The effective catalog covers all 52 generic city buildings and 5 southern port buildings")
	check(CATALOG.for_source("FreightDepot").is_empty(),"Deleted frontage is absent")
	check(CATALOG.for_source("MotorWorkshop").is_empty(),"Northgate keeps its existing service owner")
	var identifiers := {}
	var receipts := {}
	for definition in definitions:
		check(not identifiers.has(definition.id),"Unique place "+str(definition.id))
		identifiers[definition.id] = true
		check(definition.floor_count>=1 and definition.roof_height>0,"Floor and roof datum "+str(definition.id))
		for reward in definition.rewards:
			check(not receipts.has(reward.id),"Unique persistent reward "+str(reward.id))
			receipts[reward.id] = true
		check(CATALOG.valid_floors({definition.id:definition.floor_count}),"Rooftop is a restorable floor "+str(definition.id))
	var room := Node3D.new()
	root.add_child(room)
	for source_id in ["NorthFrontage5","CanalHomesEast","FoundryLofts","PorchHouse","new_1790426066_503_97028106"]:
		var definition := CATALOG.for_source(source_id)
		if definition.is_empty(): continue
		await _check_facade(room,definition)
	check(completed_facades==5,"All five facade fixtures reached their final physical assertion")
	await _check_rooftops(room,definitions)
	room.queue_free()
	await process_frame
	print(JSON.stringify({"test":"harbor_building_access","checks":checks,"failures":failures,"places":definitions.size()}))
	quit(0 if failures.is_empty() else 1)

func _check_facade(parent: Node3D, definition: Dictionary) -> void:
	var data := {"id":definition.source_id,"position":definition.facade_position,"size":definition.size,"kind":definition.building_kind,"height_override":definition.storey_height*definition.floor_count}
	if definition.building_kind == "cobra_house": data.size.y += 1.8
	if definition.building_kind == "l_shaped_block": data.size.y /= .55
	var art := FACTORY.populate_chunk(parent,data)
	art.rotation.y = definition.exterior_rotation
	var access := ACCESS.install(art,str(definition.source_id))
	await physics_frame
	access.set_open_amount(1.0)
	# Fachada pintada: a folha da entrada é sólida fechada e só gira quando o jogador
	# chega (PaintedDoor). Aqui ninguém chega; abre como o jogador abriria. Porta dupla
	# (Customs House pintada): set_open_amount não puxa a parceira, então abre Door2 também.
	for door in art.find_children("Door*","",true,false):
		if door.get_parent().has_meta("walk_in") and door.has_method("set_open_amount"): door.set_open_amount(1.0)
	await physics_frame
	await physics_frame
	check(access.access_ready,"Facade admits a prepared room "+str(definition.id))
	var shape := CapsuleShape3D.new()
	shape.radius = .30
	shape.height = 1.78
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY,access.to_global(definition.entrance_local+Vector3(0,.96,1.0)))
	query.motion = access.global_basis*Vector3(0,0,-2.5)
	var sweep: PackedFloat32Array = parent.get_world_3d().direct_space_state.cast_motion(query)
	check(sweep[0]>.995,"Swept human capsule crosses the actual doorway "+str(definition.id))
	query.motion = Vector3.ZERO
	query.transform.origin = access.to_global(Vector3(0,.96,0))
	check(parent.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(),"Main body is hollow "+str(definition.id))
	access.set_floor_view(0,float(definition.storey_height),false)
	access.set_floor_view(int(definition.floor_count),float(definition.storey_height),true)
	access.restore_exterior()
	await physics_frame
	await physics_frame
	check(not access.access_ready,"Closing access returns ownership to the original facade "+str(definition.id))
	completed_facades += 1
	art.queue_free()
	await physics_frame
	await process_frame

func _check_rooftops(parent: Node3D, definitions: Array[Dictionary]) -> void:
	# Every distinct parcel must have a valid landing, pickup and guarded edge.
	for definition in definitions:
		var roof := ROOFTOP.new()
		roof.definition = definition.duplicate(true)
		roof.definition.rewards = preload("res://world/places/harbor_buildings/HarborBuildingContent.gd").floor_rewards(definition,int(definition.floor_count))
		roof.position = Vector3(0,float(definition.roof_height),0)
		parent.add_child(roof)
		check(roof.is_floor_clear(roof.landing_point(),.32),"Roof landing is clear "+str(definition.id))
		check(roof.is_floor_clear(roof.jump_point,.32),"Jump approach is clear "+str(definition.id))
		check(roof.reward_points.size()==1,"Roof cache has a reachable location "+str(definition.id))
		for reward in roof.reward_points: check(roof.is_floor_clear(roof.to_local(reward.position),.32),"Roof cache clear "+str(definition.id))
		check(roof._jump_gate.collision_layer==1,"Roof rail remains solid for physical traversal "+str(definition.id))
		roof.queue_free()
		await process_frame
