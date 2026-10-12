extends SceneTree
## Physical contracts use real player/NPC capsules. Rendered depth and performance
## are measured separately in the production session, never inferred here.
const LAYOUT := preload("res://world/places/amusement_park/AmusementParkLayout.gd")
const SITE := preload("res://world/places/amusement_park/ParkLume.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("AMUSEMENT_GEOMETRY ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("AMUSEMENT_GEOMETRY timeout"); quit(3))
	var stage := Node3D.new()
	root.add_child(stage)
	var park := SITE.new()
	stage.add_child(park)
	var initial := park.get_child_count()
	park.build()
	check(park.get_child_count()==initial,"park build is idempotent")
	var floor_mesh := park.get_node("ParkGround_paving") as MeshInstance3D
	var floor_faces := floor_mesh.mesh.get_faces()
	var facing_up := not floor_faces.is_empty()
	for index in range(0,floor_faces.size(),3):
		# Godot renders clockwise fronts; collision alone accepts both sides.
		var normal := (floor_faces[index+2]-floor_faces[index]).cross(floor_faces[index+1]-floor_faces[index]).normalized()
		facing_up = facing_up and normal.dot(Vector3.UP)>.99
	check(facing_up,"plaza floor front faces are visible from above")
	var room = PLACES.create_place(LAYOUT.HAUNTED_ID)
	check(room != null,"house integrated into production place catalogue")
	if room == null: quit(1); return
	room.position = Vector3(0,0,-3000)
	stage.add_child(room)
	for i in 4: await physics_frame
	# The unsafe overlapping inner returns were removed; the simple circuit is
	# about 130 m. Crossing/curvature regressions live in test_coaster_geometry.
	check(park.coaster_length()>120.0,"coaster has a full recreation circuit")
	check(park.sample_coaster(0).origin.distance_to(park.sample_coaster(park.coaster_length()).origin)<.001,"coaster returns exactly to station")
	var high := 0.0
	var low := INF
	for i in 120:
		var pose := park.sample_coaster(park.coaster_length()*i/120.0)
		high = maxf(high,pose.origin.y)
		low = minf(low,pose.origin.y)
		check(pose.is_finite() and absf(pose.basis.determinant()-1)<.01,"finite upright track pose %d"%i)
		var position2 := Vector2(pose.origin.x,pose.origin.z)
		check(LAYOUT.FOOTPRINT.has_point(position2),"track remains in reserved fairground %d"%i)
	check(high>12 and low>.15,"real climb and descent stay above floor (low %.3f, high %.3f)"%[low,high])
	check(park.carriage.transform.origin.distance_to(park.curve.sample_baked(0))<.001,"parked carriage rests at boarding station")
	var grouped := {}
	for mesh in room.model.find_children("*","MeshInstance3D",true,false):
		var id := str(mesh.get_meta("interior_solid_id",""))
		if id.is_empty(): continue
		var bounds: AABB = (room.global_transform.affine_inverse()*mesh.global_transform)*mesh.get_aabb()
		if bounds.position.y>2.1 or bounds.end.y<.06: continue
		grouped[id] = grouped[id].merge(bounds) if grouped.has(id) else bounds
	for id in grouped:
		var covered := false
		for body in room.solid_bodies:
			if str(body.get_meta("interior_solid_id",""))==id:
				var bounds: AABB = body.get_meta("bounds")
				covered = bounds.grow(.005).encloses(grouped[id])
		check(covered,"house solid fully covers visual: "+str(id))
	check(grouped.size()>=15,"house has independently classified furniture and walls")
	var outside_points := [LAYOUT.ENTRY,LAYOUT.BOARDING,LAYOUT.HAUNTED_ENTRY,
		LAYOUT.ORIGIN+Vector3(29,.08,20),LAYOUT.ORIGIN+Vector3(-31,.08,27),
		LAYOUT.ORIGIN+Vector3(28,.08,27),LAYOUT.ORIGIN+Vector3(-2,.08,-28),LAYOUT.ORIGIN+Vector3(31,.08,-3)]
	for player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player = player
		actor.controlled_automatically = true
		stage.add_child(actor)
		actor.set_physics_process(false)
		actor.collision_mask = 1
		for i in 3: await physics_frame
		var who := "Dante" if player else "NPC visitor"
		# Real stepping logic must cross the platform lip, not merely fit at its
		# destination. Only this body is pavement; benches remain solid furniture.
		actor.teleport(LAYOUT.ORIGIN+Vector3(-3.4,.08,15))
		actor.speed = 3.5
		actor.automatic_direction = Vector3.ZERO
		actor.set_physics_process(true)
		for i in 8: await physics_frame
		actor.automatic_direction = Vector3.LEFT
		for i in 120:
			await physics_frame
			if actor.global_position.x<LAYOUT.BOARDING.x+.12: break
		actor.automatic_direction = Vector3.ZERO
		var capsule_node := actor.get_child(0) as CollisionShape3D
		var capsule := capsule_node.shape as CapsuleShape3D
		var foot_offset := capsule_node.position.y-capsule.height*.5
		var foot_y := actor.global_position.y+foot_offset
		check(actor.global_position.x<LAYOUT.BOARDING.x+.20 and absf(foot_y-.12)<.005,who+" actual walking climbs station deck (foot %.4f, x %.3f)"%[foot_y,actor.global_position.x])
		actor.automatic_direction = Vector3.RIGHT
		for i in 120:
			await physics_frame
			if actor.global_position.x>LAYOUT.ORIGIN.x-3.5: break
		actor.automatic_direction = Vector3.ZERO
		for i in 12: await physics_frame
		check(actor.global_position.x>LAYOUT.ORIGIN.x-3.8 and actor.global_position.y<.08,who+" actual walking leaves the deck onto plaza")
		actor.teleport(LAYOUT.ORIGIN+Vector3(12,.08,24))
		var raised_foot := 0.0
		actor.automatic_direction = Vector3.BACK
		for i in 90:
			await physics_frame
			raised_foot = maxf(raised_foot,actor.global_position.y+foot_offset)
		actor.automatic_direction = Vector3.ZERO
		check(raised_foot<.10 and (not player or actor.global_position.z<LAYOUT.ORIGIN.z+25.65),who+" bench remains solid while NPC may steer around (highest foot %.4f)"%raised_foot)
		actor.set_physics_process(false)
		for i in outside_points.size():
			check(_clear(actor,outside_points[i]),who+" full body at park interaction %d"%i)
			check(_supported(stage,outside_points[i]),who+" floor at park interaction %d"%i)
		var route := LAYOUT.house_route()
		for i in route.size():
			var point: Vector3 = room.to_global(route[i])
			check(_clear(actor,point),who+" house route body clearance %d"%i)
			check(_supported(stage,point),who+" house route floor support %d"%i)
			if i>0:
				var start := actor.global_transform
				start.origin = room.to_global(route[i-1])
				check(not actor.test_move(start,route[i]-route[i-1]),who+" house route swept passage %d"%i)
		for point in [LAYOUT.HOUSE_SPAWN,LAYOUT.HOUSE_EXIT,Vector3(-6.4,.06,-5.2),Vector3(6.4,.06,-5.2)]:
			check(_clear(actor,room.to_global(point)),who+" admission/exit/secret body clearance "+str(point))
		var exit_pose := actor.global_transform
		exit_pose.origin = room.to_global(LAYOUT.HOUSE_EXIT)
		check(actor.test_move(exit_pose,Vector3.BACK*4.0),who+" closed exit door blocks walking into exterior void until transfer interaction")
		var tested := 0
		for body in room.solid_bodies:
			var id := str(body.get_meta("interior_solid_id",""))
			if id == "Floor": continue
			var bounds: AABB = body.get_meta("bounds")
			if bounds.end.y<.15: continue
			for direction in [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]:
				var extent: float = bounds.size.x*.5 if absf(direction.x)>.5 else bounds.size.z*.5
				var start: Vector3 = bounds.get_center()+direction*(extent+.9)
				start.y = .04
				if absf(start.x)>8.5 or absf(start.z)>7: continue
				if not _clear(actor,room.to_global(start)): continue
				var pose := actor.global_transform
				pose.origin = room.to_global(start)
				check(actor.test_move(pose,-direction*(extent*2+1.8)),who+" long sweep blocks "+id)
				tested += 1
		check(tested>=12,who+" exercised furniture edges and wall boundaries")
		# Guardrails and scenery must also resist a large outdoor step.
		for row in [[Vector3(-2,.08,-10),Vector3(-8,0,0)], [Vector3(35,.08,25),Vector3(10,0,0)], [Vector3(20,.08,-1),Vector3(0,0,-8)], [Vector3(-7,.16,15),Vector3(-8,0,0)]]:
			var pose := actor.global_transform
			pose.origin = LAYOUT.ORIGIN+row[0]
			check(actor.test_move(pose,row[1]),who+" outdoor full sweep blocks fence/facade")
		actor.free()
	check(room.model.get_node("FrontWall-1").mesh.size.y>3.0,"first-person front wall does not retain orthographic cutaway")
	check(room.model.get_node("ExitDoorPanel").mesh.size.y>2.6,"first-person exit door retains its full visible panel")
	check(room.model.find_children("*","SubViewport",true,false).is_empty(),"house shares native 3D renderer without extra viewports")
	check(park.get_node("BoardingDeckBody").get_meta("pedestrian_step",false) and not park.get_node("ParkSolids").get_meta("pedestrian_step",false),"pavement step metadata never leaks onto furniture and fences")
	stage.free()
	await process_frame
	print("AMUSEMENT_GEOMETRY_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _clear(actor: CharacterBody3D, point: Vector3) -> bool:
	var pose := actor.global_transform
	pose.origin = point
	return not actor.test_move(pose,Vector3.UP*.001)

func _supported(stage: Node3D, point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.1,point-Vector3.UP*.38,1)
	var hit := stage.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.normal.y>.8 and absf(hit.position.y-point.y)<.35
