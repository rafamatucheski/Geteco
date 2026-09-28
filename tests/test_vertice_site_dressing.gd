extends SceneTree
## Only the new dressing is present: clearance queries cannot be masked by
## existing architecture, guard booths or the known dock-handling machinery.
const DRESSING := preload("res://gameplay/urban_v1/VerticeSiteDressing.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const ROUTES := preload("res://gameplay/urban_v1/PortHaulRoutes.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var dressing := DRESSING.new()
	scene.add_child(dressing)
	for frame in 3: await physics_frame
	check(dressing.solids.size()>40,"New occupied work zones have physical solids")
	check(dressing.placements.size()==dressing.solids.size(),"Every solid has an authored validation footprint")
	check(dressing.find_children("*","Light3D",true,false).is_empty(),"Dressing introduces no real-time light sources")
	for body in dressing.solids: check(body.has_meta("interior_solid_id"),"Solid identity "+body.name)
	var walks := [
		[Vector3(-43,0,44),Vector3(-43,0,-24)],
		[Vector3(-43,0,-24),Vector3(44,0,-24)],
		[Vector3(44,0,-24),Vector3(44,0,56)],
		[Vector3(44,0,56),Vector3(-43,0,56)],
		[Vector3(10,0,73),Vector3(10,0,66)],
		[Vector3(24,0,45),Vector3(38,0,45)],
		[Vector3(0,0,3),Vector3(0,0,-12)],
		[Vector3(35,0,27),Vector3(35,0,3)],
		[Vector3(35,0,8),Vector3(24,0,8)],
		[Vector3(24,0,8),Vector3(24,0,-16)],
		[Vector3(-24,0,-10),Vector3(-24,0,-14.2)],
		[Vector3(-25,0,12),Vector3(25,0,12)],
		[Vector3(-30,0,34),Vector3(43,0,34)]]
	for player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player = player
		actor.controlled_automatically = true
		actor.position = Vector3(100,.04,100)
		scene.add_child(actor)
		actor.set_physics_process(false)
		var who := "Player" if player else "NPC"
		for frame in 2: await physics_frame
		for walk in walks:
			check(not actor.test_move(Transform3D(Basis.IDENTITY,walk[0]+Vector3.UP*.04),walk[1]-walk[0]),who+" can traverse authored route "+str(walk))
		for blocker in [
			[Vector3(-23,.04,40),Vector3(0,0,6),"central loaded pallet"],
			[Vector3(-19,.04,50),Vector3(0,0,-4),"empty pallet stack"],
			[Vector3(-46.5,.04,61),Vector3(0,0,7),"waste container"],
			[Vector3(32,.04,17),Vector3(-5,0,0),"kitchen counter"],
			[Vector3(32,.04,20.7),Vector3(-5,0,0),"refrigerator"],
			[Vector3(47.5,.04,13),Vector3(0,0,7),"maintenance workbench"],
			[Vector3(27.5,.04,68),Vector3(0,0,6),"rest table"]]:
			actor.position = blocker[0]
			var hit := actor.move_and_collide(blocker[1])
			check(hit != null,who+" swept actual motion stops at "+blocker[2])
			check(is_equal_approx(actor.position.y,.04),who+" is not lifted onto "+blocker[2])
		actor.position = Vector3(100,.04,100)
		var capsule := CapsuleShape3D.new()
		capsule.radius=.3
		capsule.height=1.7
		for point in [Vector3(35,.9,3),Vector3(0,.9,-16),Vector3(-24,.9,-14.2),Vector3(-24,.9,-15.7)]:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape=capsule
			query.transform.origin=point
			query.collision_mask=1
			check(scene.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),who+" full body fits pickup/hatch "+str(point))
		actor.free()
	var truck_shape := BoxShape3D.new()
	truck_shape.size=Vector3(2.72,3.6,8.4)
	for index in 3:
		var dock := Vector3(-18+index*18,0,34)
		var routes := [
			ROUTES.rounded(PackedVector3Array([Vector3(0,0,78),Vector3(0,0,64),Vector3(-37,0,56),Vector3(-37,0,34),dock])),
			ROUTES.rounded(PackedVector3Array([dock,Vector3(36,0,34),Vector3(39,0,50),Vector3(-3,0,64),Vector3(-3,0,78)]))]
		for route in routes:
			for i in route.size()-1:
				var direction: Vector3=route[i+1]-route[i]
				if direction.length_squared()<.0001: continue
				var query:=PhysicsShapeQueryParameters3D.new()
				query.shape=truck_shape
				query.transform=Transform3D(Basis.looking_at(direction.normalized()),route[i]+Vector3.UP*1.9)
				query.motion=direction
				query.collision_mask=1
				var travel:=scene.get_world_3d().direct_space_state.cast_motion(query)
				check(travel[0]>=.999,"Loaded truck swept clearance bay%d segment%d"%[index,i])
	dressing.set_cutaway(true)
	check(not dressing.roof_parts[0].visible,"Break shelter can reveal seated occupants")
	dressing.set_region_active(false)
	for body in dressing.solids: check(body.collision_layer==0,"Inactive region releases detail collision")
	dressing.set_region_active(true)
	check(dressing.visible and dressing.solids[0].collision_layer==1,"Region activation restores render and collision")
	print("VERTICE_SITE_DRESSING checks=",checks," solids=",dressing.solids.size()," failures=",failures)
	scene.free()
	quit(0 if failures.is_empty() else 1)
