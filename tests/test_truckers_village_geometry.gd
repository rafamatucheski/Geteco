extends SceneTree
const VILLAGE := preload("res://gameplay/urban_v1/TruckersVillageVisuals.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var village := VILLAGE.new()
	scene.add_child(village)
	# This geometry fixture has no terrain; gait/gravity use the resident test.
	village.tonico.set_physics_process(false)
	for frame in 3: await physics_frame
	check(village.houses.size()==6,"Six accessible homes compose the village")
	check(village.solids.size()==village.placements.size(),"All solid identities have physics inventory")
	check(village.find_children("*","Light3D",true,false).is_empty(),"Only pooled light fittings, no permanent light sources")
	check(village.tonico.position.is_equal_approx(VILLAGE.TONICO_POINT-VILLAGE.ORIGIN),"Tonico stands in authored open position")
	var home_bodies: Array = village.solids.filter(func(body): return body.get_meta("interior_solid_id")=="VillageHouse")
	for body in home_bodies:
		var facing: Vector3 = body.basis*Vector3.FORWARD*-1
		var toward_court: Vector3 = Vector3(-15,0,0)-body.position
		toward_court.y = 0
		check(facing.dot(toward_court.normalized())>.35,"Home frontage faces shared courtyard")
	var required_details := ["YardFence","WaterTankStand","RaisedVegetableBed","CoveredFirewood","BackyardWorkbench","RainBarrel","PorchPlantPot","ClotheslinePole"]
	for id in required_details:
		check(village.solids.any(func(body): return body.get_meta("interior_solid_id")==id),"Physical household detail: "+id)
	for player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player = player
		actor.controlled_automatically = true
		actor.position = Vector3(-200,.04,200)
		scene.add_child(actor)
		actor.set_physics_process(false)
		for frame in 2: await physics_frame
		var who := "Player" if player else "NPC"
		for route in [[Vector3(40,0,-90),Vector3(40,0,-12)],[Vector3(40,0,0),Vector3(-55,0,0)],[Vector3(-55,0,0),Vector3(-67,0,25)],[Vector3(40,0,0),Vector3(40,0,27)],[Vector3(40,0,27),Vector3(60,0,27)],[Vector3(61,0,5),Vector3(61,0,-5)]]:
			var start: Vector3 = route[0]+VILLAGE.ORIGIN+Vector3.UP*.04
			check(not actor.test_move(Transform3D(Basis.IDENTITY,start),route[1]-route[0]),who+" clear path "+str(route))
		for hit in [[Vector3(-73,0,-12),Vector3(0,0,-12),"House"],[Vector3(-32.68,0,-9),Vector3(0,0,-7),"Pump"],[Vector3(-39,0,-23),Vector3(0,0,-6),"Bench"],[Vector3(58,0,27),Vector3(0,0,-12),"FarmCart"],[Vector3(55.2,0,2),Vector3(0,0,-7),"Tires"]]:
			actor.position = hit[0]+VILLAGE.ORIGIN+Vector3.UP*.04
			var result := actor.move_and_collide(hit[1])
			check(result != null,who+" swept collision "+hit[2])
			check(is_equal_approx(actor.position.y,.04),who+" remains on ground against "+hit[2])
		# Each yard has an open gate and a clear centre leading to the veranda.
		# Test actual bodies against a rotated home's front, not an axis-aligned proxy.
		for home in home_bodies:
			var approach: Vector3 = home.position+home.basis*Vector3(0,0,8.5)
			approach.y = .04
			actor.position = approach+VILLAGE.ORIGIN
			var motion: Vector3 = home.basis*Vector3(0,0,-6)
			var contact := actor.move_and_collide(motion)
			check(contact!=null and contact.get_collider()==home,who+" stops at rotated home wall with central porch clear")
		for detail in [["WaterTankStand",Vector3(1,0,0)],["RaisedVegetableBed",Vector3(-1,0,0)],["CoveredFirewood",Vector3(-1,0,0)],["BackyardWorkbench",Vector3(1,0,0)],["RainBarrel",Vector3(0,0,-1)],["PorchPlantPot",Vector3(0,0,1)],["YardFence",Vector3(-1,0,0)]]:
			var body: StaticBody3D = village.solids.filter(func(candidate): return candidate.get_meta("interior_solid_id")==detail[0])[0]
			var shape: BoxShape3D = body.get_child(0).shape
			var axis: Vector3 = detail[1]
			var extent: float = absf(axis.x)*shape.size.x*.5+absf(axis.z)*shape.size.z*.5
			var outward: Vector3 = body.basis*axis
			var start: Vector3 = body.global_position+outward*(extent+.48)
			start.y = .04
			actor.position = start
			var collision := actor.move_and_collide(-outward*1.1)
			check(collision!=null and collision.get_collider()==body,who+" swept physical yard prop "+detail[0])
		actor.free()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .32
	capsule.height = 1.8
	for point in [VILLAGE.TONICO_POINT,VILLAGE.PUMP_POINT,VILLAGE.BELT_POINT,VILLAGE.CRANK_POINT]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform.origin = point+Vector3(0,.94,1.2)
		query.collision_mask = 1
		check(scene.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),"Full body fits approach "+str(point))
	var truck := BoxShape3D.new()
	truck.size = Vector3(2.8,3.6,8.4)
	for route in [[Vector3(40,0,-60),Vector3(40,0,-38)],[Vector3(44,0,-60),Vector3(44,0,-38)],[Vector3(48,0,-60),Vector3(48,0,-38)]]:
		var motion: Vector3 = route[1]-route[0]
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = truck
		query.transform = Transform3D(Basis.looking_at(motion.normalized()),route[0]+VILLAGE.ORIGIN+Vector3.UP*1.9)
		query.motion = motion
		query.collision_mask = 1
		var result := scene.get_world_3d().direct_space_state.cast_motion(query)
		check(result[0]<.999,"Timber bollards prevent vehicle entry "+str(route))
	village.set_cutaway(true)
	for mesh in village._roof.get_children():
		check(mesh.visible and mesh.material_override.albedo_color.a<.15,"Roof becomes translucent, keeping actor and objects readable")
	village.set_cutaway(false)
	for mesh in village._roof.get_children():
		check(mesh.material_override.albedo_color.a==1,"Roof restores opaque outside the station")
	check(village.get_meta("wild_grass_points").size()>1500,"Real grass geometry fills garden patches")
	village.set_part_collected("belt",true)
	check(not village.parts.belt.visible and village.parts.crank.visible,"Collected part hidden independently")
	village.set_region_active(false)
	for body in village.solids: check(body.collision_layer==0,"Inactive collision "+body.name)
	village.set_region_active(true)
	check(village.visible and village.solids[0].collision_layer==1,"Region reactivation")
	print("TRUCKERS_VILLAGE_GEOMETRY checks=",checks," failures=",failures)
	scene.free()
	quit(0 if failures.is_empty() else 1)
