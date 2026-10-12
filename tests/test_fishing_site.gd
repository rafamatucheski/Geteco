extends SceneTree
## Physical admission, swept pond guards, native people and visit lifecycle.
## Rendered depth, landscaping and performance are checked in the real session.
const SITE := preload("res://world/places/fishing/FishingSite.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var scene: Node3D
var site: Node3D
var actor: CharacterBody3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	print("FISHING_SITE ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Fishing site test timeout"); quit(3))
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	# Exactly the same flat land support used by Harbor; no bespoke helper path.
	var ground := StaticBody3D.new()
	ground.position = SITE.ANCHOR + Vector3(0,-.15,5)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(90,.3,80)
	shape.shape = box
	ground.add_child(shape)
	scene.add_child(ground)
	site = SITE.new()
	scene.add_child(site)
	site.finish_build()
	actor = ACTOR.new()
	actor.is_player = true
	actor.controlled_automatically = true
	actor.speed = 8.0
	actor.position = site.entrance_position()
	scene.add_child(actor)
	for frame in 8: await physics_frame
	var entrance_label: Label3D = site.get_node("LagoSerenoName")
	var approach: Vector2 = (SITE.LOCATION.ROAD_POINTS[-2] - SITE.LOCATION.ROAD_POINTS[-1]).normalized()
	check(entrance_label.basis.z.dot(Vector3(approach.x,0,approach.y)) > .999,"entrance portal faces the incoming road")
	check(site.anglers.size()==5,"five native anglers present")
	check(site.fishing_spots().size()>=3,"multiple free player stations")
	check(site.LOT.end.x < -430,"venue stays west of the existing company village and motocross grounds")
	var count: int = site.get_child_count()
	site.finish_build()
	check(site.get_child_count()==count and site.anglers.size()==5,"build is idempotent")
	check(_clear(site.entry_position(),[actor.get_rid()]),"reception admits the complete player capsule")
	check(await walk(site.entry_position()),"player walks entrance to reception")
	check(await walk(site.to_global(Vector3(3,.075,24))),"reception leaves past the counter edge")
	check(await walk(site.to_global(Vector3(0,.075,21))),"reception leaves toward pond on clear land")
	for index in site.fishing_spots().size():
		var spot: Dictionary = site.fishing_spots()[index]
		check(_clear(spot.position,[actor.get_rid()]),"station %d admits whole player capsule" % index)
		check(not site.contains_water(spot.position) and site.contains_water(spot.water),"station %d keeps feet dry and hook in water" % index)
		actor.global_position = spot.position+Vector3.UP*.025
		actor.velocity = Vector3.ZERO
		for frame in 4: await physics_frame
		var direction: Vector3 = spot.water-actor.global_position
		direction.y = 0
		check(actor.test_move(actor.global_transform,direction.normalized()*8),"player swept movement meets pond guard %d" % index)
		actor.automatic_direction = direction.normalized()
		for frame in 30: await physics_frame
		actor.automatic_direction = Vector3.ZERO
		check(not site.contains_water(actor.global_position),"player cannot walk onto pond %d" % index)
		check(actor.global_position.y>-.05,"player remains supported beside pond %d" % index)
	# Native civilian capsules use the same guards and occupy clear dry stations.
	for npc in site.anglers:
		check(_clear(npc.global_position,[npc.get_rid(),actor.get_rid()]),"native angler clear spawn "+str(npc.name))
		var toward: Vector3 = npc.water_target-npc.global_position
		toward.y = 0
		check(npc.test_move(npc.global_transform,toward.normalized()*7),"native angler swept guard "+str(npc.name))
		check(npc.person.hand_provider.is_valid(),"native angler holds rod with hand targets "+str(npc.name))
		check(not site.contains_water(npc.global_position),"native angler remains on shore "+str(npc.name))
	# Furniture tests protect actual volume coverage, not just collision counts.
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3
	capsule.height = 1.7
	for solid in site.solid_inventory:
		if solid.id not in ["PicnicTable","AnglerBench","FishBucket","TreeTrunk"]: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.collision_mask = 1
		var forward: Vector3 = solid.basis.z
		query.transform = Transform3D(Basis.IDENTITY,site.to_global(solid.position)+forward*(solid.size.z*.5+1)+Vector3.UP*.86)
		# Place feet at ground level, separately from the prop's centre height.
		query.transform.origin.y = site.global_position.y+.88
		query.motion = -forward*(solid.size.z+2)
		var result := scene.get_world_3d().direct_space_state.cast_motion(query)
		check(result[0]<1,"solid furniture swept volume "+str(solid.id))
	site.set_focus(SITE.ANCHOR+Vector3(150,0,0))
	check(site.anglers.all(func(npc): return not npc.is_physics_processing() and not npc.person.is_processing()),"distant native people suspend physics and pose")
	site.set_focus(SITE.ANCHOR)
	check(site.anglers.all(func(npc): return npc.is_physics_processing() and npc.person.is_processing()),"returning resumes anglers")
	site.queue_free()
	await process_frame
	await process_frame
	check(get_nodes_in_group("fishing_angler").is_empty(),"leaving frees all five native people")
	site = SITE.new()
	scene.add_child(site)
	site.finish_build()
	for frame in 4: await physics_frame
	check(get_nodes_in_group("fishing_angler").size()==5,"revisit recreates one population without duplicates")
	print("FISHING_SITE_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _clear(point: Vector3,excluded: Array[RID]) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 3
	query.exclude = excluded
	query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*.87)
	return scene.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func walk(point: Vector3) -> bool:
	for frame in 300:
		var direction := point-actor.global_position
		direction.y = 0
		if direction.length()<.22: break
		actor.automatic_direction = direction.normalized()
		await physics_frame
	actor.automatic_direction = Vector3.ZERO
	var error := actor.global_position-point
	error.y = 0
	return error.length()<.35
