extends SceneTree
## Real Actor capsule sweeps through the continuous Vértice building.
const BUILDING := preload("res://gameplay/urban_v1/PortDepotBuilding.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)
func sweep(actor: CharacterBody3D, start: Vector3, motion: Vector3) -> bool:
	return actor.test_move(Transform3D(Basis.IDENTITY, start), motion)
func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var depot := BUILDING.new()
	scene.add_child(depot)
	for frame in 3: await physics_frame
	check(depot.solids.size() >= 80, "Walls, furniture, shelves and docks have physical solids")
	for solid in depot.solids: check(solid.has_meta("interior_solid_id"), "Solid identity: " + solid.name)
	check(depot.dock_doors.size() == 3, "Three independently opening freight doors")
	for player in [true, false]:
		var actor := ACTOR.new()
		actor.is_player = player
		actor.controlled_automatically = true
		actor.position = Vector3(100, .04, 100)
		scene.add_child(actor)
		actor.set_physics_process(false)
		var who := "Player" if player else "NPC"
		for frame in 2: await physics_frame
		for blocked in [
			[Vector3(-26,.04,0),Vector3(-10,0,0),"west wall"],
			[Vector3(0,.04,-17),Vector3(0,0,-30),"rear wall against large displacement"],
			[Vector3(40,.04,26),Vector3(8,0,0),"office east wall"],
			[Vector3(-19,.04,0),Vector3(0,0,-7),"loaded rack"],
			[Vector3(35,.04,14),Vector3(6,0,0),"first desk"],
			[Vector3(35,.04,21),Vector3(6,0,0),"second desk"],
			[Vector3(-23,.04,-15),Vector3(0,0,-5),"packing bench"]]:
			check(sweep(actor,blocked[0],blocked[1]), who + " cannot cross " + blocked[2])
		actor.position = Vector3(-19,.04,0)
		var impact := actor.move_and_collide(Vector3(0,0,-12))
		check(impact != null and actor.position.z > -2.5, who + " actual motion stops at rack")
		check(is_equal_approx(actor.position.y,.04), who + " collision never lifts onto furniture")
		actor.position = Vector3(100,.04,100)
		depot.set_office_open(0)
		for frame in 2: await physics_frame
		check(sweep(actor,Vector3(35,.04,33),Vector3(0,0,-6)),who + " closed office blocks entry")
		depot.set_office_open(1)
		for frame in 2: await physics_frame
		for clear in [
			[Vector3(35,.04,33),Vector3(0,0,-7),"open level office entry"],
			[Vector3(35,.04,27),Vector3(0,0,-24),"office corridor to reward"],
			[Vector3(35,.04,8),Vector3(-12,0,0),"office to warehouse passage"],
			[Vector3(24,.04,8),Vector3(0,0,-24),"warehouse east corridor"],
			[Vector3(0,.04,-16),Vector3(0,0,31),"warehouse central corridor"],
			[Vector3(-25,.04,8),Vector3(50,0,0),"interior access to all docks"],
			[Vector3(-30,.04,34),Vector3(73,0,0),"unobstructed external apron"]]:
			check(not sweep(actor,clear[0],clear[1]), who + " can traverse " + clear[2])
		var actor_shape: CollisionShape3D
		for child in actor.get_children():
			if child is CollisionShape3D:
				actor_shape = child
				break
		for point in [Vector3(35,.04,3),Vector3(0,.04,-16)]:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = actor_shape.shape
			query.transform = Transform3D(Basis.IDENTITY,point + actor_shape.position)
			query.collision_mask = 1
			query.exclude = [actor.get_rid()]
			check(scene.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),who + " whole capsule fits reward " + str(point))
		for index in 3:
			var x := float(index-1)*18.0
			depot.set_dock_open(index,0)
			for frame in 2: await physics_frame
			check(sweep(actor,Vector3(x,1.14,21),Vector3(0,0,-6)),who + " closed shutter blocks dock " + str(index))
			depot.set_dock_open(index,1)
			for frame in 2: await physics_frame
			check(not sweep(actor,Vector3(x,1.14,21),Vector3(0,0,-6)),who + " raised shutter clears dock " + str(index))
		depot.set_cutaway(true)
		check(not depot.roof_parts[0].visible and not depot.facade_parts[0].visible,"Cutaway reveals interior")
		check(sweep(actor,Vector3(-26,.04,0),Vector3(-10,0,0)),who + " cutaway preserves wall physics")
		depot.set_cutaway(false)
		actor.free()
	print("PORT_DEPOT checks=",checks," failures=",failures)
	scene.free()
	quit(0 if failures.is_empty() else 1)
