extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func run() -> void:
	var region = preload("res://world/regions/NativeRegion.gd").build_region("harbor",Vector3(202,0,219))
	root.add_child(region)
	region.set_process(false)
	var safety = region.coastal_protection
	check(safety.boundaries.size()>20,"Coastal inventory must include exposed banks")
	region.free() # Isola as varreduras das barreiras dos prédios e dos trilhos pré-existentes.
	var fixture := Node3D.new()
	root.add_child(fixture)
	var foundry := preload("res://world/urban_detail/HarborBridge3D.gd").new()
	foundry.position = Vector3(3790.0/16,0,400.0/16)
	fixture.add_child(foundry)
	for key in safety.cells:
		safety.build_chunk(fixture,Rect2(key.x*64,key.y*64,64,64))
	var actors: Array[CharacterBody3D] = []
	for player in [true,false]:
		var actor = preload("res://scripts/Actor.gd").new()
		actor.is_player = player
		fixture.add_child(actor)
		actor.set_physics_process(false)
		actor.position = Vector3(0,50+actors.size()*5,0)
		actors.append(actor)
	var car := preload("res://scripts/Vehicle.gd").new()
	fixture.add_child(car)
	car.set_physics_process(false)
	car.position = Vector3(0,70,0)
	actors.append(car)
	for i in 3: await physics_frame
	var styles := {}
	for edge in safety.boundaries:
		styles[edge.style] = true
		var outward := Vector3(edge.outward.x,0,edge.outward.y)
		var midpoint: Vector2 = (edge.a+edge.b)*0.5
		for actor in actors:
			# O casco paralelo começa do lado seco mesmo na passarela de 4.5m do porto.
			var origin := Vector3(midpoint.x,0.06,midpoint.y)-outward*1.7
			var pose := Transform3D(Basis(Vector3.UP,atan2(outward.z,-outward.x)),origin)
			var collision := KinematicCollision3D.new()
			# Em cantos côncavos curtos um carro já encontra o trilho vizinho.
			# Inclui contatos de recuperação, mas só um sólido costeiro real pode passar.
			var blocked := actor.test_move(pose,outward*4.0,collision,0.001,true)
			check(blocked and str(collision.get_collider().name).begins_with("CoastalBarrierSolid"),"Unprotected coast %s actor %s"%[midpoint,actor.name])
	check(styles.size()==4,"Four environmental protection styles")
	var space := fixture.get_world_3d().direct_space_state
	# Uma calçada seca real acima do canal, além do colisor do asfalto.
	var support := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(230,2,30),Vector3(230,-2,30),1))
	check(not support.is_empty(),"Foundry bridge sidewalk must support actors before rail")
	check(not car.test_move(Transform3D(Basis(Vector3.UP,PI*0.5),Vector3(269,0.06,25)),Vector3(12,0,0)),"Foundry east abutment must not block the full vehicle hull")
	# Portais de embarque e ligações de rua precisam continuar livres na altura do tronco.
	for route in [
		[Vector3(198,0.7,110),Vector3(212,0.7,110)],
		[Vector3(265.6,0.7,201),Vector3(265.6,0.7,194)],
		[Vector3(195,0.7,25),Vector3(280,0.7,25)],
		[Vector3(206.875,0.7,152),Vector3(206.875,0.7,203)]]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(route[0],route[1],1))
		check(hit.is_empty(),"Protection must preserve passage %s hit %s"%[route,hit])
		var start: Vector3 = route[0]
		start.y = 0.06
		check(not actors[0].test_move(Transform3D(Basis.IDENTITY,start),route[1]-route[0]),"Full player capsule must fit passage %s"%[route])
	for access in preload("res://world/places/PlaceCatalog.gd").access_points():
		if access.region != "harbor": continue
		for point: Vector3 in [access.position,access.return_position]:
			check(not actors[0].test_move(Transform3D(Basis.IDENTITY,point+Vector3.UP*0.06),Vector3.ZERO,null,0.001,true),"Coastal barrier obstructs access/return "+access.id)
	# A ponte compartilhada tinha um vão de 12.5 m na junção oeste da proteção.
	var connection := preload("res://world/regions/WorldConnection3D.gd").new()
	fixture.add_child(connection)
	for i in 2: await physics_frame
	for x in [457.0,463.0,468.0,565.0]:
		for side in [-1,1]:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,0.7,-285+side*5),Vector3(x,0.7,-285+side*10),1))
			check(not hit.is_empty(),"Bridge rail gap at %s side %s"%[x,side])
	# Full authored ship geometry must leave its southern walkway mouth open.
	var native_ship = preload("res://world/regions/NativeRegion.gd").new()
	native_ship.source_data = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json"))
	native_ship._build_ship(fixture)
	native_ship.free()
	for i in 2: await physics_frame
	check(not actors[0].test_move(Transform3D(Basis.IDENTITY,Vector3(223.125,0.06,130)),Vector3(0,0,5)),"Northstar stern walkway capsule clearance")
	print("COASTAL_PROTECTION checks=",checks," failures=",failures," edges=",safety.boundaries.size()," cells=",safety.cells.size()," styles=",styles.keys())
	fixture.free()
	await process_frame
	quit(0 if failures==0 else 1)
