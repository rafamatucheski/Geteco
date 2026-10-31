extends SceneTree
const SITE := preload("res://world/places/amusement_park/ParkLume.gd")
const CLOWN := preload("res://activities/amusement_park/ParkClown.gd")
const LIFE := preload("res://activities/amusement_park/AmusementParkLife.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const LAYOUT := preload("res://world/places/amusement_park/AmusementParkLayout.gd")
const VENDING := preload("res://activities/amusement_park/AmusementParkVending.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PARK_DRESSING ","PASS " if ok else "FAIL ",label)

func clear(actor: CharacterBody3D, point: Vector3) -> bool:
	var shape := actor.get_child(0) as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = Transform3D(Basis.IDENTITY,point+shape.position)
	query.collision_mask = 1
	return actor.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var park := SITE.new()
	stage.add_child(park)
	var clowns: Array[CharacterBody3D] = []
	for index in 4:
		var actor := CLOWN.new()
		actor.configure({"id":"fixture_clown_%d"%index,"position":park.to_global(LIFE.ROUTES[index][0]),"kind":"park_clown","worker_index":index})
		for point: Vector3 in LIFE.ROUTES[index]: actor.patrol.append(park.to_global(point))
		stage.add_child(actor)
		actor.set_physics_process(false)
		clowns.append(actor)
	var player := ACTOR.new()
	player.is_player = true
	stage.add_child(player)
	player.set_physics_process(false)
	for frame in 4: await physics_frame
	var relevant := 0
	var solids: Node = park.get_node("ParkSolids")
	for solid: Dictionary in park.solid_inventory:
		var id: String = solid.id
		if not (id.begins_with("Lume") or id in ["BuntingPole","CartCanopyPost","BalloonStand","UmbrellaPole"]): continue
		relevant += 1
		var covered := false
		for collision: CollisionShape3D in solids.get_children():
			if str(collision.get_meta("interior_solid_id","")) != id: continue
			var size: Vector3 = collision.shape.size
			var actual: AABB = collision.transform*AABB(-size*.5,size)
			if actual.grow(.001).encloses(solid.bounds): covered = true; break
		check(covered,"authored physical coverage: "+id)
	check(relevant >= 45,"new furniture has complete independently classified solid inventory")
	for actor in [player,clowns[0]]:
		# A circulação estática independe de um morador móvel ocupando a faixa.
		actor.collision_mask = 1
		var who := "Dante" if actor == player else "native clown"
		for local in [Vector3(40,.08,16),Vector3(-7,.16,15),Vector3(20,.08,-2.2),Vector3(29,.08,20),Vector3(-31,.08,27),Vector3(28,.08,27),Vector3(-2,.08,-28),Vector3(31,.08,-3),VENDING.MACHINES.drinks.approach,VENDING.MACHINES.snacks.approach]:
			check(clear(actor,park.to_global(local)),who+" interaction body remains clear "+str(local))
		for segment in [[Vector3(40,.08,15),Vector3(-3.5,.08,15)],[Vector3(20,.08,15),Vector3(20,.08,-2.2)],[Vector3(29,.08,15),Vector3(29,.08,20)]]:
			var pose := Transform3D(Basis.IDENTITY,park.to_global(segment[0]))
			check(not actor.test_move(pose,segment[1]-segment[0]),who+" public promenade remains traversable")
		var swept := 0
		for solid: Dictionary in park.solid_inventory:
			var id: String = solid.id
			if not id.begins_with("Lume"): continue
			var bounds: AABB = solid.bounds
			if bounds.position.y>2 or bounds.end.y<.2: continue
			for direction in [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]:
				var extent: float = bounds.size.x*.5 if absf(direction.x)>.5 else bounds.size.z*.5
				var start: Vector3 = bounds.get_center()+direction*(extent+.75)
				start.y = .08
				if not clear(actor,park.to_global(start)): continue
				var pose := Transform3D(Basis.IDENTITY,park.to_global(start))
				check(actor.test_move(pose,-direction*(extent*2+1.5)),who+" large displacement blocks "+id)
				swept += 1
		check(swept>=35,who+" exercised table stall machine and planter edges")
	for index in 4:
		var actor := clowns[index]
		actor.collision_mask = 1
		var route: Array = LIFE.ROUTES[index]
		for j in route.size():
			var pose := Transform3D(Basis.IDENTITY,park.to_global(route[j]))
			check(clear(actor,pose.origin),"clown %d route body clearance %d"%[index,j])
			check(not actor.test_move(pose,route[(j+1)%route.size()]-route[j]),"clown %d full swept patrol leg %d"%[index,j])
		actor.collision_mask = 7
		actor.set_physics_process(true)
	var start: Array = []
	for actor in clowns: start.append(actor.global_position)
	for frame in 180: await physics_frame
	for index in 4:
		var actor := clowns[index]
		check(actor.global_position.distance_to(start[index])>1.0 and actor.travelled>1.0,"clown %d actually walks with collision and native gait"%index)
		check(actor.global_position.y<.10 and actor.model.head_node != null,"clown %d remains supported with articulated head"%index)
	stage.free()
	await process_frame
	check(get_nodes_in_group("park_clown").is_empty(),"unload releases all four clown bodies")
	print("PARK_DRESSING_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
