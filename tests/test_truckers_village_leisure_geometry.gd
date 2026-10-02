extends SceneTree
## Real production capsules and swept physics; rendering/occlusion is a separate
## Main-scene capture. This fixture deliberately has no terrain or gravity tick.
const VILLAGE := preload("res://gameplay/urban_v1/TruckersVillageVisuals.gd")
const ART := preload("res://gameplay/urban_v1/TruckersVillageLeisureArt.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const RESIDENT := preload("res://gameplay/urban_v1/TruckersVillageResident.gd")
const RESIDENTS := preload("res://gameplay/urban_v1/TruckersVillageResidents.gd")
const NEW_SOLIDS := [
	"HorseshoeCourtRail","HorseshoeCourtPeg","HorseshoeCourtBack",
	"HorseshoeTargetStake","HorseshoeSpareRack","VillageMarketCrate",
	"VillageMarketBasket","VillageParkedBicycle","VillageGardenWindmill",
	"VillageWindmillGarden","VillageWindmillCache"]
var checks := 0
var failures: Array[String] = []
var completed_throws := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var village := VILLAGE.new()
	scene.add_child(village)
	village.tonico.set_physics_process(false)
	for frame in 3: await physics_frame
	var art: Node3D = village.leisure_art
	check(is_instance_valid(art),"Exterior leisure geometry is integrated in the village")
	if not is_instance_valid(art):
		scene.free()
		quit(1)
		return
	check(not art.is_processing() and not art.is_physics_processing(),"Leisure art has no idle processing loop")
	check(art.find_children("*","Light3D",true,false).is_empty(),"Leisure props add no permanent light sources")
	var bodies: Array[StaticBody3D] = []
	for body in village.solids:
		if body.get_meta("interior_solid_id","") in NEW_SOLIDS:
			bodies.append(body)
		elif body.get_meta("interior_solid_id","") == "WoodenBench" and body.position.distance_to(Vector3(22.2,.55,-27.3)) < .01:
			bodies.append(body)
	for id in NEW_SOLIDS:
		check(bodies.any(func(body): return body.get_meta("interior_solid_id")==id),"Registered physical detail: "+id)
	check(bodies.any(func(body): return body.get_meta("interior_solid_id")=="WoodenBench"),"The new court bench has full-body collision")
	check(village.solids.size()==village.placements.size(),"Collision inventory stays aligned after the new props")
	for body in bodies:
		var index: int = village.solids.find(body)
		var placement: Dictionary = village.placements[index]
		var collider: CollisionShape3D = body.get_child(0)
		check(collider.shape is BoxShape3D and not collider.disabled,"Active box collision for "+body.name)
		check(placement.id==body.get_meta("interior_solid_id") and placement.center.is_equal_approx(body.position) and placement.basis.is_equal_approx(body.basis) and placement.size.is_equal_approx(collider.shape.size),"Geometry inventory matches real transform and dimensions: "+body.name)
		var outline := _footprint(body)
		for home in village.homes.homes:
			check(Geometry2D.intersect_polygons(outline,_home_footprint(home.root)).is_empty(),"New prop stays outside house "+str(home.index+1)+": "+body.name)
	var court: MeshInstance3D = village.get_node_or_null("HorseshoeCourtEarth")
	check(court!=null and court.material_override!=null and court.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Court ground is textured and does not cast a micro-shadow")
	var grass_inside := false
	for p in village.get_meta("wild_grass_points",[]):
		if ART.COURT.has_point(p):
			grass_inside = true
			break
	check(not grass_inside,"Authored court remains clear of generated grass")
	for person in ["Player","Resident"]:
		var actor: CharacterBody3D
		if person=="Player":
			actor = ACTOR.new()
			actor.is_player = true
			actor.controlled_automatically = true
			actor.position = Vector3(-200,.04,200)
		else:
			actor = RESIDENT.new()
			actor.configure({"id":"leisure_physics_resident","position":Vector3(-200,.04,200),"stationary":true,"variant":1})
		scene.add_child(actor)
		actor.set_physics_process(false)
		for frame in 2: await physics_frame
		var collider := _actor_collider(actor)
		check(collider!=null and collider.shape is CapsuleShape3D,person+" uses its production capsule")
		if collider==null:
			actor.free()
			continue
		for point in [ART.PLAY_POINT,ART.CACHE_POINT,VILLAGE.ORIGIN+Vector3(28,0,-33.4),VILLAGE.ORIGIN+Vector3(26.4,0,-29),VILLAGE.ORIGIN+Vector3(29.6,0,-29)]:
			check(_free(actor,point),person+" whole body fits leisure approach "+str(point))
		# Connected approaches from the existing walking route, including the
		# fully open front of the court; no direct teleport across the border.
		_walk(actor,[Vector3(26,0,-13),Vector3(34,0,-19),Vector3(34,0,-24),ART.PLAY_POINT-VILLAGE.ORIGIN,Vector3(28,0,-33.4)],person+" court entry")
		_walk(actor,[Vector3(0,0,1),Vector3(0,0,-8),Vector3(-.5,0,-12),ART.CACHE_POINT-VILLAGE.ORIGIN],person+" windmill cache approach")
		_walk(actor,[Vector3(28,0,-29),Vector3(26.4,0,-29),Vector3(26.4,0,-33),Vector3(29.6,0,-33),Vector3(29.6,0,-29)],person+" walk around the target")
		# Existing central paths and each resident's complete patrol circuit remain
		# valid with the new props present, using swept capsules instead of points.
		for path in [[Vector3(40,0,0),Vector3(-55,0,0)],[Vector3(-55,0,0),Vector3(-67,0,25)],[Vector3(40,0,0),Vector3(40,0,27)],[Vector3(40,0,27),Vector3(60,0,27)]]:
			_walk(actor,path,person+" main village path")
		for index in RESIDENTS.ROUTES.size():
			var circuit: Array = RESIDENTS.ROUTES[index].duplicate()
			circuit.append(circuit[0])
			_walk(actor,circuit,person+" resident route "+str(index))
		for body in bodies:
			_sweep_prop(actor,body,person)
		actor.free()
	# Let actual tweens run. The functional/UI test owns scoring and rewards;
	# these checks guard bounded visual objects and unload cleanup.
	art.throw_finished.connect(func(): completed_throws+=1)
	art.animate_throw(.7,true)
	check(_visible_shoes(art)==1,"First launch shows one bounded horseshoe")
	await create_timer(.35).timeout
	var first: MeshInstance3D = art.get_node("ThrownHorseshoe0")
	check(first.global_position.y>1.5 and first.global_position.z<ART.PLAY_POINT.z and first.global_position.z>ART.TARGET_POINT.z,"Horseshoe follows an elevated arc toward the court target")
	await create_timer(.85).timeout
	check(completed_throws==1 and Vector2(first.global_position.x,first.global_position.z).distance_to(Vector2(ART.TARGET_POINT.x,ART.TARGET_POINT.z))<.30,"Successful throw lands around the real stake and completes once")
	art.animate_throw(.1,false)
	await create_timer(1.2).timeout
	var miss: MeshInstance3D = art.get_node("ThrownHorseshoe1")
	check(completed_throws==2 and Vector2(miss.global_position.x,miss.global_position.z).distance_to(Vector2(ART.TARGET_POINT.x,ART.TARGET_POINT.z))>.60,"Miss remains visibly separated from the target")
	art.animate_throw(.7,true)
	await create_timer(1.2).timeout
	check(_visible_shoes(art)==3 and completed_throws==3,"Three launches retain exactly three completed visual shoes")
	art.animate_throw(.7,true)
	check(_visible_shoes(art)==1,"A new round clears all shoes from the previous round")
	village.set_region_active(false)
	check(not art.visible and _visible_shoes(art)==0,"Leaving Harbor hides an in-flight throw and the leisure visuals")
	for body in bodies: check(body.collision_layer==0,"Inactive new collision: "+body.name)
	art.set_cache_open(true)
	var lid: Node3D = art.get_node("WindmillCacheLid")
	check(lid.rotation.x < -1.8,"Restoring an opened cache while inactive applies the lid state immediately")
	village.set_region_active(true)
	village.tonico.set_physics_process(false)
	for frame in 2: await physics_frame
	check(art.visible and _visible_shoes(art)==0,"Region return does not resurrect a cancelled throw")
	for body in bodies: check(body.collision_layer==1,"Reactivated new collision: "+body.name)
	art.set_cache_open(false)
	await create_timer(.4).timeout
	check(is_zero_approx(lid.rotation.x),"Closing the cache restores its physical presentation")
	art.set_cache_open(true)
	await create_timer(.4).timeout
	check(lid.rotation.x < -1.8 and completed_throws==3,"Opening the cache preserves state without finishing the cancelled throw")
	check(not art.is_processing() and not art.is_physics_processing(),"Finishing all effects leaves no idle art loop")
	print("TRUCKERS_VILLAGE_LEISURE_GEOMETRY checks=",checks," failures=",failures)
	scene.free()
	quit(0 if failures.is_empty() else 1)

func _actor_collider(actor: CharacterBody3D) -> CollisionShape3D:
	for child in actor.get_children():
		if child is CollisionShape3D: return child
	return null

func _free(actor: CharacterBody3D,world_point: Vector3) -> bool:
	var collider := _actor_collider(actor)
	if collider==null: return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	query.transform = Transform3D(Basis.IDENTITY,world_point+Vector3.UP*.04)*collider.transform
	query.collision_mask = 1
	query.exclude = [actor.get_rid()]
	return actor.get_world_3d().direct_space_state.intersect_shape(query).is_empty()

func _walk(actor: CharacterBody3D,local_points: Array,label: String) -> void:
	for index in local_points.size()-1:
		var start: Vector3 = local_points[index]+VILLAGE.ORIGIN
		var finish: Vector3 = local_points[index+1]+VILLAGE.ORIGIN
		check(_free(actor,start) and _free(actor,finish),label+" endpoints fit, segment "+str(index))
		actor.global_position = start+Vector3.UP*.04
		var collision := actor.move_and_collide(finish-start)
		check(collision==null and actor.global_position.distance_to(finish+Vector3.UP*.04)<.01,label+" swept travel succeeds, segment "+str(index))

func _sweep_prop(actor: CharacterBody3D,body: StaticBody3D,label: String) -> void:
	var collider: CollisionShape3D = body.get_child(0)
	var size: Vector3 = collider.shape.size
	var contacted := 0
	# Choose reachable sides by real capsule clearance. A neighbouring crate or
	# rail is allowed to occupy a side; every object must still block a free face.
	for axis in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
		var half: float = absf(axis.x)*size.x*.5+absf(axis.z)*size.z*.5
		var direction: Vector3 = body.global_basis*axis
		var start: Vector3 = body.global_position+direction*(half+.48)
		start.y = 0.0
		if not _free(actor,start): continue
		actor.global_position = start+Vector3.UP*.04
		var collision := actor.move_and_collide(-direction*1.1)
		if collision!=null and collision.get_collider()==body:
			contacted += 1
			check(is_equal_approx(actor.global_position.y,.04),label+" stays on the floor against "+body.name)
	check(contacted>0,label+" swept capsule is stopped by "+body.name)

func _footprint(body: StaticBody3D) -> PackedVector2Array:
	var collider: CollisionShape3D = body.get_child(0)
	var size: Vector3 = collider.shape.size
	return _rectangle(body.global_transform*collider.transform,Vector2(size.x,size.z))

func _home_footprint(home: Node3D) -> PackedVector2Array:
	return _rectangle(home.global_transform,Vector2(13.1,9.5))

func _rectangle(transform: Transform3D,size: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in [Vector3(-size.x*.5,0,-size.y*.5),Vector3(size.x*.5,0,-size.y*.5),Vector3(size.x*.5,0,size.y*.5),Vector3(-size.x*.5,0,size.y*.5)]:
		var at: Vector3 = transform*point
		points.append(Vector2(at.x,at.z))
	return points

func _visible_shoes(art: Node3D) -> int:
	var total := 0
	for child in art.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("ThrownHorseshoe") and child.visible: total+=1
	return total
